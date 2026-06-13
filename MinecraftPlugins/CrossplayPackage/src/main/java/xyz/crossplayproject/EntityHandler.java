package xyz.crossplayproject;

import com.google.gson.Gson;
import net.citizensnpcs.api.npc.NPC;
import org.bukkit.*;
import org.bukkit.entity.Entity;
import org.bukkit.entity.LivingEntity;
import org.bukkit.entity.TNTPrimed;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.block.BlockBreakEvent;
import org.bukkit.event.block.BlockDamageAbortEvent;
import org.bukkit.event.block.BlockDamageEvent;
import org.bukkit.event.entity.EntityDamageByEntityEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.plugin.java.JavaPlugin;
import spark.Service;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.logging.Level;
import java.util.logging.Logger;

public class EntityHandler implements Listener {

    private static final Logger logger = Logger.getLogger(EntityHandler.class.getName());
    private final Gson gson = new Gson();
    // Skin PNG cache: UUID string → raw PNG bytes (populated on first request per UUID)
    private final ConcurrentHashMap<String, byte[]> skinCache = new ConcurrentHashMap<>();
    // Tracks when each player last landed an attack hit (epoch ms); used for isAttacking flag
    private static final ConcurrentHashMap<UUID, Long> recentAttackers = new ConcurrentHashMap<>();
    private static final long ATTACK_VISIBLE_MS = 400;

    // Tracks blocks currently being mined: player UUID → damage record
    private static final ConcurrentHashMap<UUID, BlockDamageRecord> activeBreaks = new ConcurrentHashMap<>();

    // Thread-safe snapshots of Bukkit world state; refreshed from the main thread every 2 ticks
    // by CrossplayPackage's runTaskTimer so Spark threads never touch Bukkit API directly.
    private volatile String playersSnapshot = "[]";
    private volatile String mobsSnapshot    = "[]";
    private volatile String worldSnapshot   = "{}";
    private volatile String spawnSnapshot   = "{}";

    /** Called from the main thread every 2 ticks (see CrossplayPackage). */
    public void refreshSnapshots() {
        playersSnapshot = gson.toJson(getPlayerPositions());
        mobsSnapshot    = gson.toJson(getMobData());
        worldSnapshot   = gson.toJson(getWorldState());
        World w = Bukkit.getWorlds().getFirst();
        Location spawn = w.getSpawnLocation();
        spawnSnapshot   = gson.toJson(new SpawnLocation(spawn.getX(), spawn.getY(), spawn.getZ()));
    }

    private static class BlockDamageRecord {
        final int x, y, z;
        final long startMs;
        final float hardness;

        BlockDamageRecord(int x, int y, int z, long startMs, float hardness) {
            this.x = x; this.y = y; this.z = z;
            this.startMs = startMs;
            this.hardness = hardness;
        }
    }

    @EventHandler
    public void onEntityDamageByEntity(EntityDamageByEntityEvent event) {
        if (event.getDamager() instanceof org.bukkit.entity.Player attacker) {
            recentAttackers.put(attacker.getUniqueId(), System.currentTimeMillis());
        }
    }

    @EventHandler
    public void onBlockDamage(BlockDamageEvent event) {
        org.bukkit.block.Block b = event.getBlock();
        float hardness = b.getType().getHardness();
        if (hardness < 0) return; // unbreakable
        activeBreaks.put(event.getPlayer().getUniqueId(),
                new BlockDamageRecord(b.getX(), b.getY(), b.getZ(), System.currentTimeMillis(), hardness));
    }

    @EventHandler
    public void onBlockDamageAbort(BlockDamageAbortEvent event) {
        activeBreaks.remove(event.getPlayer().getUniqueId());
    }

    @EventHandler
    public void onBlockBreak(BlockBreakEvent event) {
        activeBreaks.remove(event.getPlayer().getUniqueId());
    }

    @EventHandler
    public void onPlayerQuit(PlayerQuitEvent event) {
        UUID uuid = event.getPlayer().getUniqueId();
        recentAttackers.remove(uuid);
        activeBreaks.remove(uuid);
    }

    public void setupRoutes(Service spark) {
        spark.get("/favicon.ico", (req, res) -> "");

        spark.get("/players", (req, res) -> {
            res.type("application/json");
            return playersSnapshot;
        });

        spark.get("/mobs", (req, res) -> {
            res.type("application/json");
            return mobsSnapshot;
        });

        spark.get("/world", (req, res) -> {
            res.type("application/json");
            return worldSnapshot;
        });

        spark.get("/spawn", (req, res) -> {
            res.type("application/json");
            return spawnSnapshot;
        });

        // /blockdamage reads only ConcurrentHashMap entries populated by event handlers — safe from any thread.
        spark.get("/blockdamage", (req, res) -> {
            res.type("application/json");
            long now = System.currentTimeMillis();
            List<BlockDamageInfo> list = new ArrayList<>();
            for (BlockDamageRecord rec : activeBreaks.values()) {
                double elapsedSec = (now - rec.startMs) / 1000.0;
                // Minecraft break time ≈ hardness * 1.5 seconds for hand; clamp stage to 0-9
                double breakTimeSec = Math.max(0.05, rec.hardness * 1.5);
                int stage = (int) Math.min(9, Math.floor(elapsedSec / breakTimeSec * 10));
                list.add(new BlockDamageInfo(rec.x, rec.y, rec.z, stage));
            }
            return gson.toJson(list);
        });

        // Inventory must be read on the main thread; callSyncMethod bridges Spark → Bukkit safely.
        spark.get("/inventory/:username", (req, res) -> {
            res.type("application/json");
            String username = req.params(":username");
            try {
                List<InventorySlot> slots = Bukkit.getScheduler()
                        .callSyncMethod(JavaPlugin.getPlugin(CrossplayPackage.class), () -> {
                            NPC npc = NPCHandler.getNPC(username);
                            if (npc == null || !npc.isSpawned()
                                    || !(npc.getEntity() instanceof org.bukkit.entity.Player npcPlayer)) {
                                return List.<InventorySlot>of();
                            }
                            List<InventorySlot> result = new ArrayList<>();
                            ItemStack[] contents = npcPlayer.getInventory().getContents();
                            for (int i = 0; i < contents.length; i++) {
                                ItemStack item = contents[i];
                                if (item != null && item.getType() != Material.AIR) {
                                    result.add(new InventorySlot(i, item.getType().name(), item.getAmount()));
                                }
                            }
                            return result;
                        }).get(5, TimeUnit.SECONDS);
                return gson.toJson(slots);
            } catch (Exception e) {
                logger.log(Level.WARNING, "[Crossplay] Failed to read inventory for " + username, e);
                return "[]";
            }
        });

        // Geyser-style event relay: drains intercepted packets (title, actionbar, sound, health)
        // queued by PacketInterceptor for this Roblox player's NPC.
        spark.get("/events/:username", (req, res) -> {
            res.type("application/json");
            String username = req.params(":username");
            List<PacketInterceptor.RobloxEvent> events = PacketInterceptor.drain(username);
            return gson.toJson(events);
        });

        // Skin proxy: fetches the Minecraft skin PNG from Crafatar and caches it.
        // Roblox requests from this endpoint so it never has to reach an external HTTPS server.
        spark.get("/skin/:uuid", (req, res) -> {
            String uuid = req.params(":uuid");
            if (uuid == null || uuid.isEmpty()) {
                res.status(400);
                return "Missing UUID";
            }

            byte[] skinData = skinCache.get(uuid);
            if (skinData == null) {
                try {
                    URL skinUrl = new URL("https://crafatar.com/skins/" + uuid);
                    HttpURLConnection conn = (HttpURLConnection) skinUrl.openConnection();
                    conn.setConnectTimeout(6000);
                    conn.setReadTimeout(10000);
                    conn.setRequestProperty("User-Agent", "CrossplayProject/1.0");

                    int status = conn.getResponseCode();
                    if (status == 200) {
                        try (InputStream in = conn.getInputStream()) {
                            skinData = in.readAllBytes();
                            skinCache.put(uuid, skinData);
                        }
                    } else {
                        res.status(404);
                        return "Skin not found for UUID: " + uuid + " (Crafatar returned " + status + ")";
                    }
                } catch (Exception e) {
                    logger.log(Level.WARNING, "Failed to fetch skin for UUID " + uuid, e);
                    res.status(500);
                    return "Error fetching skin: " + e.getMessage();
                }
            }

            res.type("image/png");
            res.header("Cache-Control", "public, max-age=86400");
            res.raw().getOutputStream().write(skinData);
            res.raw().getOutputStream().flush();
            return res.raw();
        });
    }

    private List<PlayerPosition> getPlayerPositions() {
        List<PlayerPosition> positions = new ArrayList<>();
        long now = System.currentTimeMillis();
        for (org.bukkit.entity.Player player : Bukkit.getOnlinePlayers()) {
            // Never expose spectator-mode players to Roblox
            if (player.getGameMode() == GameMode.SPECTATOR) continue;

            boolean isAttacking = recentAttackers.containsKey(player.getUniqueId())
                    && now - recentAttackers.get(player.getUniqueId()) < ATTACK_VISIBLE_MS;

            positions.add(new PlayerPosition(
                    player.getUniqueId().toString(),
                    player.getName(),
                    player.getInventory().getItemInMainHand().getType(),
                    player.getInventory().getItemInOffHand().getType(),
                    player.getLocation().getX(),
                    player.getLocation().getY(),
                    player.getLocation().getZ(),
                    player.getLocation().getYaw(),
                    player.getLocation().getPitch(),
                    player.isSneaking(),
                    isAttacking
            ));
        }
        return positions;
    }

    private List<MobPosition> getMobData() {
        List<MobPosition> mobPositions = new ArrayList<>();
        for (World world : Bukkit.getServer().getWorlds()) {
            for (Chunk chunk : world.getLoadedChunks()) {
                for (Entity entity : chunk.getEntities()) {
                    if (entity instanceof LivingEntity livingEntity && !(entity instanceof org.bukkit.entity.Player)) {
                        mobPositions.add(new MobPosition(
                                livingEntity.getUniqueId().toString(),
                                livingEntity.getLocation().getX(),
                                livingEntity.getLocation().getY(),
                                livingEntity.getLocation().getZ(),
                                livingEntity.getLocation().getYaw(),
                                livingEntity.getLocation().getPitch(),
                                livingEntity.getType().name()
                        ));
                    } else if (entity instanceof TNTPrimed primedTNT) {
                        Location tntLocation = primedTNT.getLocation();
                        mobPositions.add(new MobPosition(
                                primedTNT.getUniqueId().toString(),
                                tntLocation.getX(),
                                tntLocation.getY(),
                                tntLocation.getZ(),
                                0,
                                0,
                                "PRIMED_TNT"
                        ));
                    }
                }
            }
        }
        return mobPositions;
    }

    private WorldState getWorldState() {
        World world = Bukkit.getServer().getWorlds().getFirst();
        return new WorldState(world.getTime(), world.isThundering(), world.hasStorm());
    }

    private static class PlayerPosition {
        private String uuid;
        private String name;
        private Material mainItem;
        private Material offItem;
        private double x;
        private double y;
        private double z;
        private float yaw;
        private float pitch;
        private boolean crouch;
        private boolean isAttacking;

        public PlayerPosition(String uuid, String name, Material mainItem, Material offItem,
                              double x, double y, double z, float yaw, float pitch,
                              boolean crouch, boolean isAttacking) {
            this.uuid = uuid;
            this.name = name;
            this.mainItem = mainItem;
            this.offItem = offItem;
            this.x = x;
            this.y = y;
            this.z = z;
            this.yaw = yaw;
            this.pitch = pitch;
            this.crouch = crouch;
            this.isAttacking = isAttacking;
        }
    }

    private static class MobPosition {
        private String uuid;
        private double x;
        private double y;
        private double z;
        private float yaw;
        private float pitch;
        private String mobType;

        public MobPosition(String uuid, double x, double y, double z, float yaw, float pitch, String mobType) {
            this.uuid = uuid;
            this.x = x;
            this.y = y;
            this.z = z;
            this.yaw = yaw;
            this.pitch = pitch;
            this.mobType = mobType;
        }
    }

    private static class WorldState {
        private long time;
        private boolean thundering;
        private boolean raining;

        public WorldState(long time, boolean thundering, boolean raining) {
            this.time = time;
            this.thundering = thundering;
            this.raining = raining;
        }
    }

    private static class SpawnLocation {
        private double x;
        private double y;
        private double z;

        public SpawnLocation(double x, double y, double z) {
            this.x = x;
            this.y = y;
            this.z = z;
        }
    }

    private static class BlockDamageInfo {
        private int x, y, z, stage;

        public BlockDamageInfo(int x, int y, int z, int stage) {
            this.x = x; this.y = y; this.z = z; this.stage = stage;
        }
    }

    private static class InventorySlot {
        private int slot;
        private String item;
        private int count;

        public InventorySlot(int slot, String item, int count) {
            this.slot = slot;
            this.item = item;
            this.count = count;
        }
    }
}
