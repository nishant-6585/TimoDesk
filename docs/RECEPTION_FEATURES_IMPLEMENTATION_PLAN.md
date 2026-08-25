# Reception-Robot Feature Implementation Plan

> Timo/Mikee showroom-first roadmap — product vision concierge, camera intelligence, and
> reception upgrades — for the robot app, spine, Supabase, and admin app.
>
> Grounded in what already ships (see HANDOFF.md): visitor check-in + host notification
> (`POST /visit`), Order/Enquiry lead capture → XBoom Workflow OS (`/xboom/lead`,
> `/xboom/catalog` with real SKUs), KB/RAG voice brain (ElevenLabs + Claude), staff face
> recognition, nav/escort/patrol state machines, notifications (Slack/WhatsApp/email/FCM).
> **Nothing below rebuilds those — every phase composes them.**

Robot hardware facts this plan relies on (confirmed 2026-08):
- Camera is in the **head** and pans/tilts with the `head` intent (lr/ud 0–100).
- 13.3" HD touch screen **is** the head/face screen.
- H = 1200 mm → camera eye-height ≈ 1.0–1.1 m; lidar nav with ±50 mm repeatability.
- Camera served by `CameraStreamPlugin` (MJPEG :8080 + `/snapshot`); spine consumes
  `/snapshot` via `RobotSDK.captureFrame()` — all vision runs **spine-side**.

Conventions that apply to every task: all robot actions as spine intents (STOP interlock
checked first, `commands/interlocks.ts`); vitest per new spine behavior (happy + failure
path), `tsc --noEmit` clean; RLS on every new table; DPDP — no visitor biometrics, ever;
features are ⬜ until verified on the physical robot.

---

## Phase 0 — Hardware verification spikes (do first, ~1 day total)

Cheap experiments that de-risk everything after. No code merges required; results go in
HANDOFF.md.

| # | Spike | Method | Decides |
|---|---|---|---|
| 0.1 | Head camera coverage envelope | Drive `head` lr/ud through range while watching MJPEG; note shelf heights visible from 1.0 m and 1.5 m standoff | Scan-pose table (1.3), showroom shelf-height rule |
| 0.2 | Shelf snapshot quality | 10 `/snapshot` captures of real shelves (drones, companion robots) at showroom lighting; eyeball blur/glare | Whether settle-delay after head move needs tuning; glare mitigation |
| 0.3 | Aquarium glass test | Snapshots of the underwater drone through the tank glass, multiple angles | Whether the aquarium needs a dedicated nav-point/angle preset |
| 0.4 | Claude vision dry run | Send spike 0.2/0.3 images + sample utterances to Claude vision by hand (script); check identification + referring-expression grounding quality | Prompt design for 1.2; go/no-go confidence for the whole concierge |
| 0.5 | Mic-array sound direction | Check CSJBot SDK for sound-source-localization API | Optional "turn toward speaker" input (nice-to-have, nothing depends on it) |

**Shelf-planning rule to hand Vishal now:** hero products between **0.6–1.4 m** shelf
height, identifiable from a 1–1.5 m standoff; higher shelves require the robot to stand
further back. Aquarium/demo platforms at floor-to-waist height are ideal.

---

## Phase 1 — Showroom Product Concierge (flagship, ~2–3 weeks)

Customer asks about any product on any shelf → Mikee identifies it by camera, explains it,
and hands off to the **existing** order pipeline. No product enrollment required (that's
Phase 3's optimization); identification is Claude vision, on the fly.

### 1.1 Spine: vision grounding service — `services/product-vision.ts` (M, 2–3 d)

- `identifyProduct(frame: Buffer, utterance: string, candidates: CatalogItem[])` →
  Claude vision call: snapshot + the customer's words + the XBoom catalog (names +
  one-line visual descriptions) in the prompt. Returns
  `{ match: 'sku'|'generic'|'ambiguous'|'not_in_frame', sku?, genericLabel?, candidates?, bbox? }`.
- Reuses `fetchXboomCatalog()` for the SKU list; fuzzy-match Claude's best-guess name
  against catalog entries (port the KB fuzzy matcher, add the stopword guard HANDOFF
  already flags).
- **Guardrails in the prompt:** never state price/availability — those come only from
  catalog/KB after the SKU resolves; ignore the white-and-black reception robot if it
  appears in frame (mirrors/glass); if multiple products plausibly match the utterance,
  return `ambiguous` with candidate descriptions instead of guessing.
- Anthropic API key lives in spine `.env` (sops) — never on the robot.
- Tests: catalog match happy path, ambiguous → candidates, not-in-frame, API-error →
  clean failure (mock the Anthropic client; fixture JPEGs from spike 0.2).

### 1.2 Spine: `identify_product` intent + handler (M, 2 d)

- New intent in `commands/handlers.ts` + route in `server.ts`:
  `{type:'identify_product', utterance}` → interlock check → `captureFrame()` →
  `identifyProduct()` → broadcast `product_identified` event
  `{sku|genericLabel, confidence, bbox, snapshot_capture_id}` to all clients.
- Snapshot stored via existing captures pipeline (products only — DPDP-neutral).
- ElevenLabs client tool `identify_product` registered alongside the existing voice
  tools (`docs/elevenlabs_agent_tools.md`), so "what's this?" works by voice with a
  filler phrase ("let me take a look…") covering the 2–4 s round trip.
- Tests: intent routing, STOP-interlock rejection, event payload contract.

### 1.3 Spine: head-scan state machine — `services/product-scan.ts` (M, 2–3 d)

Used only when 1.2 returns `not_in_frame`.
- Sweep table of head poses (from spike 0.1, e.g. lr 20/50/80 × ud 2 levels); per pose:
  move head → settle ~500 ms → capture → ground → stop on first hit.
- **Return-to-person is mandatory** on every exit path (success, exhausted, STOP) — the
  final step restores gaze toward the customer (gaze tracker owns it once returned).
- Optional per-nav-point head-pose presets (`nav_points` gains `scan_poses jsonb`) —
  ±50 mm nav repeatability makes stored poses reliable.
- Mutually exclusive with patrol/escort/dock (same pattern as escort⇄patrol exclusion).
- Tests: sweep ordering, early-exit, STOP mid-scan aborts + restores pose, exclusivity.

### 1.4 Robot app: concierge UI (M, 3–4 d)

- **Confirm overlay** on the face screen: snapshot with highlight box from `bbox` +
  "This one?" ✓/✗ big tap targets; auto-dismiss to eyes. (Screen is 13.3" — roomy.)
- **Product card**: image, 3–4 spec bullets, price from catalog/KB, [Order] [Enquiry]
  buttons that open the **existing** Order/Enquiry FAB flow **prefilled** with the
  identified SKU → existing `POST /xboom/lead`.
- **QR handoff**: product card renders a `qr_flutter` code deep-linking to the product
  page for on-phone browsing/ordering (convenience path, not the primary).
- Voice-first: card appears while Mikee speaks the explanation (existing KB/RAG answer
  path, keyed by SKU); eyes return after interaction ends.
- Tests: widget tests for overlay/card; flow test faked over the spine WS contract.

### 1.5 KB: product content packs (S, 1–2 d, mostly content work with Vishal)

- Ingest per-SKU spec sheets/FAQs through the existing KB platform so RAG answers
  ("how deep does it dive?", "compare it with the one next to it") are grounded.
  Tag KB chunks with SKU so identified-product questions retrieve scoped content first.
- Explanation rule (already in 1.1 prompt): general knowledge may describe the product
  class; **price/stock/promo claims only from catalog/KB** — otherwise Mikee offers to
  call a salesperson.

### 1.6 Admin app: concierge visibility + config (S–M, 2 d)

- Events feed already shows broadcasts — add a `product_identified` card (snapshot
  thumbnail, SKU/label, confidence) in Live Feed + events log.
- Settings panel: concierge on/off, confidence threshold, scan enabled, per-nav-point
  scan poses editor (reuse nav-point editor patterns).
- Leads already land in XBoom OS; no admin work needed for orders.

**Phase-1 acceptance (on hardware):** stand at a shelf, ask "what's the orange drone?" →
correct SKU confirmed on screen ≥8/10 tries for catalog products in the 0.6–1.4 m band;
ambiguous asks produce a sensible clarifying question; STOP aborts a scan instantly;
an order placed from the card reaches XBoom OS with the right SKU.

---

## Phase 2 — Camera intelligence for operations (~1–2 weeks)

Generic object detection (not product-specific) composed with patrol. One new spine
service powers three features.

### 2.1 Spine: generic detector — `services/object-detect.ts` (M, 2–3 d)

- `@tensorflow-models/coco-ssd` on the existing tfjs-node runtime (same pattern as
  `face-embedding.ts`): `detectObjects(frame)` → `[{class, score, bbox}]`. 80 COCO
  classes cover the ops use cases (person, backpack, handbag, suitcase, umbrella,
  cell phone, bottle, chair…). No robot-side cost.
- Tests: detection contract on fixture images, model-load failure → feature disabled
  cleanly (never blocks boot).

### 2.2 Lost & found via patrol (M, 2–3 d)

- Patrol arrival at each point (stationary → sharp frames): capture → detect → any
  unattended-item class **with no person in frame** → save capture + row in new
  `found_items` table (RLS; class, nav point, patrol run, capture id, `purge_after`).
- After-hours patrol run ends → summary notification via existing channels ("2 items:
  backpack @ Reception 21:40, umbrella @ Drone Shelf 21:52").
- Admin: Lost & Found screen under gallery (list + snapshot + resolve/dismiss).

### 2.3 Blocked-path & unattended-item alerts (S, 1–2 d)

- Same patrol hook: configured "must-be-clear" nav points (fire exit, corridor) with
  obstructing classes detected → immediate notification with snapshot.
- Daytime unattended-bag variant (item persists across two consecutive passes, no
  person nearby) → security notification. Detection-only, no identity — DPDP-clean.

### 2.4 Interest/footfall zones (S–M, 2 d)

- During idle patrol: person-count per nav point (COCO `person` class — counts only,
  no identity, nothing biometric stored) → `zone_counts` rows → admin dashboard
  heat-list ("Drone shelf: 34 dwellers today"). Optional live ping to sales when a
  person lingers at a zone beyond N seconds.

---

## Phase 3 — Embedding-based product recognition (optimization, ~1 week, optional)

Only if Phase-1 API latency/cost hurts in practice, or offline operation is needed.
Mirrors the proven face pipeline exactly.

- `product_embeddings` table (pgvector, like `staff_face_embedding`); CLIP-class
  image-embedding model on tfjs-node; enrollment = 8–15 in-situ photos per product
  (taken **through the robot camera at the shelf** — spike 0.3 lesson: enroll the
  underwater drone through the aquarium glass).
- Admin: product enrollment screen reusing the staff-enrollment UX + camera-source
  toggle; re-run a `calibrate`-style threshold script as the catalog grows (same
  margin-guard + nearest-neighbor method as faces).
- Runtime: embedding match first (fast, free); below threshold → fall back to Claude
  vision (Phase 1 path stays as the long tail). Claude-vision results can auto-collect
  enrollment crops over time ("self-enrolling" catalog).

---

## Phase 4 — Reception experience upgrades (~2–3 weeks, ordered by value)

| # | Feature | Builds on | Size |
|---|---|---|---|
| 4.1 | **Multilingual voice** — Hindi + English first; ElevenLabs agent language config + multilingual KB retrieval sanity pass (Voyage embeddings are multilingual; verify recall on Hindi queries) | voice brain | M |
| 4.2 | **Appointment awareness** — `appointments` table (RLS) + admin CRUD; check-in dialog matches "here to see X at 3" → host notify with appointment context; unmatched → existing manual flow | `POST /visit` | M |
| 4.3 | **Returning-visitor greeting (DPDP-safe)** — check-in issues a QR/phone-number token; presenting it next visit personalizes the greeting. No biometrics — `visitor` table stays clean | check-in | S–M |
| 4.4 | **Guided tour mode** — patrol route + per-point `arrival_text` already exist; add a "tour" wrapper: curated point list, KB-driven narration per stop, pause/resume by voice, interest hand-off ("want details? just ask") | patrol + nav arrival text | S–M |
| 4.5 | **Wayfinding fallback** — robot busy/charging → face screen shows a static map + walking directions for the asked destination (nav-point metadata gains a human-directions string) | nav points | S |
| 4.6 | **Demo scheduling** — "book a drone demo" → lead of kind `enquiry` with requested slot into XBoom OS (sales confirms); no calendar system on our side | /xboom/lead | S |

---

## Phase 5 — Ops, analytics & polish (~1–2 weeks, continuous)

| # | Feature | Notes | Size |
|---|---|---|---|
| 5.1 | **Scheduled behaviors** — auto-dock below battery threshold + at closing time; patrol windows (after-hours security, idle-hours tour loop). Spine cron (node-cron) + admin schedule editor; every scheduled action still goes through interlocks | S–M |
| 5.2 | **Analytics dashboard** — from existing `events` + new `zone_counts`: visitors/day, identifications/day, top asked products, **KB gap report** (questions RAG answered poorly — mine `ask` logs) → feeds Vishal's content work | M |
| 5.3 | **After-hours security patrol** — patrol window + person detection at night → immediate notification with snapshot (person presence only, no identity) | S (composes 2.1 + 5.1) |
| 5.4 | **Idle-screen promotions** — ambient face occasionally interleaves a promo card (admin-managed list, KB/catalog images); face always returns | S |
| 5.5 | **Error tracking** — Sentry/Crashlytics in both Flutter apps + spine (HANDOFF flags this as a top hole; a showroom robot that fails silently loses sales silently) | S–M |

---

## Explicitly deferred / rejected for the showroom

- **On-robot ML (ML Kit object detection)** — weak Android 7.1.2 CPU, 5 coarse classes;
  spine-side vision wins on every axis. Revisit only for a no-network requirement.
- **Payment on the robot** — QR to the customer's phone sidesteps payment compliance;
  orders stay lead-based in XBoom OS.
- **Face-based visitor personalization** — DPDP line stays absolute: staff-only
  biometrics. Returning-visitor feature (4.3) is token-based instead.
- **Precision servo product framing** — wide snapshot + language grounding beats
  pan-tilt hunting; no zoom hardware anyway.
- **Queue/token + mask detection** — hospital-vertical features; parked until a
  hospital deployment is actually scoped.

---

## Sequencing at a glance

```
Week 1        Phase 0 spikes → Phase 1.1–1.2 (vision service + intent)
Weeks 2–3     Phase 1.3–1.6 (scan, robot UI, KB packs, admin) → hardware acceptance
Weeks 4–5     Phase 2 (detector + lost&found + alerts + footfall)
Week 6        Phase 5.1/5.3/5.5 (schedules, security patrol, error tracking)
Weeks 7–9     Phase 4 (multilingual first, then appointments, tour)
Later/if-needed  Phase 3 (embedding recognition)
```

Dependencies: 1.2←1.1; 1.3←0.1; 1.4←1.2; 2.2/2.3/2.4←2.1; 5.3←2.1+5.1; 3←1 (falls back
to it). Everything else is independent and can be resequenced by demo/sales pressure.

Every phase ends with: vitest green + `tsc --noEmit` clean, physical-robot verification
of the headline flow, and a HANDOFF.md entry (✅/⬜/⚠️ per this repo's honest-reporting
convention).
