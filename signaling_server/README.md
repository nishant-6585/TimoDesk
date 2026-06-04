# TimoDesk Signaling Server

Minimal WebSocket signaling server for WebRTC peer connection setup between the
Timo robot and browser/mobile viewers. Runs on your dev laptop on the same WiFi.

## Start

```bash
cd timoDesk/signaling_server
npm install
node server.js
```

## Browser viewer

Open `http://<your-laptop-ip>:3000` — the server also serves `viewer_web/index.html`.

Or open `viewer_web/index.html` directly from disk and type the signaling URL manually.

## Architecture

```
Robot (port 8080 MJPEG + WebRTC peer)
    │
    │  ws://laptop:3000   (WebSocket signaling)
    ▼
Signaling Server (port 3000)
    │
    │  ws://laptop:3000
    ▼
Browser / Mobile viewer
```

The signaling server only exchanges SDP offers/answers and ICE candidates.
After the WebRTC handshake, video flows directly P2P (no relay needed on same WiFi).

## Message protocol

| Sender  | Message                                      | Action                        |
|---------|----------------------------------------------|-------------------------------|
| Any     | `{type:"role", role:"robot"\|"viewer"}`      | Register role                 |
| Robot   | `{type:"offer", sdp:"..."}`                  | Forwarded to all viewers      |
| Viewer  | `{type:"answer", sdp:"..."}`                 | Forwarded to robot            |
| Robot   | `{type:"ice", candidate:{...}}`              | Forwarded to all viewers      |
| Viewer  | `{type:"ice", candidate:{...}}`              | Forwarded to robot            |
| Viewer  | `{type:"request_offer"}`                     | Prompts robot to re-send offer|
