#!/usr/bin/env node
/**
 * battery-bridge.mjs — DEV STOPGAP, not a production feed.
 *
 * The robot's real chassis charge (power_value) + charge_status live only in
 * robot-core, which Alpha Map talks to — our CSJBot SDK isn't connected to it
 * yet (same blocker as drive). Until that's fixed, this bridge tails the robot's
 * `adb logcat` for robot-core's `robot_info` packets, parses the real battery +
 * charging state, and POSTs them to the spine (/robot/battery). The spine then
 * broadcasts them in robot_status → the admin shows the true battery + a bolt.
 *
 * Requires: a single adb device connected (the robot). Auto-respawns logcat if
 * the device drops (the robot's adb-over-wifi port churns on reboot).
 *
 *   node battery-bridge.mjs            # spine at http://localhost:4000
 *   SPINE_URL=http://host:4000 node battery-bridge.mjs
 */
import { spawn } from 'child_process';

const SPINE = process.env.SPINE_URL || 'http://localhost:4000';
const HEARTBEAT_MS = 15000; // re-POST at least this often even if unchanged

let lastKey = null;
let lastPost = 0;
let buf = '';

function handleLine(line) {
  if (!line.includes('"command":"robot_info"')) return;
  const pv = line.match(/"power_value":(\d+)/);
  if (!pv) return;
  const battery = parseInt(pv[1], 10);
  const cs = line.match(/"charge_status":(\d+)/);
  const charging = cs ? parseInt(cs[1], 10) !== 0 : false;

  const key = `${battery}:${charging}`;
  const now = Date.now();
  if (key === lastKey && now - lastPost < HEARTBEAT_MS) return;
  lastKey = key;
  lastPost = now;
  post(battery, charging);
}

async function post(battery, charging) {
  try {
    const r = await fetch(`${SPINE}/robot/battery`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ battery, charging }),
    });
    console.log(`[battery-bridge] battery=${battery}% charging=${charging} → spine ${r.status}`);
  } catch (e) {
    console.log(`[battery-bridge] POST failed: ${e.message} (is spine up at ${SPINE}?)`);
  }
}

function start() {
  console.log(`[battery-bridge] tailing adb logcat → ${SPINE}/robot/battery …`);
  // Tag-filter to CosSlamLogger so we don't parse the whole firehose.
  const p = spawn('adb', ['logcat', '-v', 'brief', 'CosSlamLogger:D', '*:S']);

  p.stdout.on('data', (chunk) => {
    buf += chunk.toString();
    const lines = buf.split('\n');
    buf = lines.pop();
    for (const line of lines) handleLine(line);
  });
  p.stderr.on('data', (d) => {
    const s = d.toString().trim();
    if (s) console.log(`[battery-bridge] adb: ${s}`);
  });
  p.on('exit', (code) => {
    console.log(`[battery-bridge] adb logcat exited (${code}); retrying in 3s …`);
    setTimeout(start, 3000);
  });
}

start();
