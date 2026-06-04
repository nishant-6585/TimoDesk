const http = require('http');
const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');

const PORT = 3000;
const VIEWER_WEB = path.join(__dirname, '../viewer_web/index.html');

function ts() { return new Date().toISOString(); }
function log(msg) { console.log(`[${ts()}] ${msg}`); }

// ── HTTP server — serves viewer_web/index.html at GET / ───────────────────────
const httpServer = http.createServer((req, res) => {
    if (req.method !== 'GET' || req.url !== '/') {
        res.writeHead(404); res.end(); return;
    }
    fs.readFile(VIEWER_WEB, (err, data) => {
        if (err) { res.writeHead(404); res.end('viewer_web/index.html not found'); return; }
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(data);
    });
});

// ── WebSocket server ───────────────────────────────────────────────────────────
const wss = new WebSocket.Server({ server: httpServer });

let robot = null;          // single broadcaster
const viewers = new Set(); // all connected viewers

function send(ws, obj) {
    if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(obj));
    }
}

function broadcastToViewers(obj) {
    viewers.forEach(v => send(v, obj));
}

// When a new viewer connects, ask robot to re-send its offer so the viewer
// can join an already-running session.
function requestOfferFromRobot() {
    if (robot) send(robot, { type: 'viewer_joined', count: viewers.size });
}

wss.on('connection', (ws, req) => {
    const ip = req.socket.remoteAddress;
    log(`Connect  ${ip}`);

    ws.on('message', (raw) => {
        let msg;
        try { msg = JSON.parse(raw); } catch { return; }

        // ── Role registration ────────────────────────────────────────────────
        if (msg.type === 'role') {
            ws.role = msg.role;

            if (msg.role === 'robot') {
                if (robot && robot !== ws) {
                    log('Robot reconnected — evicting old viewers');
                    viewers.forEach(v => { send(v, { type: 'robot_disconnected' }); v.close(); });
                    viewers.clear();
                    robot.close();
                }
                robot = ws;
                log(`Robot    registered (${ip})`);
                send(ws, { type: 'viewer_count', count: viewers.size });
                // Notify all connected viewers that robot is now available
                broadcastToViewers({ type: 'robot_available' });
                if (viewers.size > 0) {
                    requestOfferFromRobot();
                }

            } else if (msg.role === 'viewer') {
                viewers.add(ws);
                log(`Viewer   registered (${ip})  total=${viewers.size}`);
                if (robot) {
                    send(ws, { type: 'robot_available' });
                    requestOfferFromRobot();
                } else {
                    send(ws, { type: 'waiting_for_robot' });
                }
            }
            return;
        }

        // ── Message routing ──────────────────────────────────────────────────
        if (ws === robot) {
            if (msg.type === 'offer') {
                log(`Offer    robot → ${viewers.size} viewer(s)`);
                broadcastToViewers(msg);
            } else if (msg.type === 'ice') {
                broadcastToViewers(msg);
            }
        } else if (viewers.has(ws)) {
            if (msg.type === 'answer') {
                log(`Answer   viewer → robot`);
                if (robot) send(robot, msg);
            } else if (msg.type === 'ice') {
                if (robot) send(robot, msg);
            } else if (msg.type === 'request_offer') {
                requestOfferFromRobot();
            }
        }
    });

    ws.on('close', () => {
        if (ws === robot) {
            log(`Robot    disconnected`);
            robot = null;
            broadcastToViewers({ type: 'robot_disconnected' });
        } else if (viewers.has(ws)) {
            viewers.delete(ws);
            log(`Viewer   disconnected  remaining=${viewers.size}`);
            if (robot) send(robot, { type: 'viewer_left', count: viewers.size });
        }
    });

    ws.on('error', (err) => log(`Error    ${ip}: ${err.message}`));
});

httpServer.listen(PORT, () => {
    log(`Signaling server on port ${PORT}`);
    log(`Browser viewer: http://<your-laptop-ip>:${PORT}`);
});
