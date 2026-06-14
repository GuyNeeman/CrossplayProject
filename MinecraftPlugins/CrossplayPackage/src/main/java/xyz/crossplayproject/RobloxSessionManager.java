package xyz.crossplayproject;

import org.bukkit.Bukkit;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.logging.Logger;

/**
 * Manages the lifecycle of all active Roblox↔Minecraft bot sessions.
 * Each Roblox player has one RobloxBotSession that holds a real MCProtocolLib
 * TCP connection to localhost:25565, giving them a genuine ServerPlayer on
 * the Minecraft server — visible to all plugins, commands, and events natively.
 */
public class RobloxSessionManager {

    private static final Logger LOG = Logger.getLogger("Crossplay");
    private static final ConcurrentHashMap<String, RobloxBotSession> sessions = new ConcurrentHashMap<>();

    /** Connect a new Roblox player. No-op if already connected. */
    public static void connect(String username) {
        if (sessions.containsKey(username)) return;
        LOG.info("[Crossplay] Connecting Roblox player: " + username);
        RobloxBotSession s = new RobloxBotSession(username);
        sessions.put(username, s);
        s.connect();
    }

    /** Disconnect and remove a Roblox player's session. */
    public static void disconnect(String username) {
        RobloxBotSession s = sessions.remove(username);
        if (s != null) {
            LOG.info("[Crossplay] Disconnecting Roblox player: " + username);
            s.disconnect();
        }
    }

    /** Called by RobloxBotSession when the MCProtocolLib session drops unexpectedly. */
    public static void handleDisconnect(String username) {
        sessions.remove(username);
        // Broadcast to MC players so they know the Roblox player left
        Bukkit.broadcastMessage("§7[RB]§e " + username + " left the game");
    }

    /** Return the active session for a username, or null if not connected. */
    public static RobloxBotSession get(String username) {
        return sessions.get(username);
    }

    /** Returns true if the player name belongs to one of our bot sessions.
     *  Used to exclude bots from the Roblox-facing /players list. */
    public static boolean isBot(String playerName) {
        return sessions.containsKey(playerName);
    }

    /** All currently connected Roblox player names. */
    public static Set<String> connectedNames() {
        return sessions.keySet();
    }

    /** Disconnect every active session — called on plugin disable. */
    public static void disconnectAll() {
        for (RobloxBotSession s : sessions.values()) {
            s.disconnect();
        }
        sessions.clear();
    }
}
