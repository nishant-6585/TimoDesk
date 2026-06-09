package com.timoDesk.robotapp;

import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.CopyOnWriteArraySet;
import com.google.gson.Gson;
import com.google.gson.JsonObject;

/**
 * Singleton that manages broadcasting messages to all connected WebSocket clients.
 * Used to send battery updates and other system events to connected RobotSDK instances.
 */
public class WebSocketBroadcaster {
    private static WebSocketBroadcaster instance;
    private final Set<WebSocketClient> connectedClients = new CopyOnWriteArraySet<>();
    private final Gson gson = new Gson();

    private WebSocketBroadcaster() {}

    public static synchronized WebSocketBroadcaster getInstance() {
        if (instance == null) {
            instance = new WebSocketBroadcaster();
        }
        return instance;
    }

    /**
     * Register a new WebSocket client connection
     */
    public void registerClient(WebSocketClient client) {
        connectedClients.add(client);
        System.out.println("[WebSocketBroadcaster] Client registered. Total clients: " + connectedClients.size());
    }

    /**
     * Unregister a disconnected WebSocket client
     */
    public void unregisterClient(WebSocketClient client) {
        connectedClients.remove(client);
        System.out.println("[WebSocketBroadcaster] Client unregistered. Total clients: " + connectedClients.size());
    }

    /**
     * Broadcast battery update to all connected clients
     */
    public void broadcastBatteryUpdate(int batteryPercentage) {
        JsonObject message = new JsonObject();
        message.addProperty("type", "battery_update");

        JsonObject payload = new JsonObject();
        payload.addProperty("level", batteryPercentage);
        message.add("payload", payload);

        String jsonMessage = gson.toJson(message);
        System.out.println("[WebSocketBroadcaster] Broadcasting battery update: " + jsonMessage);
        System.out.println("[WebSocketBroadcaster] Total clients: " + connectedClients.size());

        for (WebSocketClient client : connectedClients) {
            try {
                client.sendMessage(jsonMessage);
            } catch (Exception e) {
                System.err.println("[WebSocketBroadcaster] Error sending to client: " + e.getMessage());
            }
        }
    }

    /**
     * Broadcast a generic message to all connected clients
     */
    public void broadcast(String message) {
        System.out.println("[WebSocketBroadcaster] Broadcasting to " + connectedClients.size() + " clients");
        for (WebSocketClient client : connectedClients) {
            try {
                client.sendMessage(message);
            } catch (Exception e) {
                System.err.println("[WebSocketBroadcaster] Error broadcasting: " + e.getMessage());
            }
        }
    }

    /**
     * Get number of connected clients
     */
    public int getConnectedClientCount() {
        return connectedClients.size();
    }
}

/**
 * Interface for WebSocket clients that can receive broadcasts
 */
interface WebSocketClient {
    void sendMessage(String message) throws Exception;
}
