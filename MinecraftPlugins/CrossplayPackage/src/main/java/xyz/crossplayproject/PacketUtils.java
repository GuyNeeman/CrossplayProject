package xyz.crossplayproject;

import org.bukkit.entity.Player;

import java.lang.reflect.*;
import java.util.*;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Injects Minecraft tab-list packets without a compile-time NMS dependency.
 * Uses reflection to build and send ClientboundPlayerInfoUpdatePacket /
 * ClientboundPlayerInfoRemovePacket so Roblox NPCs appear in the player list
 * just like real players (the same way Floodgate/Geyser does it).
 */
public class PacketUtils {

    private static final Logger LOG = Logger.getLogger("Crossplay");

    // --- Public API ---

    /** Add the NPC Bukkit Player to every viewer's in-game tab list. */
    @SuppressWarnings({"unchecked", "rawtypes"})
    public static void addToTabList(Player npcPlayer, Collection<? extends Player> viewers) {
        try {
            Object nmsPlayer = getHandle(npcPlayer);

            // Build EnumSet<Action> { ADD_PLAYER, UPDATE_LISTED }
            Class<?> actionClass = Class.forName(
                    "net.minecraft.network.protocol.game.ClientboundPlayerInfoUpdatePacket$Action");
            EnumSet actions = EnumSet.noneOf((Class) actionClass);
            for (Object constant : actionClass.getEnumConstants()) {
                String n = ((Enum<?>) constant).name();
                if (n.equals("ADD_PLAYER") || n.equals("UPDATE_LISTED")) {
                    actions.add((Enum) constant);
                }
            }

            // new ClientboundPlayerInfoUpdatePacket(EnumSet<Action>, Collection<ServerPlayer>)
            Class<?> packetClass = Class.forName(
                    "net.minecraft.network.protocol.game.ClientboundPlayerInfoUpdatePacket");
            Constructor<?> ctor = packetClass.getDeclaredConstructor(EnumSet.class, Collection.class);
            Object packet = ctor.newInstance(actions, List.of(nmsPlayer));

            broadcast(packet, viewers);
        } catch (Exception e) {
            LOG.log(Level.WARNING, "[Crossplay] Tab-list add failed: " + e.getMessage());
        }
    }

    /** Remove the fake entry by UUID from every viewer's in-game tab list. */
    public static void removeFromTabList(UUID uuid, Collection<? extends Player> viewers) {
        try {
            Class<?> cls = Class.forName(
                    "net.minecraft.network.protocol.game.ClientboundPlayerInfoRemovePacket");
            Object packet = cls.getDeclaredConstructor(List.class).newInstance(List.of(uuid));
            broadcast(packet, viewers);
        } catch (Exception e) {
            LOG.log(Level.WARNING, "[Crossplay] Tab-list remove failed: " + e.getMessage());
        }
    }

    // --- Helpers ---

    private static void broadcast(Object packet, Collection<? extends Player> viewers) {
        for (Player viewer : viewers) {
            try {
                sendPacket(viewer, packet);
            } catch (Exception e) {
                LOG.log(Level.FINE, "[Crossplay] sendPacket to " + viewer.getName() + " failed: " + e.getMessage());
            }
        }
    }

    private static void sendPacket(Player player, Object packet) throws Exception {
        Object nmsPlayer = getHandle(player);
        Field connField = findField(nmsPlayer.getClass(), "connection");
        Object connection = connField.get(nmsPlayer);
        if (connection == null) return;

        // Find send(Packet<?>) — at bytecode level the erasure is send(Packet)
        for (Method m : connection.getClass().getMethods()) {
            if (m.getName().equals("send") && m.getParameterCount() == 1
                    && m.getParameterTypes()[0].isInstance(packet)) {
                m.invoke(connection, packet);
                return;
            }
        }
    }

    private static Object getHandle(Player player) throws Exception {
        return player.getClass().getMethod("getHandle").invoke(player);
    }

    /** Walks the class hierarchy so we find the field even if it's declared in a superclass. */
    private static Field findField(Class<?> cls, String name) throws NoSuchFieldException {
        while (cls != null) {
            try {
                Field f = cls.getDeclaredField(name);
                f.setAccessible(true);
                return f;
            } catch (NoSuchFieldException ignored) {
                cls = cls.getSuperclass();
            }
        }
        throw new NoSuchFieldException(name);
    }
}
