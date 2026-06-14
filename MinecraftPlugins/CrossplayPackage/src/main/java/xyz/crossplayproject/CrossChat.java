package xyz.crossplayproject;

import org.bukkit.Bukkit;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.AsyncPlayerChatEvent;
import org.bukkit.event.player.PlayerCommandPreprocessEvent;
import org.bukkit.event.server.ServerCommandEvent;
import org.bukkit.plugin.java.JavaPlugin;
import org.json.JSONArray;
import org.json.JSONObject;
import spark.Service;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class CrossChat implements Listener {

    private final List<JSONObject> minecraftMessages = Collections.synchronizedList(new ArrayList<>());
    private final List<JSONObject> robloxMessages = Collections.synchronizedList(new ArrayList<>());

    public void setupRoutes(Service spark) {
        spark.get("/favicon.ico", (req, res) -> "");

        spark.post("/chat", (req, res) -> {
            JSONObject requestBody = new JSONObject(req.body());
            String player = requestBody.getString("player");
            String color = requestBody.getString("color");
            String message = requestBody.getString("message");

            JSONObject messageObject = new JSONObject();
            messageObject.put("sender", player);
            messageObject.put("color", color);
            messageObject.put("message", message);

            robloxMessages.add(messageObject);

            res.status(200);
            return "Message received";
        });

        spark.get("/chat", (req, res) -> {
            res.type("application/json");
            synchronized (minecraftMessages) {
                JSONArray messagesArray = new JSONArray(minecraftMessages);
                minecraftMessages.clear();
                return messagesArray.toString();
            }
        });
    }

    @SuppressWarnings("deprecation")
    @EventHandler
    public void onPlayerChat(AsyncPlayerChatEvent event) {
        event.setFormat("%s: %s");
        String playerName = event.getPlayer().getName();
        String message = event.getMessage();
        sendToRoblox(playerName, message);
    }

    @EventHandler
    public void onServerCommand(ServerCommandEvent event) {
        if (event.getCommand().startsWith("say ")) {
            String playerName = "[SERVER]";
            String message = event.getCommand().substring(4);
            sendToRoblox(playerName, message);
        }
    }

    private void sendToRoblox(String playerName, String message) {
        JSONObject jsonMessage = new JSONObject();
        jsonMessage.put("sender", playerName);
        jsonMessage.put("message", message);
        minecraftMessages.add(jsonMessage);
    }

    @EventHandler
    public void onPlayerCommand(PlayerCommandPreprocessEvent event) {
        String cmd = event.getMessage().toLowerCase().trim();
        if (cmd.equals("/list") || cmd.startsWith("/list ")) {
            java.util.Set<String> robloxPlayers = RobloxSessionManager.connectedNames();
            if (!robloxPlayers.isEmpty()) {
                event.getPlayer().sendMessage(
                    "§b[Roblox] §fConnected (" + robloxPlayers.size() + "): §e" + String.join("§f, §e", robloxPlayers)
                );
            }
        }
    }

    public void startBroadcastTask() {
        Bukkit.getScheduler().runTaskTimer(JavaPlugin.getPlugin(CrossplayPackage.class), this::broadcastMessagesToMinecraft, 20L, 20L);
    }

    private void broadcastMessagesToMinecraft() {
        List<JSONObject> snapshot;
        synchronized (robloxMessages) {
            snapshot = new ArrayList<>(robloxMessages);
            robloxMessages.clear();
        }
        for (JSONObject messageObject : snapshot) {
            String sender = messageObject.getString("sender");
            String message = messageObject.getString("message");
            String colorHex = messageObject.optString("color", "FFFFFF");
            String formattedMessage = net.md_5.bungee.api.ChatColor.of(colorHex) + sender + net.md_5.bungee.api.ChatColor.RESET + ": " + message;
            Bukkit.getServer().broadcastMessage("§f§7[RB]§f " + formattedMessage);
        }
    }
}
