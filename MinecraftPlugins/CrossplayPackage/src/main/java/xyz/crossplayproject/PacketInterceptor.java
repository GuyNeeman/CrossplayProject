package xyz.crossplayproject;

import io.netty.channel.*;
import org.bukkit.entity.Player;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedDeque;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Injects a Netty ChannelOutboundHandlerAdapter into the Citizens NPC's underlying
 * connection channel — the same technique Geyser uses to intercept packets the MC
 * server sends to a proxy player.  We capture title, actionbar, sound, and health
 * packets and queue them so the Roblox client can poll /events/:username and display
 * them natively.
 */
public class PacketInterceptor extends ChannelOutboundHandlerAdapter {

    private static final String HANDLER = "roblox_event_interceptor";
    private static final Logger LOG = Logger.getLogger("Crossplay");

    private final String username;

    // Per-Roblox-player event queue; drained by the /events/:username endpoint
    private static final Map<String, ConcurrentLinkedDeque<RobloxEvent>> queues =
            new ConcurrentHashMap<>();

    public PacketInterceptor(String username) {
        this.username = username;
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /** Call from the main thread after the NPC spawns (2-tick delay). */
    public static void inject(String username, Player npcPlayer) {
        queues.put(username, new ConcurrentLinkedDeque<>());
        try {
            Channel ch = channel(npcPlayer);
            if (ch == null) return;
            // Pipeline mutations must run on the channel's event loop
            ch.eventLoop().submit(() -> {
                if (ch.pipeline().get(HANDLER) == null) {
                    ch.pipeline().addFirst(HANDLER, new PacketInterceptor(username));
                }
            });
        } catch (Exception e) {
            LOG.log(Level.FINE, "[Crossplay] PacketInterceptor inject failed for " + username + ": " + e.getMessage());
        }
    }

    /** Call when the NPC despawns. */
    public static void remove(String username, Player npcPlayer) {
        queues.remove(username);
        try {
            Channel ch = channel(npcPlayer);
            if (ch == null) return;
            ch.eventLoop().submit(() -> {
                if (ch.pipeline().get(HANDLER) != null) ch.pipeline().remove(HANDLER);
            });
        } catch (Exception ignored) {}
    }

    /** Drain all pending events for a Roblox player (called by the /events endpoint). */
    public static List<RobloxEvent> drain(String username) {
        ConcurrentLinkedDeque<RobloxEvent> q = queues.get(username);
        if (q == null || q.isEmpty()) return List.of();
        List<RobloxEvent> out = new ArrayList<>();
        RobloxEvent e;
        while ((e = q.poll()) != null) out.add(e);
        return out;
    }

    // ── Netty handler ─────────────────────────────────────────────────────────

    @Override
    public void write(ChannelHandlerContext ctx, Object msg, ChannelPromise promise) throws Exception {
        try {
            capture(msg);
        } catch (Exception ignored) {
            // Reflection failure is non-fatal; just don't queue this packet
        }
        ctx.write(msg, promise); // always pass through — don't interfere with Citizens
    }

    private void capture(Object msg) throws Exception {
        ConcurrentLinkedDeque<RobloxEvent> q = queues.get(username);
        if (q == null) return;

        String cls = msg.getClass().getSimpleName();
        switch (cls) {
            case "ClientboundSetTitleTextPacket"    -> q.offer(new RobloxEvent("title",     componentPlainText(msg, "title")));
            case "ClientboundSetSubtitleTextPacket" -> q.offer(new RobloxEvent("subtitle",  componentPlainText(msg, "title")));
            case "ClientboundSetActionBarTextPacket"-> q.offer(new RobloxEvent("actionbar", componentPlainText(msg, "text")));
            case "ClientboundSetHealthPacket" -> {
                // health field is a float record component
                Object val = invokeOrField(msg, "health");
                if (val != null) q.offer(new RobloxEvent("health", String.valueOf(val)));
            }
            case "ClientboundSoundPacket" -> {
                // sound|name|x|y|z|volume|pitch
                try {
                    Object soundHolder = invokeOrField(msg, "sound");
                    Object soundEvent  = soundHolder.getClass().getMethod("value").invoke(soundHolder);
                    Object location    = soundEvent.getClass().getMethod("location").invoke(soundEvent);
                    String name = location.toString();

                    double x = toDouble(invokeOrField(msg, "x"));
                    double y = toDouble(invokeOrField(msg, "y"));
                    double z = toDouble(invokeOrField(msg, "z"));
                    float  volume = (float) invokeOrField(msg, "volume");
                    float  pitch  = (float) invokeOrField(msg, "pitch");

                    q.offer(new RobloxEvent("sound",
                            name + "|" + x + "|" + y + "|" + z + "|" + volume + "|" + pitch));
                } catch (Exception ignored) {}
            }
        }
    }

    // ── Reflection helpers ────────────────────────────────────────────────────

    /**
     * Tries the accessor method first (works for Java records like MC packets),
     * then falls back to direct field access.
     */
    private static Object invokeOrField(Object obj, String name) throws Exception {
        try {
            Method m = obj.getClass().getMethod(name);
            return m.invoke(obj);
        } catch (NoSuchMethodException e) {
            Field f = PacketUtils.findField(obj.getClass(), name);
            return f.get(obj);
        }
    }

    /** Extract plain text from an NMS Component (net.minecraft.network.chat.Component). */
    private static String componentPlainText(Object packet, String fieldName) {
        try {
            Object component = invokeOrField(packet, fieldName);
            if (component == null) return "";
            // Component.getString() returns the raw literal string without formatting
            return (String) component.getClass().getMethod("getString").invoke(component);
        } catch (Exception e) {
            try { return invokeOrField(packet, fieldName).toString(); } catch (Exception ignored) {}
            return "";
        }
    }

    private static double toDouble(Object val) {
        if (val instanceof Double d) return d;
        if (val instanceof Float  f) return f;
        if (val instanceof Integer i) return i / 8.0; // older fixed-point encoding
        if (val instanceof Number n) return n.doubleValue();
        return 0;
    }

    /** Walk reflection chain: CraftPlayer → ServerPlayer → connection → Connection → channel */
    private static Channel channel(Player player) throws Exception {
        Object nmsPlayer      = PacketUtils.getHandle(player);
        Field  listenerField  = PacketUtils.findField(nmsPlayer.getClass(), "connection");
        Object listener       = listenerField.get(nmsPlayer);
        if (listener == null) return null;
        Field  networkField   = PacketUtils.findField(listener.getClass(), "connection");
        Object networkManager = networkField.get(listener);
        if (networkManager == null) return null;
        Field  channelField   = PacketUtils.findField(networkManager.getClass(), "channel");
        return (Channel) channelField.get(networkManager);
    }

    // ── Event DTO ─────────────────────────────────────────────────────────────

    public record RobloxEvent(String type, String data) {}
}
