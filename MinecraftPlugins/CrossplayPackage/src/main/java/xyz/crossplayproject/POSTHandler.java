package xyz.crossplayproject;

import com.google.gson.Gson;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import net.citizensnpcs.api.npc.NPC;
import org.bukkit.*;
import org.bukkit.block.Block;
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

import static org.bukkit.Bukkit.getLogger;

public class POSTHandler {

    private final Gson gson = new Gson();

    public void setupRoutes(Service spark) {
        spark.get("/favicon.ico", (req, res) -> "");

        // Direct player attack — called by the Roblox client when a Roblox player
        // punches a Minecraft player model. Damages the target by the given amount.
        spark.post("/attack", (req, res) -> {
            JsonObject json = gson.fromJson(req.body(), JsonObject.class);
            String targetName = json.get("target").getAsString();
            double damage = json.has("damage") ? json.get("damage").getAsDouble() : 1.0;

            new BukkitRunnable() {
                @Override
                public void run() {
                    Player target = Bukkit.getPlayer(targetName);
                    if (target != null) {
                        target.damage(damage);
                    } else {
                        getLogger().warning("[Attack] Target player not found: " + targetName);
                    }
                }
            }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));

            res.status(200);
            return "OK";
        });

        spark.post("/post", (request, response) -> {
            JsonObject json = gson.fromJson(request.body(), JsonObject.class);
            int x = json.get("x").getAsInt();
            int y = json.get("y").getAsInt();
            int z = json.get("z").getAsInt();
            String action = json.get("action").getAsString();

            World world = Bukkit.getWorlds().getFirst();

            switch (action.toUpperCase()) {
                case "BUILD":
                    buildBlock(world, x, y, z, json);
                    break;
                case "BREAK":
                    breakBlock(world, x, y, z);
                    break;
                case "TOGGLE":
                    toggleBlock(world, x, y, z);
                    break;
                case "EDIT":
                    editSign(world, x, y, z, json);
                    break;
                default:
                    break;
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
                    getLogger().warning("[POST] Direction has not been set in the POST payload.");
                    return;
                }
                String directionString = directionElement.getAsString();
                BlockFace direction = BlockFace.valueOf(directionString);
                Block block = world.getBlockAt(x, y, z);
                if (block.getType() == Material.AIR) {
                    block.setType(material);
                    if (block.getBlockData() instanceof org.bukkit.block.data.Directional directional) {
                        directional.setFacing(direction);
                        block.setBlockData(directional);
                    }
                    world.playSound(block.getLocation(), block.getType().createBlockData().getSoundGroup().getPlaceSound(), 1.0f, 1.0f);
                }
            }
        }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));
    }

    private void breakBlock(World world, int x, int y, int z) {
        new BukkitRunnable() {
            @Override
            public void run() {
                Block block = world.getBlockAt(x, y, z);
                if (block.getType() == Material.AIR) return;

                world.playEffect(block.getLocation(), Effect.STEP_SOUND, block.getType());

                // Calculate natural drops and route them to the Roblox player's NPC inventory.
                // The POST body carries the "player" field set by NPCHandler.Script.lua.
                // We look up the NPC by name; if found we add drops directly to its inventory.
                java.util.Collection<ItemStack> drops = block.getDrops();
                for (NPC npc : getNPCsNearBlock(world, x, y, z, 32)) {
                    if (npc.isSpawned() && npc.getEntity() instanceof Player npcPlayer) {
                        for (ItemStack drop : drops) {
                            npcPlayer.getInventory().addItem(drop.clone());
                        }
                        break; // give drops to the closest Roblox player only
                    }
                }

                block.setType(Material.AIR);
            }
        }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));
    }

    private java.util.List<NPC> getNPCsNearBlock(World world, int bx, int by, int bz, double maxDist) {
        java.util.List<NPC> nearby = new java.util.ArrayList<>();
        for (String name : NPCHandler.getConnectedPlayerNames()) {
            NPC npc = NPCHandler.getNPC(name);
            if (npc == null || !npc.isSpawned()) continue;
            Location npcLoc = npc.getEntity().getLocation();
            if (!npcLoc.getWorld().equals(world)) continue;
            double dx = npcLoc.getX() - bx, dz = npcLoc.getZ() - bz;
            if (Math.sqrt(dx * dx + dz * dz) <= maxDist) nearby.add(npc);
        }
        return nearby;
    }

    private void toggleBlock(World world, int x, int y, int z) {
        new BukkitRunnable() {
            @Override
            public void run() {
                Block block = world.getBlockAt(x, y, z);
                Material material = block.getType();
                String materialName = material.name();

                if (materialName.endsWith("_BUTTON")) {
                    toggleButton(block);
                } else if (materialName.endsWith("_DOOR")) {
                    toggleDoor(block);
                } else if (materialName.endsWith("_FENCE_GATE")) {
                    toggleFenceGate(block);
                } else if (materialName.endsWith("_TRAPDOOR")) {
                    toggleTrapdoor(block);
                } else if (material == Material.LEVER) {
                    toggleLever(block);
                } else {
                    getLogger().warning("Material at " + block.getX() + ", " + block.getY() + ", " + block.getZ() + " is not supported by POST toggle.");
                }
            }
        }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));
    }

    private void toggleLever(Block block) {
        BlockData blockData = block.getBlockData();
        if (blockData instanceof Powerable powerable) {
            powerable.setPowered(!powerable.isPowered());
            block.setBlockData(powerable);
            if(powerable.isPowered()) {
                block.getWorld().playSound(block.getLocation(), Sound.BLOCK_STONE_BUTTON_CLICK_OFF, 1.0f, 1.0f);
            } else {
                block.getWorld().playSound(block.getLocation(), Sound.BLOCK_STONE_BUTTON_CLICK_ON, 1.0f, 1.0f);
            }
        }
    }

    private void toggleButton(Block block) {
        BlockData blockData = block.getBlockData();
        if (blockData instanceof Powerable powerable) {
            powerable.setPowered(!powerable.isPowered());
            block.setBlockData(powerable);
            block.getWorld().playSound(block.getLocation(), Sound.BLOCK_STONE_BUTTON_CLICK_ON, 1.0f, 1.0f);

            Bukkit.getScheduler().runTaskLater(JavaPlugin.getPlugin(CrossplayPackage.class), () -> {
                powerable.setPowered(!powerable.isPowered());
                block.setBlockData(powerable);
                block.getWorld().playSound(block.getLocation(), Sound.BLOCK_STONE_BUTTON_CLICK_OFF, 1.0f, 1.0f);
            }, 20L);
        }
    }

    private void toggleDoor(Block block) {
        BlockData blockData = block.getBlockData();
        if (blockData instanceof Openable openable) {
            openable.setOpen(!openable.isOpen());
            block.setBlockData(openable);
            block.getWorld().playSound(block.getLocation(), Sound.BLOCK_WOODEN_DOOR_OPEN, 1.0f, 1.0f);
        }
    }

    private void toggleFenceGate(Block block) {
        BlockData blockData = block.getBlockData();
        if (blockData instanceof Openable openable) {
            boolean nowOpen = !openable.isOpen();
            openable.setOpen(nowOpen);
            block.setBlockData(openable);
            Sound sound = nowOpen ? Sound.BLOCK_FENCE_GATE_OPEN : Sound.BLOCK_FENCE_GATE_CLOSE;
            block.getWorld().playSound(block.getLocation(), sound, 1.0f, 1.0f);
        }
    }

    private void toggleTrapdoor(Block block) {
        BlockData blockData = block.getBlockData();
        if (blockData instanceof Openable openable) {
            openable.setOpen(!openable.isOpen());
            block.setBlockData(openable);
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
