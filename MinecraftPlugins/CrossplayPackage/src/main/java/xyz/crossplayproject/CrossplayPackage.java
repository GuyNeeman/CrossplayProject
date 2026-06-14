package xyz.crossplayproject;

import org.bukkit.Material;
import org.bukkit.configuration.file.FileConfiguration;
import org.bukkit.plugin.java.JavaPlugin;
import spark.Service;

import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

public class CrossplayPackage extends JavaPlugin {

    private BlockHandler blockHandler;
    private EntityHandler entityHandler;
    private POSTHandler postHandler;
    private CrossChat crossChat;
    private CommandHandler commandHandler;
    private Service sparkService;

    @Override
    public void onEnable() {
        if (!getDataFolder().exists()) getDataFolder().mkdir();
        saveDefaultConfig();

        FileConfiguration config = getConfig();
        int sparkPort = config.getInt("webserver.port", 4567);

        Set<Material> biomeSensitiveBlocks = loadMaterials(config.getStringList("blocks.biomeSensitive"));
        Set<Material> nonObstructingBlocks  = loadMaterials(config.getStringList("blocks.nonObstructing"));
        boolean enableCulling = config.getBoolean("enableCulling", false);

        blockHandler    = new BlockHandler(biomeSensitiveBlocks, nonObstructingBlocks, enableCulling);
        entityHandler   = new EntityHandler();
        postHandler     = new POSTHandler();
        crossChat       = new CrossChat();
        commandHandler  = new CommandHandler();

        setupSpark(sparkPort);
        crossChat.startBroadcastTask();

        getServer().getPluginManager().registerEvents(crossChat, this);
        getServer().getPluginManager().registerEvents(entityHandler, this);

        // Keep /players, /mobs, /world, /spawn snapshots current on the main thread
        // so Spark handler threads never need to touch the Bukkit API.
        getServer().getScheduler().runTaskTimer(this, entityHandler::refreshSnapshots, 0L, 2L);

        getLogger().info("CrossplayPackage enabled — Geyser-style proxy mode active.");
    }

    private Set<Material> loadMaterials(List<String> names) {
        return names.stream()
                .map(name -> {
                    try { return Material.valueOf(name); }
                    catch (IllegalArgumentException e) {
                        getLogger().warning("Invalid material in config: " + name);
                        return null;
                    }
                })
                .filter(Objects::nonNull)
                .collect(Collectors.toSet());
    }

    private void setupSpark(int port) {
        sparkService = Service.ignite();
        sparkService.port(port);

        blockHandler.setupRoutes(sparkService);
        entityHandler.setupRoutes(sparkService);
        postHandler.setupRoutes(sparkService);
        crossChat.setupRoutes(sparkService);
        commandHandler.setupRoutes(sparkService);

        // /npc route: Roblox player position updates → bot session movement
        sparkService.post("/npc", (req, res) -> {
            try {
                NpcUpdate update = new com.google.gson.Gson().fromJson(req.body(), NpcUpdate.class);
                if (update == null || update.user == null) { res.status(400); return "Bad request"; }

                if (update.disconnect) {
                    RobloxSessionManager.disconnect(update.user);
                } else {
                    RobloxBotSession session = RobloxSessionManager.get(update.user);
                    if (session == null || !session.isConnected()) {
                        RobloxSessionManager.connect(update.user);
                        // Session connecting — movement will start flowing on next poll
                    } else if (session.isActive()) {
                        // Coordinate mapping: Roblox 3-stud grid → 1 MC block
                        // +0.5 centres the player inside the block, matching Citizens NPC placement
                        session.sendMovement(
                                update.x + 0.5, update.y, update.z + 0.5,
                                update.yaw, update.pitch, true
                        );
                    }
                }
                return "OK";
            } catch (Exception e) {
                getLogger().warning("[Crossplay] /npc error: " + e.getMessage());
                res.status(500);
                return "Internal Server Error";
            }
        });
    }

    /** POJO for the /npc POST body sent by NPCHandler.Script.lua */
    private static class NpcUpdate {
        String user;
        double x, y, z;
        float yaw, pitch;
        boolean disconnect;
    }

    @Override
    public void onDisable() {
        RobloxSessionManager.disconnectAll();
        if (sparkService != null) {
            sparkService.stop();
            sparkService.awaitStop();
        }
        getLogger().info("CrossplayPackage disabled.");
    }
}
