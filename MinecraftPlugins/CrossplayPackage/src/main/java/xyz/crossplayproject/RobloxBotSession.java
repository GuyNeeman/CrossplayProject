package xyz.crossplayproject;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.serializer.plain.PlainTextComponentSerializer;
import org.geysermc.mcprotocollib.auth.SessionService;
import org.geysermc.mcprotocollib.network.Session;
import org.geysermc.mcprotocollib.network.event.session.DisconnectedEvent;
import org.geysermc.mcprotocollib.network.event.session.SessionAdapter;
import org.geysermc.mcprotocollib.network.packet.Packet;
import org.geysermc.mcprotocollib.network.tcp.TcpClientSession;
import org.geysermc.mcprotocollib.protocol.MinecraftConstants;
import org.geysermc.mcprotocollib.protocol.MinecraftProtocol;
import org.geysermc.mcprotocollib.protocol.data.game.entity.player.HandPreference;
import org.geysermc.mcprotocollib.protocol.data.game.entity.player.InteractAction;
import org.geysermc.mcprotocollib.protocol.data.game.setting.ChatVisibility;
import org.geysermc.mcprotocollib.protocol.data.game.setting.SkinPart;
import org.geysermc.mcprotocollib.protocol.packet.common.serverbound.ServerboundClientInformationPacket;
import org.geysermc.mcprotocollib.protocol.packet.common.serverbound.ServerboundCustomPayloadPacket;
import org.geysermc.mcprotocollib.protocol.data.game.ClientCommand;
import org.geysermc.mcprotocollib.protocol.packet.ingame.clientbound.ClientboundLoginPacket;
import org.geysermc.mcprotocollib.protocol.packet.ingame.clientbound.ClientboundRespawnPacket;
import org.geysermc.mcprotocollib.protocol.packet.ingame.clientbound.entity.player.ClientboundPlayerCombatKillPacket;
import org.geysermc.mcprotocollib.protocol.packet.ingame.clientbound.entity.player.ClientboundPlayerPositionPacket;
import org.geysermc.mcprotocollib.protocol.packet.ingame.clientbound.entity.player.ClientboundSetHealthPacket;
import org.geysermc.mcprotocollib.protocol.packet.ingame.serverbound.ServerboundClientCommandPacket;
import org.geysermc.mcprotocollib.protocol.packet.ingame.clientbound.level.ClientboundSoundPacket;
import org.geysermc.mcprotocollib.protocol.packet.ingame.clientbound.title.ClientboundSetActionBarTextPacket;
import org.geysermc.mcprotocollib.protocol.packet.ingame.clientbound.title.ClientboundSetSubtitleTextPacket;
import org.geysermc.mcprotocollib.protocol.packet.ingame.clientbound.title.ClientboundSetTitleTextPacket;
import org.geysermc.mcprotocollib.protocol.packet.ingame.serverbound.level.ServerboundAcceptTeleportationPacket;
import org.geysermc.mcprotocollib.protocol.packet.ingame.serverbound.player.ServerboundInteractPacket;
import org.geysermc.mcprotocollib.protocol.packet.ingame.serverbound.player.ServerboundMovePlayerPosRotPacket;
import net.kyori.adventure.key.Key;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.ConcurrentLinkedDeque;
import java.util.logging.Logger;

/**
 * One MCProtocolLib TCP session per connected Roblox player.
 * Connects to localhost:25565 as a real Java client — the server sees a genuine
 * ServerPlayer, so all plugins, commands, tab list, and events work natively.
 * This mirrors exactly how Geyser-as-plugin works.
 */
public class RobloxBotSession {

    private static final Logger LOG = Logger.getLogger("Crossplay");

    private final String username;
    private final int serverPort;
    private volatile TcpClientSession session;
    private volatile boolean spawned = false;
    private final ConcurrentLinkedDeque<RobloxEvent> eventQueue = new ConcurrentLinkedDeque<>();

    public record RobloxEvent(String type, String data) {}

    public RobloxBotSession(String username, int serverPort) {
        this.username = username;
        this.serverPort = serverPort;
    }

    // ── Connection ────────────────────────────────────────────────────────────

    public void connect() {
        // Offline mode: username only — requires online-mode=false in server.properties
        MinecraftProtocol protocol = new MinecraftProtocol(username);

        session = new TcpClientSession("127.0.0.1", serverPort, protocol);
        session.setFlag(MinecraftConstants.SESSION_SERVICE_KEY, new SessionService());

        session.addListener(new SessionAdapter() {
            @Override
            public void packetReceived(Session s, Packet packet) {
                handlePacket(s, packet);
            }

            @Override
            public void disconnected(DisconnectedEvent event) {
                spawned = false;
                LOG.info("[Crossplay] Bot " + username + " disconnected: " + event.getReason());
                RobloxSessionManager.handleDisconnect(username);
            }
        });

        session.connect(false); // non-blocking
    }

    public void disconnect() {
        spawned = false;
        if (session != null && session.isConnected()) {
            session.disconnect("Roblox player disconnected");
        }
    }

    // ── Inbound packet handling ───────────────────────────────────────────────

    private void handlePacket(Session s, Packet packet) {

        if (packet instanceof ClientboundLoginPacket) {
            spawned = true;
            // Brand payload must be a Minecraft-encoded String: VarInt(length) + UTF-8 bytes.
            // Sending raw bytes causes the server to read 'v'=118 as the length and crash.
            byte[] brandStr = "vanilla".getBytes(StandardCharsets.UTF_8);
            byte[] brandPayload = new byte[1 + brandStr.length]; // len=7 < 128 → 1-byte VarInt
            brandPayload[0] = (byte) brandStr.length;
            System.arraycopy(brandStr, 0, brandPayload, 1, brandStr.length);
            s.send(new ServerboundCustomPayloadPacket(Key.key("minecraft:brand"), brandPayload));
            // Client settings: 8-arg constructor in MCProtocolLib 1.21-SNAPSHOT (no ParticleStatus)
            s.send(new ServerboundClientInformationPacket(
                    "en_us", 10, ChatVisibility.FULL, true,
                    Arrays.asList(SkinPart.values()),
                    HandPreference.RIGHT_HAND, false, true
            ));

        } else if (packet instanceof ClientboundPlayerCombatKillPacket) {
            // Auto-respawn so the bot reappears on the MC server after dying
            spawned = false;
            s.send(new ServerboundClientCommandPacket(ClientCommand.RESPAWN));

        } else if (packet instanceof ClientboundRespawnPacket) {
            // Server confirms respawn — bot is alive again
            spawned = true;

        } else if (packet instanceof ClientboundPlayerPositionPacket pos) {
            // Acknowledge server teleport — server kicks if not confirmed
            s.send(new ServerboundAcceptTeleportationPacket(pos.getTeleportId()));
            s.send(new ServerboundMovePlayerPosRotPacket(
                    true, pos.getX(), pos.getY(), pos.getZ(), pos.getYaw(), pos.getPitch()
            ));

        } else if (packet instanceof ClientboundSetTitleTextPacket t) {
            queue("title", plain(t.getText()));

        } else if (packet instanceof ClientboundSetSubtitleTextPacket t) {
            queue("subtitle", plain(t.getText()));

        } else if (packet instanceof ClientboundSetActionBarTextPacket t) {
            queue("actionbar", plain(t.getText()));

        } else if (packet instanceof ClientboundSetHealthPacket hp) {
            queue("health", String.valueOf(hp.getHealth()));

        } else if (packet instanceof ClientboundSoundPacket sp) {
            queue("sound", sp.getSound() + "|" + sp.getX() + "|" + sp.getY() + "|"
                    + sp.getZ() + "|" + sp.getVolume() + "|" + sp.getPitch());
        }
    }

    private void queue(String type, String data) {
        eventQueue.add(new RobloxEvent(type, data));
    }

    private String plain(Component component) {
        try {
            return PlainTextComponentSerializer.plainText().serialize(component);
        } catch (Exception e) {
            return component.toString();
        }
    }

    // ── Outbound actions ──────────────────────────────────────────────────────

    /** Send a position + rotation update. Called from the /npc HTTP route at ~100 req/min. */
    public void sendMovement(double x, double y, double z, float yaw, float pitch, boolean onGround) {
        if (!isActive()) return;
        session.send(new ServerboundMovePlayerPosRotPacket(onGround, x, y, z, yaw, pitch));
    }

    /**
     * Attack an entity by its Minecraft entity ID via a proper Interact/ATTACK packet.
     * Triggers EntityDamageByEntityEvent with the Roblox player as the real damager —
     * kill credits, drops, and combat plugins all work correctly.
     */
    public void sendAttack(int entityId) {
        if (!isActive()) return;
        session.send(new ServerboundInteractPacket(entityId, InteractAction.ATTACK, false));
    }

    // ── Event relay ───────────────────────────────────────────────────────────

    /** Drain and return all queued server→Roblox events since the last poll. */
    public List<RobloxEvent> drain() {
        List<RobloxEvent> events = new ArrayList<>();
        RobloxEvent evt;
        while ((evt = eventQueue.poll()) != null) events.add(evt);
        return events;
    }

    // ── State ─────────────────────────────────────────────────────────────────

    /** True after login packet received and brand/settings sent. */
    public boolean isActive() {
        return session != null && session.isConnected() && spawned;
    }

    public boolean isConnected() {
        return session != null && session.isConnected();
    }

    public String getUsername() {
        return username;
    }
}
