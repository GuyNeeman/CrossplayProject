package xyz.crossplayproject;

import com.google.gson.Gson;
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

    private final ConcurrentHashMap<String, byte[]> skinCache = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<UUID, Long> recentAttackers = new ConcurrentHashMap<>();
    private static final long ATTACK_VISIBLE_MS = 400;
    private static final ConcurrentHashMap<UUID, BlockDamageRecord> activeBreaks = new ConcurrentHashMap<>();

    // Thread-safe snapshots updated by refreshSnapshots() on the main thread every 2 ticks.
    private volatile String playersSnapshot = "[]";
    private volatile String mobsSnapshot    = "[]";
    private volatile String worldSnapshot   = "{}";
    private volatile String spawnSnapshot   = "{}";

    /** Called from the main thread every 2 ticks (CrossplayPackage runTaskTimer). */
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
            this.startMs = startMs; this.hardness = hardness;
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
        if (hardness < 0) return;
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

        spark.get("/blockdamage", (req, res) -> {
            res.type("application/json");
            long now = System.currentTimeMillis();
            List<BlockDamageInfo> list = new ArrayList<>();
            for (BlockDamageRecord rec : activeBreaks.values()) {
                double elapsed = (now - rec.startMs) / 1000.0;
                double breakTime = Math.max(0.05, rec.hardness * 1.5);
                int stage = (int) Math.min(9, Math.floor(elapsed / breakTime * 10));
                list.add(new BlockDamageInfo(rec.x, rec.y, rec.z, stage));
            }
            return gson.toJson(list);
        });

        // Inventory: Roblox player is now a real Bukkit player — read directly.
        spark.get("/inventory/:username", (req, res) -> {
            res.type("application/json");
            String username = req.params(":username");
            try {
                List<InventorySlot> slots = Bukkit.getScheduler()
                        .callSyncMethod(JavaPlugin.getPlugin(CrossplayPackage.class), () -> {
                            org.bukkit.entity.Player p = Bukkit.getPlayer(username);
                            if (p == null) return List.<InventorySlot>of();
                            List<InventorySlot> result = new ArrayList<>();
                            ItemStack[] contents = p.getInventory().getContents();
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
                logger.log(Level.WARNING, "[Crossplay] Inventory read failed for " + username, e);
                return "[]";
            }
        });

        // Event relay: drains server→Roblox events (title, actionbar, health, sound)
        // captured by the MCProtocolLib session listener.
        spark.get("/events/:username", (req, res) -> {
            res.type("application/json");
            String username = req.params(":username");
            RobloxBotSession session = RobloxSessionManager.get(username);
            if (session == null) return "[]";
            return gson.toJson(session.drain());
        });

        // Skin proxy — fetches PNG from Crafatar and caches it for Roblox HTTP requests.
        spark.get("/skin/:uuid", (req, res) -> {
            String uuid = req.params(":uuid");
            if (uuid == null || uuid.isEmpty()) { res.status(400); return "Missing UUID"; }

            byte[] skinData = skinCache.get(uuid);
            if (skinData == null) {
                try {
                    URL url = new URL("https://crafatar.com/skins/" + uuid);
                    HttpURLConnection conn = (HttpURLConnection) url.openConnection();
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
                        return "Skin not found (Crafatar returned " + status + ")";
                    }
                } catch (Exception e) {
                    logger.log(Level.WARNING, "[Crossplay] Skin fetch failed for " + uuid, e);
                    res.status(500);
                    return "Error: " + e.getMessage();
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
            if (player.getGameMode() == GameMode.SPECTATOR) continue;
            // Exclude our own MCProtocolLib bot connections — Roblox renders their own bodies.
            if (RobloxSessionManager.isBot(player.getName())) continue;

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
                    if (entity instanceof LivingEntity le
                            && !(entity instanceof org.bukkit.entity.Player)) {
                        mobPositions.add(new MobPosition(
                                le.getUniqueId().toString(),
                                le.getLocation().getX(), le.getLocation().getY(), le.getLocation().getZ(),
                                le.getLocation().getYaw(), le.getLocation().getPitch(),
                                le.getType().name()
                        ));
                    } else if (entity instanceof TNTPrimed tnt) {
                        mobPositions.add(new MobPosition(
                                tnt.getUniqueId().toString(),
                                tnt.getLocation().getX(), tnt.getLocation().getY(), tnt.getLocation().getZ(),
                                0, 0, "PRIMED_TNT"
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

    // ── Inner data classes ────────────────────────────────────────────────────

    private static class PlayerPosition {
        private String uuid, name;
        private Material mainItem, offItem;
        private double x, y, z;
        private float yaw, pitch;
        private boolean crouch, isAttacking;

        public PlayerPosition(String uuid, String name, Material mainItem, Material offItem,
                              double x, double y, double z, float yaw, float pitch,
                              boolean crouch, boolean isAttacking) {
            this.uuid = uuid; this.name = name;
            this.mainItem = mainItem; this.offItem = offItem;
            this.x = x; this.y = y; this.z = z;
            this.yaw = yaw; this.pitch = pitch;
            this.crouch = crouch; this.isAttacking = isAttacking;
        }
    }

    private static class MobPosition {
        private String uuid, mobType;
        private double x, y, z;
        private float yaw, pitch;

        public MobPosition(String uuid, double x, double y, double z,
                           float yaw, float pitch, String mobType) {
            this.uuid = uuid; this.x = x; this.y = y; this.z = z;
            this.yaw = yaw; this.pitch = pitch; this.mobType = mobType;
        }
    }

    private static class WorldState {
        private long time;
        private boolean thundering, raining;
        public WorldState(long time, boolean thundering, boolean raining) {
            this.time = time; this.thundering = thundering; this.raining = raining;
        }
    }

    private static class SpawnLocation {
        private double x, y, z;
        public SpawnLocation(double x, double y, double z) { this.x = x; this.y = y; this.z = z; }
    }

    private static class BlockDamageInfo {
        private int x, y, z, stage;
        public BlockDamageInfo(int x, int y, int z, int stage) {
            this.x = x; this.y = y; this.z = z; this.stage = stage;
        }
    }

    private static class InventorySlot {
        private int slot, count;
        private String item;
        public InventorySlot(int slot, String item, int count) {
            this.slot = slot; this.item = item; this.count = count;
        }
    }
}
