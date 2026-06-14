package xyz.crossplayproject;

import com.google.gson.Gson;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import org.bukkit.*;
import org.bukkit.block.Block;
import org.bukkit.entity.Entity;
import org.bukkit.block.BlockFace;
import org.bukkit.block.Sign;
import org.bukkit.block.data.BlockData;
import org.bukkit.block.data.Openable;
import org.bukkit.block.data.Powerable;
import org.bukkit.entity.Player;
import org.bukkit.inventory.ItemStack;
import org.bukkit.plugin.java.JavaPlugin;
import org.bukkit.scheduler.BukkitRunnable;
import spark.Service;

import java.util.UUID;
import java.util.concurrent.TimeUnit;
import java.util.logging.Level;
import java.util.logging.Logger;

import static org.bukkit.Bukkit.getLogger;

public class POSTHandler {

    private static final Logger LOG = Logger.getLogger("Crossplay");
    private final Gson gson = new Gson();

    public void setupRoutes(Service spark) {

        /**
         * Attack endpoint: Roblox player punches a Minecraft player.
         *
         * With the proxy approach the attack goes through the bot's real ServerPlayer,
         * so EntityDamageByEntityEvent fires with the correct damager — plugins see it
         * as a legitimate hit, kill credits and achievements work properly.
         *
         * Request body: { "attacker": "<robloxName>", "target": "<mcName>", "damage": 1.0 }
         */
        spark.post("/attack", (req, res) -> {
            JsonObject json = gson.fromJson(req.body(), JsonObject.class);
            String targetName   = json.get("target").getAsString();
            String attackerName = json.has("attacker") ? json.get("attacker").getAsString() : null;
            double damage       = json.has("damage") ? json.get("damage").getAsDouble() : 1.0;

            RobloxBotSession botSession = attackerName != null
                    ? RobloxSessionManager.get(attackerName) : null;

            if (botSession != null && botSession.isActive()) {
                // Look up entity ID on the main thread, then send a proper Interact/Attack packet.
                // targetName is either a player name or a mob UUID (contains dashes).
                boolean isMobUUID = targetName.contains("-");
                try {
                    Integer entityId = Bukkit.getScheduler()
                            .callSyncMethod(JavaPlugin.getPlugin(CrossplayPackage.class), () -> {
                                if (isMobUUID) {
                                    try {
                                        Entity mob = Bukkit.getEntity(UUID.fromString(targetName));
                                        return mob != null ? mob.getEntityId() : -1;
                                    } catch (IllegalArgumentException e) { return -1; }
                                } else {
                                    Player target = Bukkit.getPlayer(targetName);
                                    return target != null ? target.getEntityId() : -1;
                                }
                            }).get(2, TimeUnit.SECONDS);
                    if (entityId != -1) botSession.sendAttack(entityId);
                } catch (Exception e) {
                    LOG.log(Level.WARNING, "[Crossplay] Attack lookup failed: " + e.getMessage());
                }
            } else {
                // Fallback: direct Bukkit damage
                final double dmg = damage;
                new BukkitRunnable() {
                    @Override public void run() {
                        Player target = Bukkit.getPlayer(targetName);
                        if (target != null) target.damage(dmg);
                    }
                }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));
            }

            res.status(200);
            return "OK";
        });

        spark.post("/post", (request, response) -> {
            JsonObject json = gson.fromJson(request.body(), JsonObject.class);
            int x = json.get("x").getAsInt();
            int y = json.get("y").getAsInt();
            int z = json.get("z").getAsInt();
            String action = json.get("action").getAsString();
            String playerName = json.has("player") ? json.get("player").getAsString() : null;

            World world = Bukkit.getWorlds().getFirst();

            switch (action.toUpperCase()) {
                case "BUILD"  -> buildBlock(world, x, y, z, json);
                case "BREAK"  -> breakBlock(world, x, y, z, playerName);
                case "TOGGLE" -> toggleBlock(world, x, y, z);
                case "EDIT"   -> editSign(world, x, y, z, json);
            }

            response.status(200);
            return "Success";
        });
    }

    private void buildBlock(World world, int x, int y, int z, JsonObject json) {
        new BukkitRunnable() {
            @Override
            public void run() {
                Material material = Material.valueOf(json.get("material").getAsString());
                JsonElement directionElement = json.get("direction");
                if (directionElement == null || directionElement.isJsonNull()) {
                    getLogger().warning("[POST] Direction not set in BUILD payload.");
                    return;
                }
                BlockFace direction = BlockFace.valueOf(directionElement.getAsString());
                Block block = world.getBlockAt(x, y, z);
                if (block.getType() == Material.AIR) {
                    block.setType(material);
                    if (block.getBlockData() instanceof org.bukkit.block.data.Directional directional) {
                        directional.setFacing(direction);
                        block.setBlockData(directional);
                    }
                    world.playSound(block.getLocation(),
                            block.getType().createBlockData().getSoundGroup().getPlaceSound(), 1.0f, 1.0f);
                }
            }
        }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));
    }

    private void breakBlock(World world, int x, int y, int z, String playerName) {
        new BukkitRunnable() {
            @Override
            public void run() {
                Block block = world.getBlockAt(x, y, z);
                if (block.getType() == Material.AIR) return;

                world.playEffect(block.getLocation(), Effect.STEP_SOUND, block.getType());

                // Roblox player is now a real Bukkit player. Use breakNaturally with their
                // held tool so Fortune / Silk Touch enchantments apply correctly, and drops
                // are spawned as item entities near the bot — the bot picks them up naturally.
                Player robloxPlayer = playerName != null ? Bukkit.getPlayer(playerName) : null;
                if (robloxPlayer != null) {
                    ItemStack tool = robloxPlayer.getInventory().getItemInMainHand();
                    block.breakNaturally(tool);
                } else {
                    block.breakNaturally();
                }
            }
        }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));
    }

    private void toggleBlock(World world, int x, int y, int z) {
        new BukkitRunnable() {
            @Override
            public void run() {
                Block block = world.getBlockAt(x, y, z);
                String name = block.getType().name();
                if (name.endsWith("_BUTTON"))      toggleButton(block);
                else if (name.endsWith("_DOOR"))   toggleDoor(block);
                else if (name.endsWith("_FENCE_GATE")) toggleFenceGate(block);
                else if (name.endsWith("_TRAPDOOR")) toggleTrapdoor(block);
                else if (block.getType() == Material.LEVER) toggleLever(block);
                else getLogger().warning("POST toggle: unsupported material at "
                        + block.getX() + "," + block.getY() + "," + block.getZ());
            }
        }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));
    }

    private void toggleLever(Block block) {
        if (block.getBlockData() instanceof Powerable p) {
            p.setPowered(!p.isPowered());
            block.setBlockData(p);
            Sound sound = p.isPowered()
                    ? Sound.BLOCK_STONE_BUTTON_CLICK_OFF : Sound.BLOCK_STONE_BUTTON_CLICK_ON;
            block.getWorld().playSound(block.getLocation(), sound, 1.0f, 1.0f);
        }
    }

    private void toggleButton(Block block) {
        if (block.getBlockData() instanceof Powerable p) {
            p.setPowered(!p.isPowered());
            block.setBlockData(p);
            block.getWorld().playSound(block.getLocation(), Sound.BLOCK_STONE_BUTTON_CLICK_ON, 1.0f, 1.0f);
            Bukkit.getScheduler().runTaskLater(JavaPlugin.getPlugin(CrossplayPackage.class), () -> {
                p.setPowered(!p.isPowered());
                block.setBlockData(p);
                block.getWorld().playSound(block.getLocation(), Sound.BLOCK_STONE_BUTTON_CLICK_OFF, 1.0f, 1.0f);
            }, 20L);
        }
    }

    private void toggleDoor(Block block) {
        if (block.getBlockData() instanceof Openable o) {
            o.setOpen(!o.isOpen());
            block.setBlockData(o);
            block.getWorld().playSound(block.getLocation(), Sound.BLOCK_WOODEN_DOOR_OPEN, 1.0f, 1.0f);
        }
    }

    private void toggleFenceGate(Block block) {
        if (block.getBlockData() instanceof Openable o) {
            boolean nowOpen = !o.isOpen();
            o.setOpen(nowOpen);
            block.setBlockData(o);
            Sound sound = nowOpen ? Sound.BLOCK_FENCE_GATE_OPEN : Sound.BLOCK_FENCE_GATE_CLOSE;
            block.getWorld().playSound(block.getLocation(), sound, 1.0f, 1.0f);
        }
    }

    private void toggleTrapdoor(Block block) {
        if (block.getBlockData() instanceof Openable o) {
            o.setOpen(!o.isOpen());
            block.setBlockData(o);
            block.getWorld().playSound(block.getLocation(), Sound.BLOCK_WOODEN_TRAPDOOR_OPEN, 1.0f, 1.0f);
        }
    }

    private void editSign(World world, int x, int y, int z, JsonObject json) {
        new BukkitRunnable() {
            @Override
            public void run() {
                Block block = world.getBlockAt(x, y, z);
                if (block.getState() instanceof Sign sign) {
                    int line = json.get("line").getAsInt();
                    String text = json.get("text").getAsString();
                    sign.setLine(line, text);
                    sign.update();
                }
            }
        }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));
    }
}
