package xyz.crossplayproject;

import com.google.gson.Gson;
import net.citizensnpcs.api.CitizensAPI;
import net.citizensnpcs.api.npc.NPC;
import net.citizensnpcs.trait.SkinTrait;
import org.bukkit.Bukkit;
import org.bukkit.Location;
import org.bukkit.Material;
import org.bukkit.World;
import org.bukkit.entity.EntityType;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerCommandPreprocessEvent;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.server.ServerCommandEvent;
import org.bukkit.inventory.ItemStack;
import org.bukkit.plugin.java.JavaPlugin;
import org.bukkit.scheduler.BukkitRunnable;
import org.bukkit.util.Vector;
import spark.Request;
import spark.Response;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.logging.Level;

public class NPCHandler implements Listener {

    // ConcurrentHashMap: getNPC() and getConnectedPlayerNames() are called from Spark threads.
    private static final Map<String, NPC> npcs = new ConcurrentHashMap<>();
    private static final Map<String, BukkitRunnable> currentTasks = new HashMap<>();
    /** Stores each NPC's Bukkit entity UUID so we can remove it from the tab list after despawn. */
    private static final Map<String, UUID> npcUUIDs = new HashMap<>();

    public static Set<String> getConnectedPlayerNames() {
        return Collections.unmodifiableSet(npcs.keySet());
    }

    public static NPC getNPC(String username) {
        return npcs.get(username);
    }

    // ── Event Handlers ────────────────────────────────────────────────────────

    @EventHandler
    public void onPlayerJoin(PlayerJoinEvent event) {
        // Send tab-list ADD for every online Roblox NPC to the newly joined player.
        new BukkitRunnable() {
            @Override
            public void run() {
                Player joined = event.getPlayer();
                if (!joined.isOnline()) return;
                for (NPC npc : npcs.values()) {
                    if (npc.isSpawned() && npc.getEntity() instanceof Player npcPlayer) {
                        PacketUtils.addToTabList(npcPlayer, List.of(joined));
                    }
                }
            }
        }.runTaskLater(JavaPlugin.getPlugin(CrossplayPackage.class), 5L);
    }

    /**
     * Intercepts player-typed commands that reference Roblox player names.
     * Covers: /tp, /give, /kill
     */
    @EventHandler
    public void onPlayerCommand(PlayerCommandPreprocessEvent event) {
        // Strip leading slash and split
        String[] parts = event.getMessage().trim().replaceFirst("^/", "").split("\\s+");
        if (parts.length == 0) return;

        String cmd = parts[0].toLowerCase();

        if (cmd.equals("tp") && parts.length == 2) {
            NPC npc = npcs.get(parts[1]);
            if (npc != null && npc.isSpawned()) {
                event.setCancelled(true);
                event.getPlayer().teleport(npc.getEntity().getLocation());
                event.getPlayer().sendMessage("§7[RB]§f Teleported to Roblox player §e" + parts[1]);
            }
        } else if (cmd.equals("tp") && parts.length == 3) {
            NPC npc = npcs.get(parts[2]);
            if (npc != null && npc.isSpawned()) {
                event.setCancelled(true);
                Player target = Bukkit.getPlayer(parts[1]);
                if (target != null) {
                    target.teleport(npc.getEntity().getLocation());
                    event.getPlayer().sendMessage(
                            "§7[RB]§f Teleported §e" + parts[1] + "§f to Roblox player §e" + parts[2]);
                } else {
                    event.getPlayer().sendMessage("§cPlayer §e" + parts[1] + "§c not found.");
                }
            }
        } else if (cmd.equals("give") && parts.length >= 3) {
            handleGive(parts, event.getPlayer().getName());
            if (npcs.containsKey(parts[1])) event.setCancelled(true);
        } else if (cmd.equals("kill") && parts.length == 2 && npcs.containsKey(parts[1])) {
            event.setCancelled(true);
            String robloxName = parts[1];
            new BukkitRunnable() {
                @Override public void run() { PlayerUpdate.despawnNPC(robloxName); }
            }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));
            event.getPlayer().sendMessage("§7[RB]§f Removed Roblox player §e" + robloxName);
        }
    }

    /** Intercepts console commands that reference Roblox player names. */
    @EventHandler
    public void onServerCommand(ServerCommandEvent event) {
        String[] parts = event.getCommand().trim().split("\\s+");
        if (parts.length == 0) return;
        String cmd = parts[0].toLowerCase();

        if (cmd.equals("give") && parts.length >= 3 && npcs.containsKey(parts[1])) {
            event.setCancelled(true);
            handleGive(parts, "Console");
        } else if (cmd.equals("kill") && parts.length == 2 && npcs.containsKey(parts[1])) {
            event.setCancelled(true);
            String robloxName = parts[1];
            new BukkitRunnable() {
                @Override public void run() { PlayerUpdate.despawnNPC(robloxName); }
            }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));
            Bukkit.getLogger().info("[RB] Removed Roblox player " + robloxName);
        } else if (cmd.equals("tp") && parts.length == 2 && npcs.containsKey(parts[1])) {
            // /tp <robloxname> from console doesn't make sense (no sender position), skip
        }
    }

    private void handleGive(String[] parts, String senderName) {
        String robloxName = parts[1];
        NPC npc = npcs.get(robloxName);
        if (npc == null || !npc.isSpawned() || !(npc.getEntity() instanceof Player npcPlayer)) return;

        Material material = Material.matchMaterial(parts[2]);
        if (material == null) {
            Bukkit.getLogger().warning("[RB] /give: unknown material '" + parts[2] + "'");
            return;
        }
        int count = 1;
        if (parts.length >= 4) {
            try { count = Math.min(Math.max(Integer.parseInt(parts[3]), 1), 64); }
            catch (NumberFormatException ignored) {}
        }
        final int finalCount = count;
        new BukkitRunnable() {
            @Override public void run() {
                npcPlayer.getInventory().addItem(new ItemStack(material, finalCount));
                Bukkit.getLogger().info("[RB] Gave " + finalCount + "x " + material.name() + " to Roblox player " + robloxName);
            }
        }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    public void cleanup() {
        for (BukkitRunnable task : currentTasks.values()) task.cancel();
        currentTasks.clear();

        for (Map.Entry<String, NPC> entry : npcs.entrySet()) {
            UUID uuid = npcUUIDs.get(entry.getKey());
            if (uuid != null) PacketUtils.removeFromTabList(uuid, Bukkit.getOnlinePlayers());
            if (entry.getValue().isSpawned()) entry.getValue().despawn();
        }
        npcs.clear();
        npcUUIDs.clear();
    }

    public void setupRoutes(spark.Service spark) {
        spark.post("/npc", NPCHandler::handleDataRequest);
    }

    public void disabledRoute(spark.Service spark) {
        spark.post("/npc", NPCHandler::handleDisabledRequest);
    }

    private static String handleDisabledRequest(Request req, Response res) {
        res.status(503);
        return "Citizens plugin not found. Module Disabled. NPC cannot be spawned.";
    }

    private static String handleDataRequest(Request req, Response res) {
        try {
            Gson gson = new Gson();
            PlayerUpdate player = gson.fromJson(req.body(), PlayerUpdate.class);
            new BukkitRunnable() {
                public void run() { player.execute(); }
            }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));
            return "OK";
        } catch (Exception e) {
            JavaPlugin.getPlugin(CrossplayPackage.class).getLogger()
                    .log(Level.SEVERE, "Error in NPCHandler", e);
            res.status(500);
            return "Internal Server Error";
        }
    }

    // ── NPC Actions ───────────────────────────────────────────────────────────

    static class PlayerUpdate {
        private final String user;
        private final double x, y, z;
        private final float yaw, pitch;
        private final boolean disconnect;

        public PlayerUpdate(String user, double x, double y, double z,
                            float yaw, float pitch, boolean disconnect) {
            this.user = user;
            this.x = x; this.y = y; this.z = z;
            this.yaw = yaw; this.pitch = pitch;
            this.disconnect = disconnect;
        }

        public void execute() {
            if (disconnect) { despawnNPC(user); return; }

            World world = Bukkit.getWorlds().getFirst();
            if (world == null) { Bukkit.getLogger().warning("World 0 not found!"); return; }

            Location target = new Location(world, x + 0.5, y, z + 0.5, yaw, pitch);
            NPC npc = npcs.get(user);
            if (npc != null && npc.isSpawned()) {
                moveNPC(user, npc, target);
            } else {
                spawnNPC(user, target);
            }
        }

        private void spawnNPC(String user, Location targetLocation) {
            NPC npc = CitizensAPI.getNPCRegistry().createNPC(EntityType.PLAYER, user);
            SkinTrait skinTrait = npc.getOrAddTrait(SkinTrait.class);
            skinTrait.setSkinName(user, true);
            npc.spawn(targetLocation);
            npcs.put(user, npc);

            // Citizens removes the NPC from the client tab list right after spawning.
            // Wait 2 ticks for Citizens to finish, then re-inject ADD_PLAYER — same
            // mechanism as Floodgate/Geyser — and install the Geyser-style packet interceptor.
            new BukkitRunnable() {
                @Override
                public void run() {
                    if (!npc.isSpawned() || !(npc.getEntity() instanceof Player npcPlayer)) return;
                    UUID uuid = npcPlayer.getUniqueId();
                    npcUUIDs.put(user, uuid);
                    PacketUtils.addToTabList(npcPlayer, Bukkit.getOnlinePlayers());
                    PacketInterceptor.inject(user, npcPlayer);
                }
            }.runTaskLater(JavaPlugin.getPlugin(CrossplayPackage.class), 2L);

            Bukkit.broadcastMessage("§f§7[RB]§e " + user + " joined the game");
        }

        static void despawnNPC(String user) {
            NPC npc = npcs.get(user);
            if (npc == null) return;

            if (currentTasks.containsKey(user)) {
                currentTasks.get(user).cancel();
                currentTasks.remove(user);
            }

            // Remove packet interceptor before despawning
            if (npc.isSpawned() && npc.getEntity() instanceof Player npcPlayer) {
                PacketInterceptor.remove(user, npcPlayer);
            }

            UUID uuid = npcUUIDs.remove(user);
            if (npc.isSpawned()) npc.despawn();
            npcs.remove(user);

            if (uuid != null) PacketUtils.removeFromTabList(uuid, Bukkit.getOnlinePlayers());
            Bukkit.broadcastMessage("§f§7[RB]§e " + user + " left the game");
        }

        private static final double SPEED = 0.3;

        private void moveNPC(String user, NPC npc, Location targetLocation) {
            if (currentTasks.containsKey(user)) currentTasks.get(user).cancel();

            Location currentLocation = npc.getEntity().getLocation();
            double distance = currentLocation.distance(targetLocation);
            if (distance < 0.1) return;

            Vector direction = targetLocation.toVector().subtract(currentLocation.toVector()).normalize();
            double ticks = distance / SPEED;

            BukkitRunnable task = new BukkitRunnable() {
                double progress = 0;

                @Override
                public void run() {
                    if (progress >= ticks) {
                        npc.teleport(targetLocation, org.bukkit.event.player.PlayerTeleportEvent.TeleportCause.PLUGIN);
                        cancel();
                        currentTasks.remove(user);
                        return;
                    }
                    progress += 1;
                    Vector next = currentLocation.toVector().add(direction.clone().multiply(SPEED * progress));
                    npc.teleport(new Location(currentLocation.getWorld(),
                                    next.getX(), next.getY(), next.getZ(),
                                    targetLocation.getYaw(), targetLocation.getPitch()),
                            org.bukkit.event.player.PlayerTeleportEvent.TeleportCause.PLUGIN);
                }
            };
            task.runTaskTimer(JavaPlugin.getPlugin(CrossplayPackage.class), 0L, 1L);
            currentTasks.put(user, task);
        }
    }
}
