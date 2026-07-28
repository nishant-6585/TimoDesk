# mikee-mcp-server

MCP server that exposes the **Mikee reception robot** to any MCP client — Claude Desktop, Claude Code, or a customer's own agent. Natural-language robot control with the spine's safety interlocks fully in force.

> Architecture rule preserved: this server is a **client of the spine** (port 4000), exactly like the Flutter admin and viewer_web. It never touches the robot SDK directly, so STOP latches, auth, and event logging apply to AI agents the same as to human operators.

## Tools

| Tool | What it does |
|---|---|
| `mikee_get_status` | Live robot status (online, battery, sensors) |
| `mikee_wave` | Greeting gesture |
| `mikee_list_nav_points` | Saved navigation points (from Supabase `nav_points`) |
| `mikee_navigate_to` | Drive to a saved point by name, optional arrival phrase |
| `mikee_cancel_navigation` | Cancel the active goal |
| `mikee_dock` | Return to charger |
| `mikee_start_patrol` / `mikee_stop_patrol` | Patrol a route of saved points |
| `mikee_emergency_stop` / `mikee_resume` | Safety interlock (blocks all motion until resume) |
| `mikee_take_snapshot` | Camera photo → admin Gallery |
| `mikee_ask_knowledge_base` | Ask the reception KB (RAG: FAQ fast-path → grounded Claude) |
| `mikee_kb_status` | KB health / chunk counts |
| `mikee_list_staff` | Staff directory (no biometrics) |

## Setup

```bash
cd mcp_server && npm install && npm run build
```

Environment:

| Var | Meaning |
|---|---|
| `SPINE_URL` | Spine base URL (default `http://127.0.0.1:4000`) |
| `SPINE_TOKEN` | Kiosk token (or Supabase JWT) the spine accepts |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | For nav-point lookups (read-only) |

### Claude Desktop / Claude Code config

```json
{
  "mcpServers": {
    "mikee": {
      "command": "node",
      "args": ["/absolute/path/to/TimoDesk/mcp_server/dist/index.js"],
      "env": {
        "SPINE_URL": "http://<spine-host>:4000",
        "SPINE_TOKEN": "<kiosk token>",
        "SUPABASE_URL": "https://<project>.supabase.co",
        "SUPABASE_ANON_KEY": "<anon key>"
      }
    }
  }
}
```

Then try: *"Check Mikee's battery, then send it to the Meeting Room and have it say 'Welcome to xboom'."*

## Development

```bash
npm test        # vitest — tools tested end-to-end over an in-memory MCP transport
npm run dev     # run from source (tsx)
npx @modelcontextprotocol/inspector node dist/index.js   # interactive testing
```

## Safety notes

- Motion tools return when the **spine accepts the goal**, not when the robot arrives — navigation is asynchronous.
- `mikee_emergency_stop` latches the spine interlock; every motion intent is rejected until `mikee_resume`. This is enforced spine-side, not by this server.
- Navigation requires the vendor Alpha Map SLAM map to be loaded and the robot localized (see project docs).
