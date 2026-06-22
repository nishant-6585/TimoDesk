# Mission Control Dashboard — Design Verification Checklist

## HEADER (64px fixed)
- [ ] Background: #121212 with 80% opacity + blur
- [ ] Border bottom: #2A2A2A 1px
- [ ] Left: Logo (36×36) with gradient + "xboom" text
- [ ] Center: "Mikee — Reception Robot" (desktop only, 13px #9CA3AF)
- [ ] Right: Battery pill (40×6px progress) + Status pill + Avatar (28px circle)
- [ ] All text: Inter font, correct spacing

## SIDEBAR (220px fixed)
- [ ] Background: #121212
- [ ] Border right: #2A2A2A 1px
- [ ] Nav items: 6 items with icons
  - Dashboard (active = orange highlight + left bar)
  - Control
  - Live Feed
  - Gallery
  - Event Log
  - Settings
- [ ] Footer: Version + "xboom · Land Air Water"
- [ ] Active state: #FF6B35/12 background, 4×20px orange bar on left

## STATUS CARDS ROW (4 cards)
### 1. Robot Status Card
- [ ] Label: "ROBOT STATUS" (11px #9CA3AF uppercase tracking 0.12em)
- [ ] Icon: smart_toy (18px #3A3A3A) top-right
- [ ] Pulsing dot: 14px, breathing animation (1.8s)
- [ ] Status text: "ONLINE"/"OFFLINE" (24px bold, green/red)
- [ ] Connection text: "Connected · {latency}ms latency" (13px)
- [ ] Last seen: "Last seen just now" (11px #6B7280, mono)
- [ ] Border top: #2A2A2A 1px divider

### 2. Battery Card
- [ ] Label: "BATTERY" (11px #9CA3AF)
- [ ] Icon: bolt/battery (18px #FF6B35) top-right
- [ ] ProgressRing: 104×104, 9px stroke, animated 0→percent over 1.1s
- [ ] Center text: "{percent}%" (26px bold) + "CHARGING"/"ON BATTERY" (10px)
- [ ] Bottom text: "Full in ~42 min" or "Est. 5h 10m remaining" (11px #6B7280, mono)

### 3. Visitors Card
- [ ] Label: "TODAY'S VISITORS" (11px #9CA3AF)
- [ ] Icon: groups (18px #3A3A3A) top-right
- [ ] Number: "24" (34px bold)
- [ ] Subtext: "visitors checked in" (13px #9CA3AF)
- [ ] Sparkline: 132×38, orange #FF6B35, gradient fill, polyline, end dot
- [ ] Trending: Icon (14px green) + "+3" (green) + "from yesterday" (grey) (11px)

### 4. Sessions Card
- [ ] Label: "ACTIVE SESSIONS" (11px #9CA3AF)
- [ ] Icon: hub (18px #3A3A3A) top-right
- [ ] Number: "2" (34px bold)
- [ ] Subtext: "admin sessions active" (13px #9CA3AF)
- [ ] Avatars: NK (orange) + RS (blue), 32px circles, overlapping with 2px border
- [ ] Bottom: "You + 1 other" (11px #6B7280)

## LIVE FEED (16:9 aspect ratio)
- [ ] Container: #000000 background, 16px radius
- [ ] Placeholder: videocam icon + text "Live Feed · 192.168.1.42:8080"
- [ ] LIVE badge: Top-left, red dot + "LIVE" text (11px tracking widest)
- [ ] Fullscreen button: Top-right (36×36 transparent with icon)
- [ ] Stats bar: Bottom, 5px padding
  - RES: 640×480 (10px grey)
  - FPS: 15 (10px green)
  - LATENCY: 45ms (10px white)
  - Clock: HH:MM:SS (11px mono 50% opacity)
- [ ] Motion halted overlay: Red gradient background + pill when stopped

## QUICK CONTROLS
- [ ] Title: "Quick Actions" (14px semibold)
- [ ] Emergency button: Full width, 56px height
  - Idle: #EF4444 red with breathing glow (2s, 22→8px blur)
  - Pressed: #7F1D1D dark red
  - Text: "EMERGENCY STOP" bold tracking-wider
- [ ] Action grid: 2×2, 10px gap
  - Control Room (icon + label)
  - Wave Hello (icon + label)
  - Take Snapshot (icon + label)
  - Go Home (icon + label)
- [ ] Head Position:
  - Label + value (LR 0-100) (11px)
  - Icon (rotating robot) + Slider (orange fill)
- [ ] Speed:
  - Label + value (0.3-0.8x) (11px)
  - Slider (orange fill)

## EVENT STREAM TABLE
- [ ] Header: Green dot + "Live Event Stream" + "View All →"
- [ ] Columns: TIME | EVENT | DETAILS | SESSION
- [ ] Rows: Alternating bg (white 1.2% opacity)
- [ ] Event chips: Color-coded by type
  - command_* → blue #3B82F6
  - face_detected/visitor → green #4ADE80
  - safety_stop → red #EF4444
  - battery_low → amber #F59E0B
  - snapshot_saved → orange #FF6B35
  - admin_session → grey #6B7280
- [ ] New events: Appear every 5 seconds with "just now" timestamp
- [ ] Time: mono 12px (grey)
- [ ] Details: mono 13px white 85%

## FLOATING STOP BUTTON
- [ ] Position: bottom-right, 24px margin
- [ ] Size: 56px circle
- [ ] Idle: #EF4444 with breathing glow (22→8px blur over 2s)
- [ ] Pressed: #7F1D1D
- [ ] Icon: stop (28px white)
- [ ] Fixed shadow: #EF4444 0 0 0 1.5px, spread 1.5px

## TOAST NOTIFICATIONS
- [ ] Position: top-right (80, 20)
- [ ] Background: #1A1A1A, colored border 44% alpha
- [ ] Animation: Slide from right + scale 0.9→1 over 0.35s
- [ ] Auto-dismiss: 3.2s
- [ ] Icon + message (13px)
- [ ] Colors by type (same as event chips)

## RESPONSIVE
- [ ] Desktop: Sidebar visible, 4-col grid, full layout
- [ ] Mobile (<900px): No sidebar, 2-col grid, scrollable
- [ ] Breakpoint: 900px

## ANIMATIONS
- [ ] PulseDot: 1.8s scale 1→2.4 + opacity 0.55→0, ease-in-out
- [ ] Battery ring: 1.1s cubic-bezier(0.22,1,0.36,1)
- [ ] Stop glow: 2s ease-in-out infinite
- [ ] Toast: 0.35s cubic-bezier(0.22,1,0.36,1) slide + scale
- [ ] Event fadeIn: ~0.45s

## COLORS (ALL HEX EXACT)
- [ ] Background: #0F0F0F
- [ ] Surface: #121212
- [ ] CardTop: #1A1A1A
- [ ] CardBottom: #161616
- [ ] Border: #2A2A2A
- [ ] Primary: #FF6B35
- [ ] PrimaryDark: #E14B1E
- [ ] Success: #4ADE80
- [ ] Error: #EF4444
- [ ] ErrorPressed: #7F1D1D
- [ ] Info: #3B82F6
- [ ] TextPrimary: #FFFFFF
- [ ] TextSecondary: #9CA3AF
- [ ] TextMuted: #6B7280

## TYPOGRAPHY
- [ ] Font: Inter (main), JetBrains Mono (numeric values)
- [ ] Weights: 400, 500, 600, 700, 800, 900 (as needed)

---

**Status:** Pending systematic verification
**Next:** Compare current app with this checklist and fix any deviations
