# Timo Dashboard — Redesign Spec (Robot app)

Implementation reference for porting the approved **`robot_app/docs/dashboard/Timo Dashboard.html`**
prototype into Flutter (`dashboard_screen.dart`). The HTML file is the source of truth — open it
and resize the window to see the responsive behaviour; this doc captures the structure, tokens,
and behaviours so the Flutter build matches.

> Scope: this is the **on-robot dashboard** (opened from the ambient face). It is **face-dominant**
> with a row of reception **action tiles** (no chat box) and a right-hand **Quick Controls** panel.
> The face itself reuses the existing shared `FacePainter` / face rig — do **not** fork it. The
> Beam constants and pose table live in `robot_app/docs/timo_face_poses.md`.

---

## 1. Layout — three columns, full height, never scrolls

Root is a full-viewport Column: a **top bar** (fixed height) above a 3-column **body Row** that
fills the rest. Nothing in the dashboard scrolls — every region sizes to the viewport.

```
┌───────────────────────────────────────────────────────────────┐
│ TOP BAR  (56px)   ← Timo Dashboard · RECEPTION HOST   pills · clock │
├──────────────┬───────────────────────────────┬────────────────┤
│  NAV RAIL    │   FACE CARD (fills height)     │ QUICK CONTROLS │
│  240px       │   ┌─────────────────────────┐  │  320px         │
│              │   │  state chip             │  │  HEAD   (pad)  │
│  Menu        │   │     ◕   ◕   (big face)   │  │  CHASSIS(pad+  │
│  Services    │   │        ‿                │  │     speed)     │
│              │   └─────────────────────────┘  │  ARM (wave/rst)│
│  [perc tgl]  │   ACTION DOCK · 6 tiles, 1 row │  EMERGENCY STOP│
└──────────────┴───────────────────────────────┴────────────────┘
```

- **Columns:** nav `240`, center `Expanded`, controls `320`. At ≤1200 dp tighten to `208 / * / 284`.
  At ≤980 dp hide the nav rail and let the action dock wrap to 3 columns.
- **Center column:** padding `14`, vertical gap `12`. Two children:
  - **Face card** — `Expanded` (fills all remaining height), `minHeight 0`. The face must fill it.
  - **Action dock** — fixed height `clamp(78, 13vh, 116)` (≈ `0.13 × viewportHeight`, min 78, max 116).
- **No scrolling anywhere.** The right column uses height-distributing flex (see §4) so it always fits.

### Top bar
- Back button (34×34, rounded 10, 1px border `#2F2F2F`) → returns to ambient face.
- Title: **Timo** (accent) **Dashboard** (ink), 15px/700. Crumb `RECEPTION HOST` 11px, letter-spacing .18em, muted.
- Right side pills (30px tall, rounded 99, border `#2F2F2F`, bg `#171717`):
  `SDK Online` (green dot), `Perception On` (accent dot), `🔋 92%`, then a mono `H:MM` clock.

---

## 2. Color & type tokens

| Token | Value |
|---|---|
| bg | `#0F0F0F` |
| panel | `#151515` · panel2 `#1A1A1A` |
| line | `#262626` · line2 `#2F2F2F` |
| ink | `#F4F1EE` · muted `#9A9A9A` · muted2 `#6B6B6B` |
| accent | `#FF6B35` · accent-dim `#E14B1E` |
| green (ok/active) | `#4ADE80` on `#06200F` |
| red (e-stop) | `#FF5247` |
| radius | cards `18`, tiles `14`–`16`, pills `99` |
| font | system sans; mono for clock/readouts |

Accent is used for: active states, focus borders, the face glow, icon strokes, slider thumb/fill.

---

## 3. Nav rail (left, 240)

- **Brand block:** 38×38 rounded-11 gradient mark “T” (`linear-gradient(150deg, accent, accent-dim)`,
  soft accent shadow) + “Timo” / `FRONT DESK · BAY 1`.
- **MENU** group: Home (active), Enroll Staff, Robot Status, Manual Control, Settings.
- **SERVICES** group (dimmed, `SOON` tag, non-interactive): Voice Q&A, Pay, Navigate, Directory.
- Item: 11px vertical padding, 12 gap, 19px stroke icon + 13.5px label. Active = accent text,
  `rgba(255,107,53,.13)` bg, `rgba(255,107,53,.4)` border. Hover = `#171717` bg, ink text.
- **Footer:** “Live perception” toggle switch (on by default). Sliding 38×22 track, accent when on.

Each menu item maps to the existing route/screen (enroll, status, control, settings). The Services
items are placeholders for upcoming features — keep them visibly disabled.

---

## 4. Quick Controls (right, 320) — height-distributing, no blank space

Header “⇄ Quick Controls” (fixed), then a body that is a **Column whose 3 control blocks each
`flex: 1` (share the height equally)** and the **Emergency Stop is fixed at the bottom**. Inside
each block the header sits at top and the interactive body is **vertically centered** (so the panel
fills top-to-bottom with no empty gap, regardless of screen height).

Block chrome: 1px `#262626` border, rounded 14, bg `#151515`, padding ~`12`. Header row = a
letter-spaced uppercase name (muted, 9.5px/700) + a status **badge**.

- **Badge:** `active` = green pill on `#06200F`; `stop/idle` = `#242424` bg, muted text. 9px/800.

### Head block
- Status badge `ACTIVE`.
- **D-pad** (3×3 grid, `clamp(64, 13vh, 150)` square, 6 gap): ↑ / ← CTR → / ↓; corners blank.
  Buttons: `#161616`, 1px `#2F2F2F`, rounded 10, muted glyph; hover/active = accent border + tint.
  Center “CTR” is a darker recenter button. → drives head yaw/pitch + recenter.

### Chassis block
- Status badge `STOPPED` (→ `MOVING · <dir>` while driving, auto-reverts after ~1.4s).
- Same 3×3 d-pad but center is a **■ stop**. ↑↓←→ = forward/back/turn.
- **Speed** row: label + accent `%` readout, then a range slider `30–80`, step 5, default 50.
  Slider: 5px track `#2A2A2A`, 15px accent thumb with 2px `#0F0F0F` ring + accent glow.

### Arm block
- Status badge `IDLE` (→ `WAVING` then back).
- Row of two buttons (`clamp(32,4.6vh,38)` tall): **👋 Wave**, **⟲ Reset**. Wave also triggers a
  greeting on the face (see §6).

### Emergency Stop (fixed, bottom)
- Full-width, `clamp(44,6vh,52)` tall, red border/tint, `#FF5247` text, 800/letter-spaced.
- Hover = solid red, white text. Press = halts chassis+arm, face → attentive+surprised, brief flash.

> In the prototype these controls are simulated. In Flutter, wire each to the existing
> `spine_client` / control services (the same calls `control_screen.dart` already uses). Keep the
> badges reflecting real motor/arm state.

---

## 5. Action dock (center, below face) — 6 reception tiles, one row

A `repeat(6, 1fr)` grid, gap 10, height `clamp(78,13vh,116)` so tiles **scale to fit and never
wrap** on the wide robot display (at ≤980 dp it falls back to 3 columns × 2 rows).

Tile: column layout, `#181818→#141414` gradient, 1px `#262626`, rounded 14. A 40px rounded-11 icon
chip (`#0F0F0F`, accent stroke icon) at top; **label** (clamp 12–14px/700) + **sub** (clamp 9–10.5px,
muted, ellipsised) at bottom. Hover = accent border, lift `-2px`. Active/live = accent border + tint.
All sizes use `clamp(...vh...)` so a tile stays legible but shrinks with the viewport.

| Tile | Icon | Sub | Behaviour (drives face + a toast over the face) |
|---|---|---|---|
| **Greet** | raised hand | Welcome a visitor | face → greeting+happy, wave arm; toast “Greeting visitor”; revert ~2.6s |
| **Listen** | mic | Hear the visitor | face → listening → (after ~2.2s) thinking → speaking; live highlight while listening |
| **Check In** | clipboard | Visitor for a meeting | face → attentive+curious; toast “who are you here to see?” |
| **Directions** | signpost | Guide & wayfind | face → speaking; toast “Giving directions →” |
| **Page Staff** | broadcast | Notify reception | face → speaking; toast “Paging the front desk…” |
| **Rest** | moon | Low-power / sleep | **toggle**: face → sleepy / back to idle; tile stays lit while resting |

These are the robot’s real reception intents — they should call the corresponding
voice/greeting/nav/paging flows when those land (Services group), and in the meantime set the face
state so staff can preview each behaviour.

### Toast (feedback over the face)
A pill anchored bottom-center of the face card: `#141414`@.86 bg, 1px accent border, blur, accent
icon + text, slides up + fades, auto-hides ~2.6s. Use it to confirm every action.

---

## 6. Face behaviour on this screen

- Reuse the shared face widget/painter at **large size, filling the face card**.
- **Pin gaze slightly forward/down** (`gazeY ≈ 0.04`) instead of full idle-wander, so the dashboard
  face stays engaged with whoever is at the desk (dashboard-only flag — do not change the ambient face).
- State chip top-left mirrors the face state: `IDLE · relaxed…`, `ATTENTIVE · someone’s here`,
  `GREETING · welcome!`, `LISTENING…`, `THINKING · one moment…`, `SPEAKING · responding`,
  `SLEEPY · resting`.
- Actions and the Wave/E-Stop controls set the face state; it eases between poses (no snapping) and
  auto-reverts to **attentive** after each action.
- Intro: open in **greeting+happy**, settle to **attentive** after ~2.8s.

---

## 7. Responsive rules (so it fits any robot screen)

- All control pads, tiles, buttons, slider, e-stop use `clamp(min, …vh, max)` heights → shrink on
  short screens, cap on tall ones. The right column distributes height via `flex: 1` blocks.
- Breakpoints: **≤1200 dp** tighten side columns; **≤980 dp** hide nav rail + action dock → 3 cols.
- Target the robot’s landscape panel first (wide, ~1280×800), but verify nothing clips at shorter
  heights — the Arm row and Emergency Stop must always be visible.

---

## 8. Acceptance checklist

- [ ] Three columns; face card fills its column; face is large and centered, gaze pinned forward.
- [ ] Action dock = single row of 6 tiles on the wide display (3×2 only on narrow); never scrolls.
- [ ] Right panel blocks share height evenly — **no blank space below Arm**; E-Stop always visible.
- [ ] Tapping any action tile changes the face state + shows the matching toast.
- [ ] Head/Chassis/Arm controls update their badges; Speed readout tracks the slider; E-Stop halts all.
- [ ] Eyes render smooth (scanlines behind the face, not over the eyes); catchlight reads as a white glint.
- [ ] Whole dashboard fits the viewport at 1280×800 and at shorter heights with nothing cropped.
