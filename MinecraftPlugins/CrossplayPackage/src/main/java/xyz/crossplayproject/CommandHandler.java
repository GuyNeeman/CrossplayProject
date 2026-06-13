package xyz.crossplayproject;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import org.bukkit.Bukkit;
import org.bukkit.plugin.java.JavaPlugin;
import org.bukkit.scheduler.BukkitRunnable;
import spark.Service;

import java.util.logging.Level;

public class CommandHandler {

    private final Gson gson = new Gson();

    public void setupRoutes(Service spark) {
        spark.post("/command", (req, res) -> {
            try {
                JsonObject json = gson.fromJson(req.body(), JsonObject.class);
                String raw = json.get("command").getAsString().trim();
                String command = raw.startsWith("/") ? raw.substring(1) : raw;

                new BukkitRunnable() {
                    @Override
                    public void run() {
                        Bukkit.dispatchCommand(Bukkit.getConsoleSender(), command);
                    }
                }.runTask(JavaPlugin.getPlugin(CrossplayPackage.class));

                return "OK";
            } catch (Exception e) {
                JavaPlugin.getPlugin(CrossplayPackage.class).getLogger()
                        .log(Level.WARNING, "Error executing Roblox command", e);
                res.status(400);
                return "Bad request";
            }
        });
    }
}
