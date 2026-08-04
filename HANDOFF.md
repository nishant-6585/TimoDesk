# Session Handoff

> **🗂️ 2026-08-04 (later) — Product catalog picker: FAB flow is now catalog-first (search XBoom's price list → tap → form prefilled with real SKU). Spine test-verified; robot analyze-clean; NOT bench-tested.**
> Tapping Order/Enquiry now opens **`ProductPickerScreen`** (search-first, 450ms debounce, infinite scroll 30/page, 2-min abandon timer, always-visible "Can't find it? Type it yourself" fallback + catalog-down state — capturing the lead always beats a perfect SKU). Picking a product prefills LeadFormScreen; if the visitor edits the product text the SKU is dropped (no longer matches). Data path: robot → spine **`GET /xboom/catalog?search=&limit=&offset=`** (kiosk auth; params clamped 1-50/0-10k) → **5-min TTL in-memory cache** (50 keys, failures never cached) → HMAC-signed POST to NEW **`robot-catalog`** edge function → service-role read of `pricelist` returning ONLY kiosk-safe columns (`website_price` is the one price exposed; `cost_price`/`dealer_price`/`unit_price`/`notes` never leave — deliberately NOT the anon-readable `pricelist_public` view, which leaks unit_price + internal notes). Filters `availability <> 'Out of Stock'`, `ilike` search on name/brand/category (PostgREST specials escaped). `robot-lead-incoming` now accepts optional `product_code` (visitor-picked `woo_sku`) instead of always 'WALK-IN'.
> - Spine env: optional `XBOOM_CATALOG_ENDPOINT` — defaults to `XBOOM_LEAD_ENDPOINT` with the last path segment swapped, so one URL configures both. Spine xboom tests now **21** (was 12; found a real bug: `Number(null)`=0 made absent `limit` clamp to 1). `tsc` clean, analyze clean.
> - ⚠️ Catalog is **thousands of rows** (Woo-synced nightly); ~3,131 rows are miscategorized as category 'Xboom' in XBoom OS — category browse would be junk, which is why the UI is search-first. No product images exist in `pricelist` (Woo `images[]` discarded by the sync) — image cards need an xboom-flow mapper + column change first.
> - ⬜ **Bench:** search latency on robot Wi-Fi (spine cache should make page-1 instant), on-screen keyboard vs list focus, SKU lands in XBoom enquiry `product_code`.

> **🛒 2026-08-04 — Showroom Order/Enquiry capture: face-screen FABs → spine → XBoom Workflow OS. Spine test-verified; robot app analyze-clean, NOT bench-tested; XBoom edge function NOT deployed yet.**
> Two new visitor-facing FABs on the robot's face screen (stacked above the mic: blue **Enquiry**, green **Order**) open a full-screen kiosk form (`robot_app/lib/screens/lead_form_screen.dart` — name/phone required, email/notes optional, quantity stepper on Order; 2-min abandon timer wipes a walked-away-from form; thank-you screen auto-returns to the face). Submission: robot → spine `POST /xboom/lead` (kiosk-token auth, `services/xboom_lead_api.dart`) → spine signs the raw body **HMAC-SHA256 `x-xbm-signature`** and forwards to a NEW edge function **`robot-lead-incoming`** in the XBoom Workflow OS project → inserts into `enquiries` (`lead_source: 'walk_in'`, order→urgency high/hot, enquiry→medium/warm; phone/email ride in `notes` — the table has no contact columns; salesperson omitted so `auto_assign_enquiry_salesperson` round-robins). Direct anon insert is impossible by design (enquiries INSERT is `TO authenticated` + sales/admin role) — the HMAC function mirrors XBoom's own `leads-incoming` WordPress-webhook pattern.
> - Spine: `handlers/xboom.ts` + `services/xboom.ts`, route in server.ts (before the Supabase gate — uses XBOOM_* env, not spine's Supabase), `xboom_lead_created` RobotEvent (audit + admin broadcast, **no PII in broadcast**), `.env.example` → `XBOOM_LEAD_ENDPOINT` + `XBOOM_WEBHOOK_SECRET` (unset = 503, feature off). **12 new vitest** (handler 6 + service 6), `tsc --noEmit` clean, suite 273/274 — the 1 fail is `nav-points.test.ts` "returns the points ordered", **pre-existing on clean main** (verified via stash), untouched here.
> - XBoom side (in the `xboom-flow` repo, branch `chore/dependabot-fixes`, **left uncommitted** — Lovable-synced repo, Nishant decides how to land it): `supabase/functions/robot-lead-incoming/index.ts` + `config.toml` entry (`verify_jwt = false`; auth is the mandatory HMAC).
> - 🔴 **Go-live steps:** (1) deploy `robot-lead-incoming` to the XBoom project (`mxsotxddcvmeluqonuuj`) and set its `ROBOT_WEBHOOK_SECRET` function secret; (2) same secret + full function URL into spine `.env` (`XBOOM_WEBHOOK_SECRET`, `XBOOM_LEAD_ENDPOINT`) + `secrets:push`; (3) rebuild + install robot APK.
> - ⬜ **Bench check:** tap Order on the chest screen → fill → submit → enquiry appears in XBoom OS Sales with source "Walk-in" badge, assigned round-robin, hot-lead notification fires; kill spine → form shows the friendly failure line; abandon form 2 min → auto-returns to face. ⚠️ `product_code` is hardcoded `'WALK-IN'` (no catalog lookup from the kiosk) — confirm that's acceptable to sales reporting.

> **🔒 2026-07-30 — Security pass: unauthenticated spine routes closed, RLS actually enforced, anon key off the robot. Spine test-verified; both Flutter apps compile-only (NO analyzer/toolchain in this session) and NOT bench-tested.**
> Audit triggered by the "7 problems in every vibe-coded app" list. Three of the seven applied here. What shipped:
> 1. **Unauthenticated HTTP routes closed.** `/recordings`, `/recordings/:file` (GET **and** DELETE), `/record/start|stop|status`, `POST /robot/battery` and `DELETE /captures/:id` had **no auth check at all** — and :4000 is on a permanent public ngrok domain, so office camera footage was listable and downloadable by anyone with the URL. The recording routes moved out of `server.ts` into **`spine/src/handlers/recordings.ts`** (injected `RecordingController`; ffmpeg lifecycle stays in server.ts) so the gate is unit-testable — **23 new vitest**. `/robot/battery` and `DELETE /captures/:id` gained inline `authorizeRequest`.
> 2. **`?token=` query fallback, playback only.** `authorizeRequest(req, {allowQueryToken:true})` — the admin opens a clip URL in the browser (`url_launcher`), which cannot set an Authorization header. Accepted on `GET /recordings/:file` and **nowhere else** (tests pin that list, delete and status all reject it).
> 3. **RLS was on but decided nothing.** Every policy in 003 was `to authenticated using (true)`, and Supabase signups default to open — any account on the project could read `staff`, `staff_face_embedding` (biometrics), `visitor`, `conversation`. **Migration 017** adds an `admin_user` allowlist + `public.is_admin()` (security definer, stable, pinned search_path) and rewrites every policy through it. **Seeded from `auth.users`, so today's logins keep working**; new signups get nothing. `config.toml` signups → `false`.
> 4. **`nav_points` was writable by `anon`** (011 recreated the policies with no role), and the anon key was **hardcoded in the robot APK** — anyone who unzipped it could rewrite where the robot drives. New **`GET/POST/PATCH/DELETE /nav-points`** on the spine (`handlers/nav-points.ts`, **19 new vitest**, coordinates validated finite, PATCH cannot move a point); both apps now go through it, the anon key + project URL are **gone from `robot_app`** (kiosk token instead), and 017 drops anon from the table.
> 5. **Admin app's login gate defaulted OFF.** `main.dart` `FLAVOR` defaulted to `dev` → the documented ship command (`flutter build web`, no `--dart-define`) built an app with no login screen. Default is now `prod`; local dev needs `--dart-define=FLAVOR=dev`.
> 6. **Live service-role key was committed** in `.claude/settings.json` (two allowlist entries). Stripped, but it is in git history — **rotation is the fix**.
> - Spine **202 vitest passing** (was 160), `tsc --noEmit` clean. (`desk-pose`/`person-check` suites fail to *load* in this container — `@tensorflow/tfjs-node` native binding — environmental, unrelated.)
> - 🔴 **DO FIRST, in this order:** (1) **rotate `SUPABASE_SERVICE_ROLE_KEY`** in the dashboard + `secrets:push`; (2) run migration 017 (session pooler) and confirm `select * from admin_user` lists you; (3) turn signups OFF in the **hosted** dashboard — `config.toml` only configures a local stack; (4) set `KIOSK_TOKEN` in the robot's Settings if it is still blank (nav points now need it).
> - ⬜ **Needs a machine with Flutter + the robot:** `dart analyze` both apps, `flutter build web`, robot APK; then bench: nav points list/capture/rename/delete **on the chest screen** (new spine round-trip), gallery playback + delete in the admin, record start/stop, and an admin login on a `prod` build.
> - ⚠️ **Deploy spine + APK together** — the robot's nav-point screen talks to routes that only exist on the new spine.
> - ⬜ **Not done, ranked:** robot Java plugins (`:8080` camera, `:8081-3` motors) still accept **any** LAN connection — that bypasses the spine STOP interlock entirely and is now the biggest hole; ElevenLabs API key still lives in the APK (proxy it through the spine like `/elevenlabs/ask`); **zero error tracking** in either app (no Sentry/Crashlytics anywhere — users won't report, they'll just leave); **no backup/restore drill** ever run (spine `recordings/` is local disk only, nothing off-box); Flutter test coverage is 5 files total vs the spine's 202, with no golden/screenshot tests.
> - ✅ **CI now covers the admin app** (`ci.yml` job `admin-app`: analyze → test → `build web --dart-define=FLAVOR=prod`). It only ever ran on `robot_app`, which is how an analyzer **error** sat unnoticed in `app/test/widget_test.dart` (`defaultRobotIp` is `String?`) — fixed, along with the removed-in-Dart-3 `invariant_booleans` lint in `app/analysis_options.yaml`. Admin analyze is gated on **errors only** (`--no-fatal-warnings`): the app carries ~170 pre-existing warnings/infos (unused imports, `withOpacity`, `avoid_print`) that would fail day one — clear those, then drop the flag. Admin tests are **fatal**; robot_app's step is still `flutter test || true`. Verified locally by Nishant: `dart analyze` clean on `robot_app`, admin down to the pre-existing warning set. Also unfixed: `app/analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` but `flutter_lints` is not in `app/pubspec.yaml` dev_dependencies, so that ruleset never loads (robot_app has it at `^3.0.0`).

> **🛡️ 2026-07-29 — Phase 0 of the transport refactor: ROBOT_IP behind RobotSDK + chassis dead-man watchdog. Spine side test-verified; robot side compile-only, NOT yet bench-tested.**
> Groundwork for a future cloud-spine (robot travels, spine fixed): the spine now has exactly ONE place that knows the robot's address, and the robot stops itself if its brain vanishes mid-motion.
> 1. **ROBOT_IP leaks collapsed.** `RobotSDK` gained `getCameraStreamUrl()` + `captureFrame(timeoutMs)` (non-throwing, JPEG-validated, aborts on timeout; `takeSnapshot` now delegates to it). The ffmpeg recorder (`server.ts`) and `FaceRecognitionService` (now takes an injected `FrameSource`, no URL building) go through the SDK. `ROBOT_IP` is referenced ONLY in `index.ts` (composition root). `camera_port` dropped from FACE_CONFIG. A future `TunneledRobotSDK` is now a one-class job.
> 2. **Robot-side dead-man (`ChassisControlPlugin.java`).** Real gap: `close()` only stopped teleop on a CLEAN disconnect — if the spine host dies without TCP FIN (power loss, Wi-Fi drop), the socket goes half-open, `readWebSocketFrame()` blocks forever, teleop keeps self-renewing via the local 150ms `move()` loop, and a navi goal keeps executing (and the chassis silently RESUMES blocked goals). Also: dead sockets never left `clients`, so 3 unclean spine restarts exhausted `MAX_CLIENTS=3` → nobody could ever reconnect. Now: a 1s `deadmanTick` on the chassis scheduler (a) reaps sockets silent >30s, (b) if the current motion is **WS-commanded** (`wsMotion` — set by WS move/rotate/navi/go_home, cleared by WS stop/cancel and by every MethodChannel takeover) and NO client frame arrived for **8s** → `cancelNavi` + stop drive + emits a `deadman` event. Chest-screen (MethodChannel) motion is deliberately NOT supervised — local operator. Transient socket blips do NOT cancel nav (no cancel in `close()`; the spine's 1s naviWatch poll reconnects and refreshes the window).
> 3. **Spine feeds the dead-man**: `RealRobotSDK` sends `{cmd:'ping'}` on the chassis WS every 2s while open (commands alone don't prove liveness during a held joystick / long navi leg); the plugin's existing pong reply is dropped silently spine-side.
> - Spine **167 vitest passing** (was 159; new: `real-camera.test.ts` — captureFrame/takeSnapshot/stream-URL/ping contracts, `face-recognition-source.test.ts` — frame-source injection), `tsc --noEmit` clean. Robot flavored debug APK builds ✓.
> - ⚠️ **Deploy spine + APK together**: the 8s window is fed by spine pings; an old spine + new APK is only safe during nav (the 1s position poll counts as traffic) — a held teleop drive could stop after 8s.
> - ⬜ **Bench check:** start a WS navi → `kill -9` the spine (or pull the Mac's Wi-Fi) → robot must stop within ~8s and logcat show `DEADMAN TRIGGERED`; chest-screen d-pad + robot's own Go must be unaffected with the spine fully down; spine reconnect mid-nav (restart `npm run dev` quickly) must NOT cancel the goal before 8s.

> **👋 2026-07-28 (later) — greeting fixed on the dashboard + a real lockout bug (`a3a6889`). NOT yet hardware-tested.**
> Reported symptom: robot doesn't greet a recognized face while the dashboard is open. Two causes:
> 1. **Greeting was screen-local.** Decision + debounce + `WavingHandOverlay` all lived in `AmbientFaceScreen`. The dashboard is `push`ed on top, so the ambient State survived and still SPOKE, but every visual sat on the hidden screen — and `DashboardScreen` subscribed only to voice/playback/ASR, never to `SpineClient.faceDetected`, so its mini-face could never react. (Its "Perception On" pill is cosmetic — `_perceptionOn` is never read by logic.) → NEW **`robot_app/lib/greeting_provider.dart`** (`greetingProvider`, keepAlive) owns the decision (`mayGreetStaff`/`mayGreetVisitor`) + the active greeting; ambient renders the overlay and still owns speaking + mic hand-off, dashboard renders greeting face + named toast (**display only** — speaking there would double up).
> 2. **Self-renewing greeting lockout (real bug, hit the ambient screen too).** A greeting blocked by the priority rule (nav/escort active · live voice session · Mikee mid-sentence) was **recorded as delivered**; since the spine re-emits the same identity every ~5s, every blocked tick refreshed the `regreetMinutes` (default 2 min) window → that person was never greeted while the condition held, and **permanently** if `navigatingTo` was left stale. Blocked greetings are no longer recorded (a later tick greets once free; still nothing queued/replayed). Added a **stale-nav watchdog** in `NavPointsNotifier`: clears `navigatingTo`/escort after **7 min** with no update — deliberately longer than the spine's 4-min navi + 6-min dock watchdogs.
> - `dart analyze` clean, robot debug APK builds. ⬜ **Bench check:** stand in front on the dashboard → toast + greeting face + spoken hello; then start an escort, get blocked, and confirm the greeting still lands after it ends (was silent for 2 min+ before).

> **🚶 2026-07-28 (later) — Follow-Me escort mode built (spine-side, unit-tested, NOT yet run on hardware).**
> New `escort_start`/`escort_stop` intents: walks saved waypoints like patrol, but advances only when a **person is verified present** — at every waypoint arrival AND at a ~2m live-distance interval mid-leg. Nobody within 30s → escort stops in place (doesn't walk off without the visitor).
> - **`spine/src/escort.ts`** — `EscortController`, a pure injected-deps state machine (13 vitest). **Checkpoint spacing = live distance tracking**, not straight-line interpolation: it's fed the SAME pose samples `startNaviWatch` already polls (`escort.handlePose` inside the watch tick — deliberately no 2nd `get_position` poller, which would race the SDK's single-slot pose resolver). At ≥2m traveled: `cancelNavi` (pause) → person check → re-`navi` the SAME target — the cancel→navi round-trip patrol arrival cleanup already proves on hardware. New `escortCancelPending` flag (mirrors `arrivalCancelPending`) so escort-initiated cancels aren't read as user cancels.
> - **Person check = face-DETECTION-only** (`countFaces` in face-embedding.ts: tinyFaceDetector boxes, NO landmarks/descriptors/identity, nothing stored — DPDP). `services/person-check.ts` scanner (4 vitest): head sweep LR 50→30→70 via `sdk.setHeadPosition`, snapshot each (`sdk.takeSnapshot` → same /snapshot endpoint), pass if ANY frame has a face, recenter after; errors are misses (fail-safe → escort stops). Chosen over CSJBot proximity fusion (can't distinguish "visitor following" from "something nearby") and over a new body-detection model (no new deps).
> - Wiring in server.ts: escort rides the normal navi pipeline (naviState banners/`arrivalText` speech/arrival watch all work; `source:'escort'`, `escort:{active,index,total,checking}` on `navi_state`); `escort_event` RobotEvent breadcrumbs (started/checkpoint/arrival_check/person_confirmed/finished); patrol⇄escort⇄dock mutually exclusive; STOP interlock rejects `escort_start` + is re-checked before every leg/resume dispatch.
> - Spine **159 vitest passing** (was 140), `tsc --noEmit` clean. Zero behavior change to patrol/navi/drive/dock/interlocks (additive only).
> - **Escort UI DONE (both apps, `b8147f4`)** — admin Navigation screen got an `EscortPanel` (tap points → ordered route chips → Start/Stop + live waypoint-x-of-y banner w/ amber "scanning" state; `escortStatusProvider` synced from `navi_state.escort`); robot Nav Points screen got a collapsible "Escort — Follow Me" builder + an escort banner that replaces the nav banner while active. Robot-side `escortStart` requires the spine (checks run there; returns false → snack when offline). Verified: analyze clean on touched files, admin `flutter build web` ✓, robot flavored debug APK ✓.
> - **Checkpoint speech DONE (`27bc59e`, after live test found pauses silent)** — robot SpineClient now streams `escort_event`s; nav provider speaks them via the ElevenLabs path: check → "One moment — just making sure you are still with me.", checkpoint pass → "Great, there you are. This way.", mid-route visitor_lost → wait-here line (phrases are consts in nav_points_provider — RobotConfig settings candidates). Arrival confirms stay silent (next leg's departure line covers them).
> - ⚠️ **Needs hardware:** (1) does the chassis resume cleanly on cancel→re-navi mid-route (expected yes — same path as patrol arrival + the 600ms ChassisControlPlugin settle); (2) does a redundant `cancel_navi` (no active goal) still return a `cancel_result`? If NOT, a stale `escortCancelPending` could swallow ONE later user cancel (same exposure as `arrivalCancelPending`); (3) face-detection-as-person-proxy: visitor must roughly face the robot during a check — tune sweep range/settle (700ms) + timeout on the bench; (4) no UI yet — trigger via WS intent (admin app/MCP tools are follow-ups).

> **🔌 2026-07-28 — MCP showcase built: Mikee MCP server + plugin platform (all unit-tested, NOT yet run against live spine/robot).**
> 1. **NEW `mcp_server/` — mikee-mcp-server** (TypeScript, `@modelcontextprotocol/sdk`, stdio). Exposes 14 tools to any MCP client (Claude Desktop/Code, customer agents): status, wave, snapshot, list/navigate-to nav points (by name, from Supabase `nav_points`), cancel/dock, patrol start/stop, emergency STOP/resume, ask-KB (`/ask`), kb-status, list-staff. It is a **client of the spine** (WS intents on :4000 w/ kiosk-token auth + HTTP Bearer) so all safety interlocks apply to AI agents. WS protocol has no request IDs → client serializes one intent in flight, matches expected response types (`ack`/`stopped`/`resumed`/`robot_status`/`position`), ignores broadcasts. 14 vitest passing (tools tested end-to-end over `InMemoryTransport`). Config: `SPINE_URL`, `SPINE_TOKEN`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` — see `mcp_server/README.md` for Claude Desktop config JSON.
> 2. **MCP plugin platform in spine** — add/remove external MCP servers (Slack, MS365, CRM/ticketing) via config, no code per integration. `services/mcp-plugins.ts` (file-backed registry, default `spine/mcp-plugins.json`, gitignored — holds tokens; tokens NEVER returned over HTTP, `has_token` flag instead) + `handlers/mcp-plugins.ts` → `GET/POST /mcp/plugins`, `DELETE /mcp/plugins/:name`, `POST /mcp/plugins/:name/enable|disable` (same auth as other endpoints, no Supabase dependency).
> 3. **Voice brain can consume plugins** — `rag.ts` gated behind **`MCP_TOOLS_ENABLED=true`** (default OFF, demo voice path byte-identical): enabled plugins → Claude API MCP connector (`mcp-client-2025-11-20` beta, `mcp_servers` + one `mcp_toolset` per server via `buildMcpRequestExtras()`), bounded `pause_turn` continuation (max 3).
> 4. Spine tests **114 passing** (was 110 + 8 registry + 4 HTTP handler − overlap); `tsc --noEmit` clean both packages.
> 5. **Admin "MCP Plugins" screen DONE** — `app/lib/features/mcp_plugins/` (provider mirrors kb_provider; screen: list cards w/ enable/disable switch + delete-confirm, add-plugin dialog w/ obscured token field, `MCP_TOOLS_ENABLED` info banner). Route `/mcp-plugins` + sidebar item (Icons.extension). `dart analyze` clean (info-level withOpacity deprecations only, house style); `flutter build web` ✓. NOTE: `flutter analyze` wrapper crashes on this Mac (analysis server exit 64) — use `~/development/downloads/flutter/bin/dart analyze` instead.
> 6. **KB expansion DONE** — (a) `/kb/ingest-file` (PDF via pdf-parse deep import, DOCX via mammoth, txt/md; base64 JSON, 15 MB cap); (b) `/kb/crawl` background same-origin BFS jobs (in-memory registry, `GET /kb/crawl[/:id]` progress, 50-page hard cap); (c) **3rd-party KB providers** `/kb/providers` CRUD (kb-providers.json, gitignored, tokens write-only) + **local-first ask chain** in rag.ts: FAQ → local grounded (top sim ≥ 0.4) → providers by priority (generic HTTP `POST {question}→{answer}`) → grounded fallback. Admin: KB screen got Add document / Crawl website FABs, crawl-progress strip (2s poll while running), External Knowledge Sources section (priority arrows, enable/disable, add dialog). Spine 140 tests ✓, `flutter build web` ✓. file_picker dep added.
> 7. **KB brain LIVE-SMOKED ✅ (2026-07-28)** — Voyage + Anthropic + ELEVENLABS_TOOL_SECRET (uuid) in spine/.env. Found & fixed the "always handoff" bug: **migration 016 — IVFFlat index (014) was created on an EMPTY table** → degenerate centroids → every query returned 0 rows (only self-matches survived); replaced with HNSW via dashboard SQL editor (015 also re-asserted the no-threshold RPC — deployed fn had drifted). Verified: text/DOCX/PDF ingest → grounded asks (sim 0.6-0.7, correct spoken answers), crawl job lifecycle, /elevenlabs/ask 401 on bad secret + speakable fallback on errors. Test chunks deleted (facts were fabricated) — **KB is empty, add real content**. ⚠️ Voyage free tier = 3 req/min until a payment method is added — real crawls will 429; add billing first. cupsfilter-generated PDFs fail pdf-parse (quirk); Chrome-printed + normal PDFs fine.
> 8. **Voice-grounding infra DONE (2026-07-28 pm)** — Voyage billing added (3 RPM cap lifted); xboom.in crawled (9 pages → 74 chunks, real grounded answers verified); keys ROTATED + vaulted (`secrets:push` ✓); ElevenLabs agent updated: `ask_knowledge_base` webhook tool + `{{robot_name}}` prompt + Vars placeholder `Minee`. **Permanent tunnel: ngrok static domain `https://flatly-antiquely-proton.ngrok-free.dev` → :4000** (authtoken configured in `~/Library/Application Support/ngrok/ngrok.yml`; restart cmd: `ngrok http --url=flatly-antiquely-proton.ngrok-free.dev 4000`). Cloudflare named tunnel abandoned — xboom.in zone lives in someone else's CF account (Nishant's new account owns no zones).
> ⬜ **Left:** point the ElevenLabs tool URL at `https://flatly-antiquely-proton.ngrok-free.dev/elevenlabs/ask` + Publish + preview-test (verify hit in spine logs); make ngrok survive reboots (LaunchAgent) — it currently runs as a background process; live voice test on the robot; add curated KB facts (hours, directions, FAQ) — crawl covered products only; add a real MCP server via the Plugins screen + flip `MCP_TOOLS_ENABLED`; register mikee-mcp-server in Claude Desktop ("send Mikee to the Meeting Room" demo); hosted MCP servers need **OAuth bearer tokens, not native API keys**; consider spine kiosk-token per-client scoping later.

> **🧭 2026-07-27 (late night) — voice-nav UX batch, all live-verified same night.**
> 1. **New nav points voice-actionable instantly** — points list refreshes at session start + no-match triggers refresh-and-retry (was: loaded once at app start, so admin-captured points were invisible until restart).
> 2. **Compound-word matcher** — "restroom" ↔ "Rest Room" via space-squashed comparison (was score 0 → apology).
> 3. **Stopword guard** — a garbled "take me to the…" containment-matched "The Dock Cabin" at 0.9 and DROVE THERE (live incident); trivial fragments (stopwords) can no longer anchor a match. 13/13 tests.
> 4. **Greeting vs speech priority** — nav > active session > greeting; losers are cancelled (recorded as greeted), never queued/retried; no more mid-session spoken hellos muting the mic via the half-duplex gate.
> 5. **Mid-conversation cutoff** — idle clock now RESTARTS when Mikee's audio drains, so the visitor always gets the full 15s window (was measured from the user's last speech, so long answers ate the reply window). Window stays 15s (was asked "raise to 25?" — root cause was the clock, not the length).
> 6. **Navigation speech choreography** — nav start (any source) closes the agent session (motor noise was triggering stray agent turns mid-route); failed dispatch now SPEAKS an apology instead of silent standstill; on arrival with the visitor in view the mic auto-opens for the next command (lost-visitor line still fires when nobody's there).
> Verified live: "take me to the restroom" → "Rest Room" drive; "dancing station" garble → still Charging Station via token overlap; escort lost-visitor line fired at Charging Station. **Battery was 20% at close — charge before tomorrow's testing.**

> **🎙️ 2026-07-27 — Deafness trilogy solved; voice→navigation proven END-TO-END on hardware.**
> Robot was deaf+mute all day after installing the f40df1e build. THREE stacked root causes, all found and fixed; by night the full chain — English speech → ElevenLabs transcript → NavVoice/Checkin matcher → SDK → SLAM `MoveToGoals` → wheels — ran live ("take me to the command cabin" drove the robot).
>
> **Root causes & fixes (robot_app):**
> 1. **No ElevenLabs key in the APK.** e34372f removed the hardcoded key; a build without `--dart-define=ELEVENLABS_API_KEY` has none unless saved in Settings. Restored the **"Timo Robot" key (`sk_ad…99f7`, git history `e34372f^:robot_app/lib/config.dart`)** into the robot's prefs — it is **still valid for Conversational AI**; it 401s on `/v1/user` only because it's permission-scoped (test validity against `GET /v1/convai/agents/<id>`, NOT `/v1/user`).
> 2. **In-process AIUI boots asleep** (`STATE_READY 等待唤醒`) and streams ZERO mic audio until woken; stock wake word is Chinese. `Speech.openMicro()` is a **no-op** for the in-process engine. Real wake = `AIUIMixedManager.getInstance().startAudioRecognize()` (AIUI_SOFT → ALSA startRecord; else CMD_WAKEUP(7)) — now called in `AudioBridgePlugin.startSpeechEngine()` each session. Proof of life: `Mikee.Audio: CSJBot mic chunk = 2560 bytes` + state flips to `STATE_WORKING`.
> 3. **USB mic array (`/dev/snd/pcmC1D0c`, "AIUI-USB-MC") is exclusive-open** and `com.csjbot.robotsdk.ten`'s own CAE grabs it at its process start → our AlsaRecorder gets "open pcm device failed" (the 777/SELinux hint in the vendor error is a red herring — it's EBUSY). Fix: `stopSpeechEngine()` now deliberately **never releases the recorder** (hold-forever, matches the historically-working state). Reclaim ritual without reboot: root kill-loop `am force-stop com.csjbot.robotsdk.ten` ×25s while opening a session (recorder retries ~2s), then restart robotsdk (`InfomationActivity` → `startservice RobotSdkService`) — it loses the mic race but chassis/cos works. Holder check: scan `/proc/*/fd` for `pcmC1D0c` via `su`.
>
> **Also fixed:** idle watchdog now closes **manual (mic-button) sessions too** — was auto-only by design — after **15s** of user silence (was 25s, changed per Nishant); hold-to-talk counts as activity; button reverts to orange. Verified live repeatedly.
>
> **Ops gotchas learned (the day's time sinks):**
> - **Nothing vendor auto-starts reliably after reboot** (kiosk app disabled): asragent/robotsdk/Mikee may all need manual start. asragent repeatedly dies as a cached activity — and it does NOT matter for our audio (our AIUI is in-process); its absence only causes robotsdk's chronic `DeadObjectException sendAlsaData` spam, which is harmless noise for us.
> - **Killing/restarting robotsdk.ten while our app runs kills the app's AIDL binder** (`IAarToSdkApp` → DeadObjectException on every chassis call, incl. `get_position` and `move_to`) and it never rebinds → **bounce the Mikee app after any robotsdk restart** (robotsdk's mic retries exhaust quickly, so the mic survives the bounce gap; re-grab with one mic-button tap).
> - Post-reboot nav also needs the usual **Alpha Map → load map → Relocate** before goals move; a stale pre-reboot session shows `Slam move_to Task_id` mismatch errors.
> - Vendor ASR wall is now OPEN with our app owning the mic + engine started: `speechInfo` delivers real text (mixed EN/中文 quality) → `VendorASR utterance` → matchers. ElevenLabs transcripts are the reliable English path.
> - Wireless-debug adb port changes every reboot; classic `adb connect <ip>:5555` persists — use it (restart `adb kill-server` if "No route to host" while `nc` succeeds).
>
> **⬜ Follow-ups:** fuzzy point matcher too eager on stopwords (`"…go to the"` matched "The Dock Cabin" — add a guard); vendor-ASR Chinese transcribing Mikee's own speaker voice (cosmetic); consider grabbing the mic at app startup (not first session) to win the boot race without the ritual; bake `ELEVENLABS_API_KEY` into CI builds via `--dart-define`; rotate the git-history key eventually. Escort re-engagement + check-in voice flow still owed a clean live pass (nav E2E + hearing are proven).

> **🧠 2026-07-02 (later) — Voice brain built + mic-wall status corrected.**
> - **Text-first voice brain DONE** (`bf64a84`, pipeline T5/T6/T7). Embedding provider = **Voyage voyage-3.5 (1024-dim)**; migration **014** re-dimensions `kb_chunk.embedding` 1536→1024 + adds a `match_kb_chunk` cosine RPC. `services/kb-embedding.ts` (asymmetric query/document), `services/kb.ts` (searchKb/upsertChunk/backfillEmbeddings), `scripts/kb/ingest.js`. FAQ fast-path (`pickFaqAnswer`, is_faq + sim>0.85 → skip LLM) → grounded **Claude `claude-opus-4-8`** fallback (`services/rag.ts`, thinking off + effort low + final-answer-only, per claude-api skill). `POST /ask` endpoint. New deps: `@anthropic-ai/sdk`. Env: `VOYAGE_API_KEY`, `ANTHROPIC_API_KEY`. **79 vitest passing.** ⬜ **Left:** apply migration 014, set both keys, Vishal supplies KB content, run `ingest.js`, smoke-test `/ask`.
> - **⚠️ Mic-wall correction:** the pipeline earlier called the CSJBot mic-wall a hard blocker (T1) — that was **stale**. It's **RESOLVED** (`enableFace(true)` before `init()` in `MikeeApplication.java` → beamformed PCM reaches `AudioBridgePlugin.onAudio`; live loop = **ElevenLabs Conversational AI**, `voice_agent.dart`). So STT (T8) + TTS (T9) are **done via ElevenLabs**.
> - **🔀 Architecture decision PENDING — two brains.** ElevenLabs runs its OWN hosted LLM (Claude Haiku + dashboard prompt), **not KB-grounded** — it can invent pricing/specs, which the blueprint forbids. The new T5/T6/T7 RAG is the grounded brain but only serves `POST /ask` (text). To reconcile, ground the ElevenLabs agent in the xboom KB via one of: **(A)** ElevenLabs built-in KB upload (fastest, but forks the KB), **(B)** a server-tool webhook → spine `/ask` (**recommended** — reuses our RAG, single source of truth), **(C)** custom-LLM endpoint on spine (purest, most work). Not yet decided.
>
> **🗂️ 2026-07-02 — Blueprint gap review + pipeline execution (T2/T3/T4 + desk-location).** Reviewed the codebase against the **Timo Architecture & Delivery Blueprint** (the 9 capabilities) and wrote **`TASK_PIPELINE.md`** — the ordered, executable plan (P0 finish-the-vision-MVP → P1 voice-brain-text-first → P2 ears/mouth → P3 go-live → P4 V2). Key finding: MVP ≈ 55–60%; the **voice half (F1 intake, F4, F5) is the missing core**, partly blocked by the vendor **mic-firmware wall** (`robot-mic-vendor-wall`), but the blueprint says build the brain text-first so that blocker doesn't stall P1. Then executed:
> - **T2 — F7 remote snapshot → cloud → gallery DONE** (`65e8753`). The snapshot handler grabbed a JPEG and discarded it; now uploads to a private `snapshots` bucket + inserts a `capture` row (kind=`admin_snapshot`, attributed via new `capture.actor`), and the admin **Gallery is now two tabs (Snapshots / Staff)**. New `GET /captures` (signed URLs). Migration **012**. `spine/src/captures.ts` (saveSnapshot/listSnapshots, 5 tests). ⚠️ **Not yet run against real robot/Supabase — apply migration 012 first.**
> - **T3 — recognition robustness, code-half DONE** (`183e4ee`). The bench part (re-enroll loose faces) needs the robot, but I made `scripts/enroll/calibrate.js` emit an **explicit re-enrollment worklist** (per-person pose count + worst-self, `THIN`/`LOOSE` flags, names the closest impostor pair, precision-threshold recommendation on overlap). Fixed stale recognizer comments (threshold `0.57→0.53`, cadence `1000→500`). Deleted the superseded `calibrate.ts`; README points at `calibrate.js`. **Bench step still owed.**
> - **T4 — host handoff hardening DONE** (`38…`/`notify`). `notify.ts` email is now a **real send via Resend HTTP API** (fetch-only, no SMTP dep) gated on `RESEND_API_KEY`+`NOTIFY_EMAIL_FROM` (log-only fallback); fixed a **latent bug** — sends never checked `res.ok`, so a Slack/Interakt 4xx passed silently (now `assertOk` throws → `/visit` 500s). 5 notify tests. **Still owed (ops):** set `notify_channel` on hosts (most NULL); test WhatsApp against a live Interakt key.
> - **NEW FEATURE — capture staff desk/location during enrollment** (`…desk`). Migration **013** adds `staff.desk_x/y/z/rotation/desk_captured_at`. `/enroll` + `PATCH /staff` accept an optional `desk_pose` (shared `deskColumns()` validator, 3 tests); `GET /staff` returns it. A **"Desk location (optional)" capture tile** was added to the enroll flow in **both** the admin app (`live_feed_screen`, via spine `getPosition()`) and the robot app (`enroll_screen`, via native chassis `getPosition()`). UX: park the robot at the desk → Capture → enroll. Groundwork for **#71 navigate-to-desk** (feeds the existing `navi` intent); the "go to desk" action is the follow-up.
> - **Spine now 68/68 vitest, tsc clean.** Work is on branch **`feat/task-pipeline-and-f7-snapshot`** (not yet merged to main).
>
> **🤖 2026-06-26 — MockRobotSDK removed.** The spine now talks **only** to the real robot via `RealRobotSDK`. Deleted `spine/src/robot/mock.ts` + `tests/mock-sdk.test.ts`; dropped the `ROBOT_MODE` env var and its mock/real branch in `index.ts` (set `ROBOT_IP` — the spine connects on boot); trimmed the mock-only sensor-simulator tests from `sensors.test.ts`. Spine: `tsc --noEmit` clean, **46/46 vitest passing** (no more flaky mock-timing tests). Historical notes below that reference the mock, `ROBOT_MODE`, or the flaky mock-sdk tests are **stale** — the build/test/file-map references have been corrected, but the dated session narratives are left as-is for history.
>
> **Last updated:** 2026-06-20 (**#82 animated face + live perception DONE (= #89 P2)** — Beam render replaces the #89 P1 placeholder, gaze/greeting wired, **kiosk credential resolved** (closes the last auth go-live item); see the callout below. Prior context: **auth go-live DONE — JWKS/ES256 verification + real login gate, prod-proven**; **Firebase/FCM config activated** — `firebase_options.dart` + Android plugin committed, APK proven, only spine service-account key + on-device test remain (see `docs/FIREBASE_SETUP.md`); #70/#87/#88 done; **#89** P1 DONE; **#90** Part A done + Part B code-complete, native-build break resolved (phone remote builds on device); **#91 deployment & config** (kill localhost/hardcoded-IPs — hybrid: cloud web app + on-prem spine, robot self-register) + **#92 CI/CD GitHub Actions** added to pipeline) · **For:** Claude Code on any future session picking up Mikee work
>
> **Read this BEFORE `PROJECT_STATUS.md` / `FLUTTER_APP_SUMMARY.md`** — those are older. This file is the live state.

---

## ✅ #82 Animated face + live perception (#89 P2) — DONE (2026-06-20)

The chest-screen face now has the real Beam/OLED render **and** is wired to live perception. **The `FaceState`/`FaceStateKind` contract is unchanged** — the painter was swapped, not the wiring (#89 §6 rule). This also **resolves the last open auth item (the kiosk operator credential).**

- **Beam render replaces the #89 placeholder.** `face_rig.dart` (new) = `FaceRig` animator: derives a smoothed `LiveState` from the public `FaceState` (poseFor/exprMod, eases k=9/20/22, blink scheduler, idle wander, breathing bob, greeting bounce, speaking lip-sync, ring/dots phases) — a 1:1 port of `robot_app/docs/mikee_face_prototype.html`. `face_painter.dart` rewritten to render `LiveState` in Beam style: **two-pass glow** (blurred accent bloom + sharp shape — canvas2d `shadowBlur` has no 1:1 in Flutter), iris/pupil/catchlights `clipRRect`'d to the eye, all geometry `×S = shortestSide/100`. Driven by a `Ticker` + a `repaint:` Listenable so only the painter repaints (no per-frame tree rebuild) — GPU-light for Android 7.1.2.
- **Wire 1 — local gaze (anonymous).** `gaze_tracker.dart` (new) polls the robot's own `/snapshot` ~300ms (REUSES the enroll pattern — never opens a 2nd camera), runs ML Kit → `GazeResult{facePresent,gazeX,gazeY}` drives the eyes + `attentive`. Presence hold 3s (5s from greeting). Stores nothing (DPDP).
- **Wire 2 — spine identity.** `services/spine_client.dart` (new) = robot_app's FIRST spine **WS client** (`ws://<spine>:4000`, dart:io WebSocket, no new dep, fixed-backoff reconnect). Parses `face_detected` (`eventPayload.payload.{name,staff_id}`, matched-only) → `greeting` + "Hi, &lt;name&gt;!" overlay (3.5s, debounced 10 min); parses `robot_status.personDetected` → coarse `attentive` fallback (eyes centered).
- **Wire 3 — mock voice cycle.** Debug overlay in `ambient_face_screen.dart` (extends the existing `kDebugMode` panel): "voice demo" → idle→listening(3s)→thinking(5s)→speaking(8s)→idle + top progress line, "live perception" toggle, gaze/spine readout. No separate FaceStudioScreen.
- **Kiosk credential — resolved (auth go-live item #5).** Auth is JWKS/ES256 (`jose`), so the chest screen (no Supabase session) authenticates with a static **`KIOSK_TOKEN`** shared secret checked inside `verifyToken` (covers WS **and** HTTP, honored in **production**, not gated by the dev bypass) → userId `kiosk-robot`. robot_app `RobotConfig.kioskToken` (persisted, editable in Settings) is sent on WS auth + enrollment (`RobotConfig.authToken`, falls back to `test-token` under the dev bypass). Documented in `spine/.env.example`. **Tradeoff:** long-lived static credential — rotate manually.
- **Verify:** `dart analyze` clean for the new files (2 remaining infos are pre-existing in `app_widgets.dart` + `enroll_screen.dart`). `spine tsc --noEmit` clean (3 mock.ts unused-var errors pre-date this). Spine tests 61/63 (2 failures = the known flaky mock-sdk/sensors timing tests). **NOT device-tested — bench checklist on the real robot:** (1) **gaze X mirroring** — gaze is derived from the ML Kit face-box **center** (NOT `headEulerAngleY`); a front-facing/mirrored snapshot may track the eyes AWAY from the visitor → flip `gaze_tracker.dart _mirrorX`. (2) **glow bloom** — eye sigma (~34 @ S≈10) is in the prototype ballpark, but brow/mouth coefficients (2.0/3.0) run ~2× the prototype's bloom; dial down on the OLED panel if heavy. (3) **ML Kit FPS** — 300ms `/snapshot` poll writes a temp file each cycle; bump to 400ms on slow eMMC. `_gazeYScale 0.6` already damps vertical so eyes don't slam to frame edges.
- **Files:** new `robot_app/lib/{face_rig.dart, gaze_tracker.dart, services/spine_client.dart}`; rewritten `face_painter.dart` + `ambient_face_screen.dart`; edited `config.dart`, `settings_screen.dart`, `enroll_screen.dart`; spine `auth/middleware.ts` + `.env.example`.
- **P3 (next):** drive `listening/thinking/speaking` from the real #80 voice pipeline instead of the mock cycler; amplitude lip-sync from TTS.

---

## TL;DR — Where things stand right now

- **Phase 1A** (spine-side LIDAR/obstacle awareness against `MockRobotSDK`) — **SHIPPED.** 49/49 vitest passing, `tsc --noEmit` clean of wire-format errors (only an unrelated `moduleResolution=node10` deprecation warning remains).
- **#53** (spine wire-format spread bug at `server.ts:145-146`) — **FIXED & VERIFIED** in commit `7a19c83`. The 3 `tsc` errors are gone; Flutter `spine_service.dart` + `viewer_web/index.html` consumers were updated to read `eventPayload`.
- **Phase 1B** (Flutter admin UI consuming the new sensor events, task #42 — `SensorStatusCard` + `BlockedOverlay`) — **NOT STARTED.** Gated on Flutter SDK install. Check `flutter --version`; if missing, install before tackling #42. Root gap: Flutter `RobotStatus.fromJson` still drops the 5 Phase 1A sensor fields.
- **Phase 1.5** (5 more SDK listener integrations — battery, errors, snapshot, head touch, expressions) — **NOT STARTED.** Blocked on resolving the Windows-only orphan-rewriter (task #54).
- **Phase 1.7, Phase 2, Phase 3** — queued.

> **⚠️ 2026-06 reality update (much of the detail below is stale).** The project has moved well past Phase 1B: it now runs against the **real Mikee robot (192.168.10.18)** — joystick drive, head, live MJPEG camera, and battery all work on hardware. **Phase 2 face recognition is in progress:** staff enrollment works end-to-end (browser face-api live detection on the robot feed → `/enroll` → spine `@vladmandic/face-api` → 128-d vector in `staff_face_embedding`, migrations 006=vector(128) + 007=phone/person_type). Enrollment is **staff/employee only** (no customer biometrics — DPDP). **Milestone C DONE (2026-06-16):** L2 threshold calibrated on real faces via nearest-neighbor (leave-one-out) metric — `face-recognition.ts threshold = 0.53` (6 people/28 poses now OVERLAP slightly; 0.53 chosen for precision — reject the closest impostor, occasional "unknown" over a wrong name). Rank-1 100%, but the gap is **thin (~0.014)** — two enrolled people are embedding-close, so Milestone D uses a margin guard + temporal voting (see below), not a bare single-frame threshold. Re-run `calibrate.js` as more staff enroll to widen the gap. **Staff view/edit/delete (DPDP erasure) DONE** (`e16c985`). **Enrollment UX #88 DONE (both parts)** — Part 1: laptop-webcam source in the admin web app (getUserMedia `<video>` + camera-source toggle). Part 2 (`033526b`): **robot_app chest-screen enrollment** — `EnrollScreen` reachable from `StreamScreen`, form-first kiosk flow, REUSES the robot's `/snapshot` (no second camera consumer — CameraStreamPlugin owns camera2), ML Kit `google_mlkit_face_detection` on the frame bytes (head Euler angles for pose gates, never opens the camera), same 5-pose flow + `/check-face` duplicate guard, POSTs each pose to spine `/enroll`. Debug APK builds with ML Kit. Configurable `kCameraBaseUrl`/`kSpineBaseUrl`/`kAuthToken` at the top of `robot_app/lib/enroll_screen.dart`. **Duplicate-face detection DONE** — a `/check-face` endpoint reuses the shared `extractEmbedding` + nearest-neighbor matcher + calibrated threshold; it runs LIVE during enrollment (fired right after the first frontal pose, not after all 5) with a **Stop / Continue-anyway** override. Fails open on error/no-face. **Milestone D — autonomous spine recognizer DONE (2026-06-17):** recognizer wired into `server.ts` (started via the single `broadcastRobotEvent` path, after `sdk.onEvent`); the rot is gone (no more `axios`/`sharp`/dead `detectFacesInFrame`/mock generator); it reuses the SHARED `extractEmbedding` (one face-api pipeline, not a divergent path); grabs frames from the robot **`/snapshot`** endpoint (clean complete JPEG — proven 6/6, sidesteps the MJPEG corrupted-boundary risk entirely); matches by NEAREST enrolled embedding < threshold with a **margin guard + temporal voting** (config `match_margin` 0.06, `vote_window`/`vote_min` 5/3, cadence 1.0s). Emits real `face_detected{staff_id,name,distance}` → `broadcastRobotEvent` → `{type:'event',event:'face_detected',eventPayload}` → Flutter `spine_service.dart` parses `eventPayload.payload` → `faceDetectionProvider` → **live dashboard card** (green match w/ name+L2+time, amber unknown, auto-dismiss 6s) + activity feed; the hardcoded mock `face_detected` rows in `dashboard_screen.dart`/`event_log_screen.dart` were removed. **Proven in spine logs against the real robot** (enrolled→real name at L2 0.46–0.52, unknown→unknown). *Verify-on-origin checklist for the next session: recognizer started in `server.ts`; no `axios`/`sharp` imports; shared `extractEmbedding` (not a 2nd path); margin-guard + voting present in `face-recognition.ts`; real `face_detected` reaches the dashboard card.* **Auth GATED (2026-06-17, `aae75bf`):** the `test-token` + no-JWT-secret bypass that spanned `/enroll`, `/check-face`, `/staff` and the WebSocket is now **fail-CLOSED by default** — active ONLY when `DEV_AUTH_BYPASS=1` AND `NODE_ENV!=='production'` (production forces it off even if the flag is set). Centralized in `authorizeRequest()` (`auth/middleware.ts`); `verifyToken`'s no-secret path also fails closed now. Dev still works behind the flag (`.env` has `DEV_AUTH_BYPASS=1`). Verified by curl (401 everywhere by default; passes with flag; prod rejects). **BUT the app isn't actually production-ready yet — see the Production auth go-live checklist immediately below.** The numbered tasks (#42–#64) and "branch `claude/clever-brown-8kLaJ`" references below are historical — that branch was deleted; work now happens directly on `main`.

> **🔐 Production auth go-live checklist — auth is now JWKS/ES256 verified end-to-end (2026-06-18, `bf03009`+).** STEP 0 finding: the Supabase project signs user tokens with **ES256 (asymmetric)**, not legacy HS256 — so verification was switched to **JWKS via `jose`** (verify against `{SUPABASE_URL}/auth/v1/.well-known/jwks.json`, `aud:'authenticated'` + `iss:{SUPABASE_URL}/auth/v1`). Proven prod-mode (`NODE_ENV=production`): no-token → 401, `test-token` → 401, real ES256 token → 200; WS rejects `test-token`, accepts a real token.
> - ✅ **(1) Real login restored** — `router.dart` `_isLoggedIn()` now checks `currentSession` (no more `return true`). Login screen already does `signInWithPassword`.
> - ✅ **(2) Verification path** — spine verifies ES256 via JWKS; needs **`SUPABASE_URL`** set (it already is, for the supabase client). The legacy HS256 `JWT_SECRET` is gone. The app already sends `currentSession.accessToken` (a real ES256 JWT).
> - ✅ **(3) Bypass gating** — `DEV_AUTH_BYPASS` only works when `=1` AND `NODE_ENV!=='production'`; prod forces it off (verified). For prod deploy: leave `DEV_AUTH_BYPASS` unset + `NODE_ENV=production`.
> - ⬜ **(4) REMAINING: robot_app kiosk credential.** Chest-screen enrollment sends `kKioskDevToken='test-token'` (`robot_app/lib/enroll_screen.dart`), which dies once the bypass is off. Per decision, the kiosk needs a **real Supabase operator account** — sign in a dedicated kiosk user, send its ES256 `access_token` (same JWKS path), refresh it. Not built this pass; TODO is in the file.
>
> **Prod deploy checklist:** set `SUPABASE_URL`, `NODE_ENV=production`, leave `DEV_AUTH_BYPASS` unset → all biometric/PII endpoints + WS require a real Supabase JWT. Only the kiosk (4) still needs its operator credential.

---

## What just shipped

### Since last handoff (commits after `901f3bb`, mostly Flutter UI + the #53 fix)

| Commit | Message | Notes |
|---|---|---|
| `7a19c83` | `feat(spine): implement event handling and update message structure for robot events` | ✅ **The #53 fix.** Destructures `{ type, ...rest }` → `{ event, eventPayload }`; updates `SpineMessage` type; updates Flutter + viewer_web consumers; +2 vitest cases (47→49). |
| `6b5ff75` | `feat(events): rename events route to event-log and update event details` | Flutter |
| `4bc6e56` | `Add MapCanvas and PatrolPanels for route management and waypoint editing` | Flutter — new `patrol_routes` feature |
| `74d0271` | `feat(settings): add new bash commands for project file searching and reading` | tooling |
| `6fcad3d` | `Refactor Gallery and Settings Screens for Improved UI and Functionality` | Flutter |
| `536e375` | `feat: Refactor dashboard and live feed screens with navigation and layout improvements` | Flutter |
| `ec1157b` | `feat(dashboard): refactor header layout and enhance battery card animation` | Flutter |
| `eeff972` | `feat: Update settings and add design verification checklist` | + `DESIGN_VERIFICATION.md` |
| `76dc96a` | `chore: add HANDOFF.md for cross-machine session continuity` | this file |

> Note: the orphan-rewriter hazard (#54) was Windows-only. This session runs in a fresh Linux cloud container — no orphan, commit messages land verbatim.

### Earlier (Windows session, 2026-06-08) — Phase 1A foundation

| Commit | Intended message | Notes |
|---|---|---|
| `a227e91` | `docs: add CLAUDE.md project context for Claude Code` | ✅ Clean |
| `d604c8b` | (was `feat(spine): obstacle awareness + sensor events (Phase 1A)`) | ⚠️ Message auto-rewritten by orphan to `feat: Implement sensor event handling...`. Content intact. |
| `0a369b6` | `chore(spine): add missing @types devDeps to unblock tsc` | ✅ Clean |
| `901f3bb` | `chore(spine): fix unused imports + real.ts placeholder bugs` | ✅ Clean |

**Additional artifacts in the history from the orphan-rewriter:**
- `2c41506 feat: Add project context documentation...` — duplicate of `a227e91`, AI-generated by the orphan.
- `cc8d401 Merge branch 'main'...` — an unrequested merge the orphan injected.

These are noise but harmless — the code state is correct. Optionally clean up under task #54 once the orphan is dead. **Do not try to rewrite published history if these have been pushed to origin.**

### Phase 1A — what was actually built

**Files added:**
- `spine/src/sensors.ts` (~96 lines) — pure `applySensorEvent` + `createSensorPipeline` (broadcast + Supabase log wiring)
- `spine/tests/sensors.test.ts` (~211 lines, 12 tests)
- `robot_app/docs/SENSOR_BRIDGE.md` (~241 lines) — Kotlin `MikeeSensorBridge` + Dart MethodChannel receiver + deploy checklist. **Reference code only, NOT deployed.** Verify against real CSJBot SDK when hardware arrives.

**Files modified:**
- `spine/src/types.ts` — 5 new `RobotStatus` fields: `obstacleState`, `localizationQuality`, `sensorHealth`, `personDetected`, `lastObstacleEventAt`; new `SensorEvent` discriminated union
- `spine/src/robot/interface.ts` — added `onSensorEvent(...)` to the SDK contract
- ~~`spine/src/robot/mock.ts`~~ — *(DELETED 2026-06-26 with the mock SDK)* synthetic emitter (obstacle 8–15s weighted 60/20/12/8, health 30s, lq 45s, person 20s); STOP suppression; `start/stopSensorSim()`; auto-start
- `spine/src/robot/real.ts` — no-op `onSensorEvent` pointing at `SENSOR_BRIDGE.md`
- `spine/src/server.ts` — registers the pipeline: seed status → broadcast `robot_status` → `logEvent`

**Critical gotcha discovered:** STOP state is a module global in `spine/src/commands/interlocks.ts` via `getStoppedState()`, NOT in the SDK. The sensor pipeline accepts an injected `isStopped` predicate defaulting to `getStoppedState` — keeps safety state in one home, stays testable.

---

## Pipeline status

### ✅ Done (8 tracked tasks + Phase 1A code)

- All Mikee LIDAR research tasks (#35–#40)
- Add `@types/ws` + `@types/node` devDeps (#41)
- **#53 — spine wire-format spread bug — FIXED & VERIFIED (commit `7a19c83`).** Both consumers (Flutter `spine_service.dart`, `viewer_web/index.html`) updated to `eventPayload`. tsc clean of those 3 errors; 49/49 vitest.
- Plus the 4 Phase 1A commits above (delivered against #38–#40 in real time, not tracked as discrete tasks)

### ⏳ Remaining (16 tasks)

**🔴 Blocking — investigate first (Windows only):**

- **#54** — Orphan `claude.exe` processes on the Windows machine auto-rewriting commits + injecting pulls. 9 orphans from 2026-06-03 14:19. **Does NOT affect iMac.** Only relevant when working on Windows. Diagnostic command:
  ```powershell
  Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Select ProcessId, ParentProcessId, CreationDate, CommandLine | Format-List
  ```
  Confirm with user before terminating any. Then verify with a test commit + reflog scan.

**🟡 Phase 1B — Flutter UI consumer (the natural next work):**

- **#42** — Flutter admin UI for sensor / obstacle events. Gated on Flutter SDK install. Adds `SensorStatusCard`, `BlockedOverlay`, event log filter chip, toast on blocked transitions, widget tests. Estimated 3–4h. **Root gap:** Flutter `RobotStatus.fromJson` (`app/lib/services/spine/spine_state.dart`) still drops the 5 Phase 1A sensor fields (`obstacleState`, `localizationQuality`, `sensorHealth`, `personDetected`, `lastObstacleEventAt`) — extend the freezed model first, then build the two widgets, then wire into `control_screen.dart`. A detailed VS Code Claude Code prompt was drafted for this in the 2026-06-08 cloud session.
- ~~**#53**~~ — ✅ DONE in `7a19c83` (see "Done" above). Was on the `event` message path, separate from the `robot_status` sensor path — Phase 1B is independent of it.

**🟢 Phase 1.5 — ~10h spine + ~5h Flutter, gated by #54:**

- **#43** Battery + charge telemetry (`OnPowerStatusListener` / `OnChargetStateListener` / `OnChargeFailureListener` / `OnRobotDockStateListener`)
- **#44** Self-check + error info events (`OnWarningCheckSelfListener` / `OnErrorInfoListener` / `OnMotoOverloadListener`)
- **#45** Snapshot API (`OnSnapshotoListener` + `takeSnapshot()` intent)
- **#46** Head touch interaction (`OnHeadTouchListener`)
- **#47** Robot facial expressions (`OnExpressionListener` + `setExpression()`)

**🔵 Phase 1.7 — free to start anytime, no #54 dependency:**

- **#48** Microphone volume monitoring (transient — NOT logged to Supabase)
- **#49** OTA upgrade + shutdown lifecycle
- **#50** Wake word / hotword detection (gated by #46 — touch is one wake source)
- **#51** SDK authentication state visibility

**⚪ Long tail:**

- **#52** SDK API integration roadmap — quarterly review of deferred listeners (elevator, door, MQTT, remote — site-specific)

**🛑 Hardware bring-up epic (#60–#64) — BLOCKED: awaiting physical Mikee robot.** Real camera + real movement against actual hardware. The plumbing is mostly built; this epic is verification + the last-mile native bridges. Cannot be validated without the robot on the desk, so it stays parked, not scheduled.

- **#60** Verify `RealRobotSDK` (`spine/src/robot/real.ts`) end-to-end: set `ROBOT_IP` (the spine always connects to the real robot now), intents → robot WS ports 8081/8082/8083, confirm drive/head/arm/wave actually move the chassis. *(drive/head/camera/battery proven on hardware per the 2026-06 update above; arm/wave still owe a hardware pass.)*
- **#61** Confirm `robot_app` native plugins (`ChassisControlPlugin` / `HeadControlPlugin` / `ArmControlPlugin`) actually call the CSJBot **motor** SDK — right now they're WebSocket command receivers; the real motor bridge is the "(future) native SDK bridge."
- **#62** Swap the **mock camera** (cycling RGB frames, per `README.md:96`) for the real CSJBot camera feed in `CameraStreamPlugin`. MJPEG server + admin-app `MjpegView` already work against the mock; this swaps the source.
- **#63** Wire the native sensor bridge (`robot_app/docs/SENSOR_BRIDGE.md`) into `RealRobotSDK.onSensorEvent` (currently a no-op) so Phase 1A obstacle/health/localization events flow from real hardware.
- **#64** Real-hardware safety pass: STOP interlock + obstacle-blocked behaviour validated with the robot physically moving. Highest-risk item — do last, supervised.

**🟫 Dual-source face enrollment — laptop webcam + robot chest-screen (#88). NEAR-TERM UX rework. Added 2026-06 per user request.**

Problem: current enrollment uses the ROBOT camera (MJPEG) feed but shows the move-closer/turn-left instructions on the LAPTOP browser — the person stands at the robot but the guidance is on a screen they can't see. Disconnect.

Solution — **ONE backend, TWO capture sources** (preserve the single embedding pipeline — both POST the IMAGE to `/enroll`, spine extracts the 128-d):
  - **Web app (laptop): use the laptop's OWN webcam** (`getUserMedia` → `<video>` → face-api), guidance on the laptop screen. Person + screen + camera co-located. Convenient for REMOTE enrollment (employee far from robot). Bonus: webcam avoids the MJPEG/CORS-canvas fragility the robot-feed path fought through. Add a camera-source picker (this device / robot); default to device webcam on laptop.
  - **robot_app (chest screen): build a NEW native enrollment screen** on the robot — robot camera preview + instructions shown ON the chest screen + capture → POST `/enroll`. For enrolling when the employee is physically at the robot. Needs camera preview + on-device face detection (`google_mlkit_face_detection`) in robot_app (Flutter/Android).
  - **Honest nuance (cross-camera domain gap):** recognition runs on the ROBOT camera, but laptop-enrolled embeddings come from a different camera/lighting. face-api embeddings are mostly camera-invariant so it generally works, but robot-camera enrollment gives best accuracy; the thin ~0.014 gap makes cross-camera matches more wobble-prone — multi-pose + margin guard + temporal voting mitigate. Optionally add a `capture_source` ('robot'|'webcam') column to `staff_face_embedding` for later analysis.
  - Effort: medium. Web = small rework (MJPEG→webcam + picker). robot_app = new screen (camera + ML Kit + form + POST).

**🔋 Battery telemetry (#87) — DONE (2026-06-17, `21efd4a`), proven on the real robot.** Robot was reporting a static 85% (hardcoded `BatteryService._currentBattery=85` + one-time `setBattery(85)`). Now wired to the REAL battery end-to-end:
- **#87a fixed** — new native `BatteryPlugin.java` registers the CSJBot SDK `OnRobotStateListener` via `CsjRobot.setOnRobotStateBatteryListener` (the SDK's internal loop reports the robot's real main battery ~every 5s; `OnPowerStatusListener` turned out to be the power BUTTON, not battery). Android `BatteryManager` fallback if the SDK never reports. Forwarded over an EventChannel → Dart `BatteryNotifier` → `BatteryService` (:8090) + UI. Also `real.ts`: the `/battery` poll was `setInterval(60s)` so it served the seed 85 for the first minute — now fetches immediately + every 30s; seed 85→-1 (unknown). Admin: dropped the fake `?? 78` (battery is `int?`, shows real or "—"); removed the mock `battery_low` rows from dashboard + event-log.
- **#87b DONE** — battery indicator added to the robot_app `StreamScreen` app bar.
- **PROVEN:** `:8090/battery` returned a real, CHANGING value from the SDK (22→25→29→32→33% while charging, `source='sdk'`, not 85); spine relayed it; the admin app received `battery:32` in `robot_status`. NOTE: spine reaches the robot via `ROBOT_IP` in `.env` (DHCP — was `192.168.1.17` this session, gitignored).

**Original #87 notes (historical, now resolved):**

- **#87a — Admin app shows INCORRECT battery (bug).** Likely root cause traced:
  - `robot_app/lib/battery_service.dart` serves `_currentBattery` on port **8090**, but it's **hardcoded to 85** and only changes via `setBattery(level)`. **Nothing appears to feed the real CSJBot battery into `setBattery()`** — so the robot reports a static 85% regardless of actual charge. This is almost certainly the wrong value. Fix: in `robot_app` native, subscribe to the CSJBot battery API (`OnPowerStatusListener` / charge listeners — Phase 1.5 #43) and call `BatteryService.setBattery(realLevel)` so 8090 reports real charge.
  - Chain is otherwise fine: `spine/src/robot/real.ts:58` correctly polls `http://<ip>:8090/battery` and updates `status.battery` → broadcast → admin. So spine faithfully relays whatever robot_app reports (the static 85).
  - **Also clean up admin-side fallbacks that mask/fake the value:** `dashboard_screen.dart:205` does `spineState.status?.battery ?? 78` (shows a hardcoded **78** when status is missing), and there's a **mock** `battery_low level: 20%` event hardcoded in the dashboard events list. Remove/replace these so the UI reflects real telemetry only.
- **#87b — Display battery in the robot_app (chest-screen) UI (feature).** The `robot_app` Flutter app runs the battery HTTP server but doesn't show the level on its own screen. Add a battery indicator to the robot_app UI (`robot_app/lib/main.dart`), reading the same real source (`BatteryService` / CSJBot SDK) — so the chest screen shows charge too.
- Effort: small–medium. The real unlock is wiring the actual CSJBot battery level (#43) — until then everything downstream shows the placeholder 85.

**🟦 Reception workflow epic (#70–#71) — "customer arrived → tell the right staff member." #70 DONE; #71 NOT built.**

The reception robot's core job: when a visitor/customer arrives, inform the staff member they're here to see. Two features, do them in this order — notification is the reliable baseline, navigate-and-announce is the premium layer on top.

> **✅ #70 — Host notification on visitor arrival DONE (2026-06-18, `6a65d71`+`cc1071d`).** Spine `POST /visit` (auth fail-closed) → loads host → inserts a `visitor` row FIRST (DPDP: **name + timestamps only, no biometrics**, `purge_after` = 30 days) → `notifyStaff` once → audit `logEvent` + broadcast a `visitor_arrived` event. `services/notify.ts` sends via the host's `notify_channel`. Admin Live Feed has a collapsible **Visitor check-in card** (staff dropdown from `GET /staff` + name field → `POST /visit`) and a dismissible **arrival banner**; arrivals also land in the dashboard activity feed. 4 vitest pass, tsc clean. Proven live (POST /visit → 200, email logged, visitor row + 30d purge, `visitor_arrived` reached the admin app).
> - **`notify_channel` format convention: `prefix:value`** — `slack:U0ABC123`, `whatsapp:+9198…`, `email:john@xboom.in`. Unknown/missing channel → warn + return (visit still logged).
> - **Env (now in `.env.example`):** `SLACK_WEBHOOK_URL` (Slack Incoming Webhook), `INTERAKT_API_KEY` (WhatsApp via Interakt, Basic auth).
> - **Known gaps:** email channel is **log-only** (`TODO: wire SMTP in Phase 3`); WhatsApp/Interakt path is **untested against a live key** (text-message shape may need an approved template); **hosts must have a real `notify_channel` set** before #70 fires for them (today most are NULL — set them in Manage Staff / DB).

- **#70 — Host notification on visitor arrival — ✅ DONE (see callout above).** Original plan retained below for context.
  - **Data model already exists — NO schema change:** `visitor.host_staff_id` (FK→staff) links a visitor to their host; `staff.notify_channel` holds `slack_id` / `whatsapp_phone` / `email` (the comment literally says "for host handoff").
  - **What's missing:** (a) a visitor-intake step that sets `host_staff_id` — either face recognition (Phase 2 recognizer, in progress) identifies a pre-booked visitor, OR a simple "who are you here to see?" check-in UI; (b) a **notification SENDER in spine** — none exists today; `notify_channel` is only *stored* (it appears in `handlers/enroll.ts` as a field, never sent). Build a sender keyed off the channel type (Slack webhook / WhatsApp / email).
  - **Reuse:** `xboom-flow` (separate repo) already sends WhatsApp via Interakt/MyOperator — reuse that for the WhatsApp channel rather than rebuilding.
  - **Can ship without recognition:** start with manual check-in (visitor picks/says the host) → notify. Recognition just automates the "who" later.

- **#71 — Navigate to the employee's desk and announce (Phase 3, large effort, multi-track).** Robot physically drives to the staff member's location and announces the customer.
  - **CRITICAL design rule:** navigate to the staff member's **assigned location/desk (a fixed waypoint)** and announce — do **NOT** "roam and hunt for a moving person by face." Hunting is the unreliable anti-pattern; a notification reaches a wandering person far faster. Model it as "go to John's sales desk = waypoint 5," not "search the building for John."
  - **Dependencies — none exist today:**
    1. **Navigation integration in spine.** There is currently **NO** navigate/goto/waypoint intent — spine only accepts `drive | head | arm | wave | stop | resume | snapshot | get_status` (`spine/src/types.ts`). Must add a `navigate`/`goto` intent + wire `RealRobotSDK` to CSJBot's point-to-point navigation API. This is the biggest missing piece.
    2. **A mapped office** built with the CSJBot mapping tool (the robot needs a floor map). CSJBot *can* navigate (it's a delivery/guidance platform) but uses its high-level nav API + a pre-built map — raw LIDAR is not exposed (see LIDAR research notes).
    3. **Staff → location mapping** ("John = sales zone / waypoint 5"). New small data — add a location/waypoint field to `staff` or a `staff_location` table.
    4. **Arrival announcement** — TTS/voice or chest-screen message.
    5. **Obstacle avoidance / localization** — ties to the Hardware bring-up epic (#63 sensor bridge); the sensor pipeline is scaffolded but not wired to real hardware.
  - **Relationship to #70:** layered on top. #70 (notification) is the dependable baseline that works even when the robot is busy, blocked, or the person isn't at their desk. Build #70 first; #71 is the Phase-3 "escort/announce" premium experience.

**🟪 Voice interaction epic (#80) — voice Q&A / conversational reception. Added to pipeline 2026-06 per user request. NOT built.**

Visitor/staff asks a question out loud → robot answers from the knowledge base, grounded by Claude. Pipeline: **wake word → STT → KB vector search → Claude RAG → TTS.**
  - **Groundwork already exists:** `kb_chunk` table with `embedding vector(1536)` (comment: *"NULL until voice pipeline populates it"*) + IVFFlat cosine index (migration 004) for FAQ/Q&A retrieval; `conversation` table for transcript logging. So the retrieval half of RAG is schema-ready.
  - **What's missing (all of it):**
    1. **KB ingestion** — chunk xboom's FAQ/KB content (Vishal owns KB content), embed each chunk (text-embedding model, 1536-dim to match), populate `kb_chunk.embedding`.
    2. **STT (speech-to-text)** — capture mic audio from the CSJBot SDK and transcribe (Deepgram or similar). Relates to old roadmap #48 (mic volume) + #50 (wake word / hotword — CSJBot exposes a wake-word listener).
    3. **Retrieval + RAG** — embed the question → pgvector cosine search over `kb_chunk` → feed top chunks to **Claude** (`claude-opus-4-8` / latest) as grounding context → generate the answer. Use the latest Claude model; read the claude-api skill before wiring the API.
    4. **TTS (text-to-speech)** — speak the answer through the robot speaker (CSJBot SDK audio out).
    5. **Conversation logging** — write turns to `conversation` (retention-bound, DPDP).
  - **Sequencing:** KB ingestion + retrieval can be built/tested in spine against text input FIRST (no audio), then bolt on STT/TTS/wake-word once the RAG answers are good. Mic/speaker pieces depend on real-hardware audio access (ties to Hardware bring-up).
  - **Effort:** large, multi-part (a Phase-2/3 track of its own).

**🟩 Animated avatar face — full-screen "robot personality" UI (#82). Pairs with #80 voice. Added 2026-06 per user request. NOT built.**

A full-screen animated face on the **robot's chest screen** (`robot_app/`, Flutter on Android 7.1.2) so interacting with Mikee *feels like talking to a being* — **eyes that look/blink + lip-sync to speech.** This is the visible "personality" layer over the voice pipeline.
  - **Where:** `robot_app/` (the chest screen), NOT the admin app. Currently `robot_app` is the MJPEG streamer + control plugins; this adds a foreground avatar UI.
  - **State machine driven by the #80 voice pipeline:**
    - **Idle** — gentle blink + subtle look-around / breathing.
    - **Attentive** — eyes track the detected person (drive gaze from the face-detection bounding-box position when someone is recognized/present).
    - **Listening** — visual cue while STT is capturing (e.g. pulsing).
    - **Thinking** — during KB retrieval + Claude RAG.
    - **Speaking** — **lip-sync** the mouth to the TTS audio.
  - **Lip-sync approach:** start with **amplitude-driven** mouth open/close synced to TTS audio playback (simple, "good enough" and robust). Phoneme/viseme-accurate lip-sync is a later upgrade (needs phoneme timing from the TTS engine).
  - **Tech suggestion:** **Rive** is well-suited — a state-machine-driven interactive character with named inputs (gaze x/y, blink, mouth-open level, state), lightweight enough for the modest chest-screen hardware. Lottie or Flutter `CustomPainter` are alternatives. Keep it GPU-light (Android 7.1.2, modest device).
  - **Dependencies:** the avatar *states* come from #80's pipeline events (listening/thinking/speaking) and from #42/face recognition (who/where the person is). Build the avatar with **mock state inputs first** (a debug toggle to cycle idle→listening→thinking→speaking), then wire it to the real voice/recognition events once #80 lands.
  - **Effort:** medium (animation + state wiring); the heavy lifting is the #80 voice pipeline it visualizes.

**🟪 Robot chest-screen experience redesign — front-of-house app shell (#89). The "proper robot" UX. Added 2026-06-19 per user request. ✅ P1 DONE (`456f867`→`2f21230`) — ambient face shell + dashboard tiles, mock state, hardware-free. P2 (real perception) next.**

Turn `robot_app` from a utility (MJPEG streamer + battery server + control receivers + enrollment) into the robot's **front-of-house personality + interaction shell**. Goal: a chest screen that *behaves like a being* — an ambient face when idle, reacts to people walking by, greets identified staff by name, and on tap opens a feature dashboard driven by tap + (later) voice. **#89 is the CONTAINER**; #82 (the animated face) and #80 (voice) are the engines that plug into it.
  - **Where:** `robot_app/` (chest screen, Flutter on Android 7.1.2). The existing background servers (MJPEG :8080, battery :8090, control WS receivers) **keep running** — this redesigns only the FOREGROUND `main.dart` UI into a stateful shell.
  - **Two screens, one shell (the app-shell redesign — this is the NEW part beyond #82/#80):**
    - **Ambient Face screen (default)** — full-screen animated face (#82). Idle = blink + subtle look-around. Reacts to presence/motion (eyes track a passerby) and to identity (greet a recognized staff member). This is the resting state the robot sits in 99% of the time.
    - **Dashboard screen (on tap/voice)** — tapping the face opens a feature dashboard: the actual features (live status, enrollment, settings, control) as large tap targets + placeholders for future features (voice Q&A, payment, navigate, directory). Idle-timeout returns to the Ambient Face.
  - **State machine (extends #82's, adds the presence/identity/dashboard states):** `ambient-idle` → `attentive` (someone present, eyes track) → `greeting` (staff identified → personalized) → `listening`/`thinking`/`speaking` (voice, #80) → `dashboard` (tapped). Auto-return to `ambient-idle` on timeout.
  - **⚠️ CRITICAL architecture — TWO perception pipelines, do NOT cross them:**
    1. **Gaze / presence = ON-DEVICE, local, fast.** Eyes tracking a passerby needs a *position* (bounding-box), in real time, with no network latency. The spine recognizer does NOT provide this — it emits identity (`face_detected{staff_id,name,distance}`), polls ~1s, and has no box. So the chest screen runs a **lightweight local ML Kit face-detect on the robot `/snapshot`** (same source enroll_screen already uses — REUSE it, do NOT open a 2nd camera; CameraStreamPlugin owns camera2) to drive gaze x/y + "someone is here". CSJBot `personDetected` (boolean, Phase 1A) is a coarser presence fallback.
    2. **Identity / greeting = SPINE, authoritative.** Who the person is comes from the existing Milestone-D recognizer over the WS (`face_detected` event). The chest screen listens for it → triggers the `greeting` state with the name. Keep ONE embedding pipeline (spine) — the on-device ML Kit is for *gaze/presence only*, never identity (would be a divergent recognition path — forbidden, same rule as enrollment).
    - Net: **local detection animates the face (responsive); spine recognition supplies the name (authoritative).** Don't try to recognize on-device, don't try to gaze-track from spine.
  - **DPDP:** strangers/passersby are **anonymous presence only** — drive the eyes, store NOTHING (no frames, no embeddings). Greeting-by-name uses staff identity from the consented enrollment pipeline only. Consistent with no-customer-biometrics.
  - **Tech:** Rive for the face (#82 — state-machine inputs: gaze x/y, blink, mouth-open, state). App shell = a simple state-driven `Stack`/`Navigator` (AmbientFace ↔ Dashboard), NOT heavy routing. GPU-light (Android 7.1.2).
  - **Phasing (build mock-first, exactly like #82):**
    - **P1 — App shell + ambient face (mock inputs). ✅ DONE (`456f867` refactor → `2f21230` feat).** AmbientFace is now `home:` (replaced `_StreamScreen`); tap → Dashboard; 30s idle / back → face. Face = **placeholder CustomPainter** (eyes+brows+mouth) wired to the Rive input contract (state/gazeX/gazeY/blink/mouthOpen/expression) — idle blink (2-6s) + lerped gaze drift; `kDebugMode` button cycles all 7 states. Dashboard = 4 real tiles (Enroll/Status/Manual Control/Settings, all on existing providers) + disabled placeholders. `main.dart` 1313→46 lines, split into 8 files. `dart analyze` clean, robot-flavor debug APK builds. Background servers untouched (control :8081-3 auto-start preserved on the face screen). **⚠️ STILL OWED:** the polished `.riv` face asset (separate Rive-editor design task) — P1 ships the placeholder painter against the contract so the swap is later + trivial. Added dep: `shared_preferences` (Settings persistence; design-specified). **Not yet run on the physical robot** (Android 7.1.2 frame-rate to verify on hardware — APK builds + analyzes clean here).
    - **P2 — Wire real perception.** Local ML Kit `/snapshot` detect → gaze + `attentive`; spine `face_detected` WS → `greeting`-by-name. Needs robot.
    - **P3 — Voice commands** (depends #80): wake/STT → `listening`/`thinking`/`speaking`; voice nav of the dashboard.
    - **P4 — Lip-sync** (depends #80 TTS): amplitude-driven mouth, per #82.
  - **Dependencies:** #82 (the face asset/animation), #80 (voice, for P3/P4), recognition pipeline (DONE — emits `face_detected`), `personDetected` sensor (Phase 1A), battery (already on the chest screen via #87). P1 depends on none of these being *finished* — it's the shell + a placeholder face with mock state.
  - **Effort:** large (it's a full app redesign + the parent of #82/#80). But P1 (shell + mock face) is a self-contained, hardware-free, demo-able chunk — start there.
  - **"Designed properly":** ✅ **design doc DONE** → `robot_app/docs/CHEST_UX_REDESIGN.md` (state machine, two screens, the two-pipeline split, Rive input contract, P1–P4 phasing, P1 acceptance criteria). **Decisions locked (2026-06-19):** face = **full stylized character** (eyes+mouth+brows from the start); Dashboard v1 real tiles = **Enroll Staff + Robot Status + Manual Control + Settings** (all wire to EXISTING `main.dart` providers/`EnrollScreen`), rest are disabled placeholders. **P1 ✅ DONE** (see phasing above). **Next: P2** — wire real perception (local ML Kit `/snapshot` detect → gaze + `attentive`; spine `face_detected` WS → `greeting`-by-name), needs the robot. Also owed: the `.riv` face asset (design task) to swap for the placeholder painter.

**📱 Mobile admin / remote-control app (#90) — phone-first "drive + monitor + get-alerted on the go." Added 2026-06-19. ✅ Part A DONE (`96081ea`, adaptive remote UI); ✅ Part B code-complete (`02c7bbb`/`1283b7b`/`4a292af`, FCM push) — AWAITING Firebase config to fire; iOS push = fast-follow (needs APNs key).**

> **#90 status detail (2026-06-19):**
> - **Part A (adaptive remote UI) — DONE.** `AdaptiveHome` makes the `/` route branch on width: phones (<600px) → new `MobileRemoteScreen` (full-bleed MjpegView, drive joystick + head pad → throttled `drive`/`head` intents, Wave/Reset/Snapshot, always-visible STOP/RESUME, compact status strip, haptics); tablet/web keep the existing `DashboardScreen`. ONE codebase — reuses `spineProvider`/auth/`Joystick`/`MjpegView` (the existing `Joystick` was already a shared widget, no extraction needed). Web build compiles; files analyze clean.
> - **Part B (push) — code-complete, dormant until Firebase config.** Migration `008_device_token.sql` (per-user RLS). Spine `services/push.ts`: FCM HTTP v1 via `google-auth-library`, best-effort (never throws), stale-token pruning; triggers wired for **visitor_arrived** (visit.ts), **battery low ≤20%** + **obstacle blocked** (server.ts). 5 passing push tests. Client `push_service.dart`: token register/upsert on login + foreground banner + tap deep-link; `main()` init is **guarded** so no-config = no-op (Part A unaffected). New deps: `google-auth-library` (spine), `firebase_core`+`firebase_messaging` (app).
> - **⚠️ PREREQS the user must provide for Part B to actually fire:** a Firebase project + `android/app/google-services.json`, a service-account key in spine env (`FCM_SERVICE_ACCOUNT`/`FCM_PROJECT_ID`), and (iOS) an APNs key + `GoogleService-Info.plist`. All gitignored; `.env.example` has placeholders. **Android push UNTESTED end-to-end** (needs the config).
> - **⚠️ Honest blockers / TODOs:**
>   1. ~~The admin `app/` does NOT build for Android/iOS~~ → ✅ **RESOLVED (`de9687f`).** The web-only imports in `live_feed/` (`dart:html`/`dart:ui_web`/`dart:js`) are now behind conditional-import seams (mirroring `mjpeg_view.dart`): `enroll_webcam_view` trio + a new `web_face_api` seam for the face-api `dart:js` calls; enrollment UI is `kIsWeb`-guarded on native (graceful "enroll on web / robot" fallback); dead `face_detection_overlay`/`_test` deleted. **PROVEN with an actual build: `flutter build apk --debug` succeeds (app-debug.apk built)**; web build still succeeds (face-api enrollment unchanged). So the #90 phone remote now builds + runs on a real Android device. (Firebase deps from #90 Part B also don't block the APK build.) iOS not separately built here but uses the same seams.
>   2. **Push targeting** is all-admins (host named in the body) — host-specific targeting needs a `staff`↔`auth.users` link that doesn't exist (TODO in `push.ts`).
>   3. **Once Android builds** (after #1) + Firebase config is added, apply the `com.google.gms.google-services` Gradle plugin and validate the APK.
>   4. **Sensor strip** ships battery/connection/obstacle; richer `SensorStatusCard` (lidar/rgbd/sonar — already on main) is TODO'd into the compact strip.

A mobile experience for the admin: a **remote-control + monitoring** client for a phone — drive Mikee, watch the camera, see status, get pushed when a visitor arrives. NOT the full admin authoring suite (enrollment management, gallery, patrol-map editing, analytics stay on the larger web/tablet screen). Think **"Mikee Remote"**, not "admin console on a small screen."
  - **✅ Architecture decision LOCKED (2026-06-19): Option A — adaptive layouts in the EXISTING `app/`.** NOT a separate app. `app/` already targets iOS+Android+web (pubspec: "Flutter web + iOS + Android"); add responsive breakpoints (`LayoutBuilder`) → phones get a mobile-first remote layout (joystick-first), web/tablet keep the current dashboard. **Shares everything** — `spine_service.dart`, Supabase auth, all Riverpod providers, models, the mobile `MjpegView` path. One codebase, no duplication; push notifications + haptics are the mobile-native layer on top. (Considered + rejected: a separate "Mikee Remote" app + extracted `packages/mikee_core` — unnecessary maintenance overhead for a solo MVP unless the products genuinely diverge. `viewer_mobile/` stays a camera-only viewer.)
  - **Core features (v1 — the "remote"):**
    1. **Login** (Supabase — reuse; gated by the #auth go-live work).
    2. **Live camera** — full-screen MJPEG (mobile `MjpegView` already exists), portrait + landscape.
    3. **Drive joystick** (chassis fwd/back/left/right) — the headline; on-screen touch joystick (mirror the admin Control joystick → spine `drive` intent).
    4. **Head pan/tilt** — touch pad / mini-joystick → `head` intent.
    5. **Arm + wave** — buttons → `arm`/`wave` intents.
    6. **STOP / RESUME** — big, ALWAYS-visible emergency stop (safety-critical) → `stop`/`resume`.
    7. **Robot status** — battery, connection, SDK status, obstacle/sensor state (reuse `SensorStatusCard` from the sensor-UI branch once merged).
    8. **Quick actions** — wave, reset body, snapshot.
  - **Mobile-native value-adds (the reason it's worth a phone app at all):**
    - **Push notifications** — visitor arrived (#70 already emits `visitor_arrived`), battery low, obstacle blocked, intrusion. This is the killer mobile feature: the host gets the arrival alert on their phone. (Needs FCM/APNs wiring + a spine→push bridge or Supabase Edge Function.)
    - **Haptic feedback** on controls; connection indicator + auto-reconnect (spine WS).
  - **Explicitly DEFERRED off mobile v1 (keep on web/tablet):** staff enrollment/CRUD, gallery, patrol-route map editor, Mission Control analytics. Mobile = control + monitor + alerts, not authoring.
  - **Dependencies / reuse:** `spine_service.dart` (WS + intents — done), mobile `MjpegView` (done), `visitorArrivedProvider`/`faceDetectionProvider` (#70/Milestone D — done), auth (gated on #auth go-live). Push notifications are the one genuinely-new infra piece.
  - **Effort:** medium (responsive layouts + push). Push-notification infra is the long pole.
  - **Build order (user, 2026-06-19):** auth go-live was FIRST — ✅ **DONE** (`9ea892b`→`24245fd`, JWKS/ES256, prod-proven). #90's feature 1 (real login) is now delivered by it. Next build = #89-P1 OR #90 (user's pick). NOTE for #90 prod: the mobile app sends `currentSession.accessToken` (real ES256) — works against the hardened spine with no extra wiring.

**🌐 Deployment & config — kill localhost + hardcoded IPs (#91). Added 2026-06-19 per user request. NOT built.**

Goal: stop developing on `localhost`, deploy properly, and get rid of hardcoded robot/spine IPs + ports (`constants.dart defaultRobotIp='192.168.10.23'`/`defaultSpineUrl='ws://localhost:4000'`, `robot_app kSpineBaseUrl`, spine `ROBOT_IP`). These are DHCP-fragile and break every session.
  - **⚠️ The reality that shapes everything (don't hand-wave "just put it on a server"):** the robot serves its camera (:8080), battery (:8090), and control WS (:8081-3) on its **private LAN IP** behind office NAT. **Spine must reach the robot over the LAN** — and you do NOT want to relay MJPEG video through a distant cloud. So this is NOT "move everything to the cloud." It's a **hybrid**: some pieces cloud-host cleanly, spine stays near the robot.
    - **Supabase** — already cloud/managed. ✅ nothing to do.
    - **Admin web app (Flutter web)** — static; cloud-host cleanly (Vercel / Netlify / Firebase Hosting / Cloudflare Pages). Easy win. Gives a stable URL, no localhost.
    - **Spine** — best kept **on-prem** (a small always-on box / NUC on the office network) because it talks to the robot continuously over LAN + relays video locally. Expose it to remote admins via a **stable hostname + TLS** (Cloudflare Tunnel / Tailscale / reverse proxy) — the JWKS/ES256 auth we shipped already protects it. ✅ **DECISION LOCKED (2026-06-19, user): on-prem spine + tunnel.** (Rejected: cloud spine + robot-tunnel — adds video-relay latency/cost + a robot-side tunnel.)
  - **Killing the hardcoded IPs — two sub-problems:**
    1. **Spine endpoint** — replace `ws://localhost:4000` with a **configurable** spine URL: a build-time/env default (prod = a fixed domain like `wss://spine.<domain>`) + the existing `settingsProvider` runtime override. Centralize ports as named constants. Straightforward.
    2. **Robot IP (the DHCP pain)** — pick ONE: (a) **static DHCP reservation** on the office router (simplest, reliable, zero code); (b) **robot self-registers** its current IP with spine on boot/heartbeat (best UX — zero human config; small robot_app + spine change); (c) **mDNS/Bonjour** (`mikee.local`). Recommend (a) now + (b) later for true plug-and-play.
  - **Per-environment config** — introduce a clean config story (dev/staging/prod): Flutter `--dart-define` / env files, spine `.env` per environment, no IPs in source. Document in a `DEPLOYMENT.md`.
  - **Effort:** medium. Web hosting + spine-URL config = quick. Robot self-registration + tunnel = the bigger pieces. **Depends on the spine-hosting decision above.**

**⚙️ CI/CD on GitHub Actions (#92). Added 2026-06-19 per user request. NOT built. INDEPENDENT — can start now.**

Automated test + build (+ deploy) on push/PR. Independent of the #91 hosting decision — the test/build half can start immediately.
  - **Workflows:**
    - **spine** — `npm ci` → `tsc --noEmit` → `npm test` (vitest) on PR + push to main. (The 2 flaky MockRobotSDK timing tests that used to make CI red were removed with the mock SDK on 2026-06-26 — 46/46 deterministic now.)
    - **app (Flutter)** — `flutter pub get` → `flutter analyze` → `flutter test` → `flutter build web`. (Note `flutter analyze` had an environmental crash once — pin the Flutter version in CI to avoid it.)
    - **robot_app (Flutter)** — `flutter analyze` → `flutter build apk --debug` (artifact upload). Requires the committed `google-services.json` (✅ now committed).
  - **Deploy (after #91 decision):** on merge to main → deploy web app to the chosen host; deploy/restart spine (if cloud, e.g. Railway/Render/Fly; if on-prem, a self-hosted runner or a pull-based agent). Supabase migrations: keep MANUAL for now (auto-applying schema from CI is risky) — revisit later.
  - **Secrets:** GitHub Actions secrets for Supabase keys, FCM, hosting tokens. NEVER inline. The service-account key + `.env` stay out of the repo.
  - **Effort:** small–medium for the test/build CI (a few `.github/workflows/*.yml`); deploy automation depends on #91.
  - **Recommended first slice:** a `spine` test workflow + an `app`/`robot_app` analyze+build workflow — pure green-check value, no deploy, no hosting decision needed. Do the flaky-test fix as part of it.
  - **Build order (user, 2026-06-19): DEFERRED — feature work (#82 avatar / #80 voice / #89 P2) comes first; CI/CD picked up after.** The test/build slice is ready to go whenever; it's parked by choice, not blocked.

**🟧 LIDAR / obstacle feature activation (#81) — turn on the obstacle awareness that's already built but unfed. Added 2026-06 per user request.**

Phase 1A built the **entire** obstacle/sensor pipeline (types, `createSensorPipeline`, mock emitter, Flutter `SensorStatusCard` + `BlockedOverlay`) — but on the real robot it is **fed by nothing**, so the UI sits at `obstacleState: 'unknown'` forever. "Activation" = connect the real sensor source to the existing pipeline.
  - **Reality (don't expect raw LIDAR):** CSJBot does **not** expose a raw LIDAR point cloud — only high-level nav events (`NAVI_ROBOT_BLOCKED_NTF`, `WAITSHORT`, `LQ_LOW`, etc.). "LIDAR feature" here = consuming those high-level obstacle/health/localization events, not rendering a point cloud.
  - **What's already done:** spine pipeline is wired (`server.ts:241` registers `sdk.onSensorEvent`); Flutter `SensorStatusCard`/`BlockedOverlay` exist.
  - **What's missing (the 3 breaks in the chain):**
    1. **`RealRobotSDK.onSensorEvent` is a no-op** (`spine/src/robot/real.ts:301`) — must invoke the handler with parsed events.
    2. **`real.ts` doesn't parse obstacle messages** — `handleRobotMessage` only handles `face_detected`/`battery_update`; add parsing for the CSJBot nav/obstacle events.
    3. **The native bridge was never built/deployed** — the Kotlin/Dart in `robot_app/docs/SENSOR_BRIDGE.md` (reference only) must be built into `robot_app` to capture CSJBot SDK events and forward them over the chassis WebSocket to spine.
  - **Same as Hardware bring-up #63.** Requires the physical robot. Once fed, the existing `SensorStatusCard`/`BlockedOverlay` light up with no further UI work. Note the old mock emitter was disabled (`49ee0da`) because its synthetic "blocked" events were tripping the STOP interlock — re-enable carefully / behind a flag if used for dev.

**🟦 Mapping & Navigation foundation (#83) — prerequisite for ALL physical autonomy. Added 2026-06 per user request.**

**Honest framing (important):** on CSJBot you do **NOT** implement SLAM yourself. The robot's firmware runs SLAM/localization internally (it reports `OnPositioningQualityListener` quality; waypoints are `{x, y, heading}` in the robot's own map frame). So this feature = **use the CSJBot mapping mode to build the map, then integrate its navigate-to-point API** — not writing a SLAM/particle-filter algorithm. Don't reinvent what the platform already does.

  - **⚠️ "Uses LIDAR" ≠ "gives raw LIDAR access" — settle this so it isn't re-litigated.** Recurring question: *"if we don't have raw LIDAR, how do we map at all?"* Answer: **we ARE mapping with LIDAR — the firmware's LIDAR does it; we just don't get the raw scans/point cloud.** Two different things. The mapping IS LIDAR-based; it's just LIDAR-consumed *inside the firmware*, where you take the finished map as output. (Mental model: like building on Supabase/Postgres without touching the storage engine — the DB does the hard part, you consume the result.) The layering:
    | Layer | Who runs it | Uses LIDAR? | Exposed to us? |
    |---|---|---|---|
    | Raw LIDAR scans / point cloud | firmware only | ✅ consumes | ❌ **NOT exposed** |
    | SLAM + map building | CSJBot firmware | ✅ | ✅ we *trigger* it, get the saved map |
    | Map + waypoints `{x,y,heading}` + localization quality | SDK | — | ✅ |
    | Navigate-to-point (live obstacle avoidance) | firmware | ✅ live | ✅ we issue `goto` |
    - **What "no raw access" actually costs us — and why we need neither:** (1) writing our OWN SLAM (we don't — firmware does it better); (2) custom raw-LIDAR+CV obstacle fusion (we don't — **event-level fusion** covers it: CSJBot's own fused `BLOCKED`/`WAITSHORT`/`LQ_LOW` events + CV semantics on spine + virtual walls on the map). Everything a reception robot needs — knows the floor, localizes, navigates point-to-point avoiding obstacles — comes from the **map + nav API**, which IS exposed. Raw access only matters if you're rebuilding the robot's brain from scratch, which we are not.
    - **Caveats (unchanged):** mapping *initiation* is **operator-guided** — drive the floor ONCE to build the map (CSJBot almost certainly does NOT expose autonomous "explore unknown building"); after that, localization + navigation are fully autonomous. **Glass walls are invisible to LIDAR** (laser passes through) even to the firmware → they don't get mapped → **mark them as virtual no-go walls** (#84). Glass is the one obstacle where BOTH LIDAR and plain RGB/CV are weak; the sensors that catch glass are ultrasonic (CSJBot fuses some internally) + depth-reflection tricks + manual virtual walls. Do NOT plan to "fall back to LIDAR when CV is unsure about glass" — for glass specifically LIDAR is the WORST sensor, not the fallback.
    - **Sensor fusion happens at the EVENT layer, not the raw-data layer.** CV (spine) = *what/who/why* (semantic); CSJBot high-level obstacle events (Phase 1A pipeline) = *am I physically blocked* (safety, already firmware-fused); virtual walls = known invisible hazards. Combine those three at the app layer. Raw-LIDAR-on-demand fusion is NOT buildable on this SDK — don't start down that path.
    - **If glass collisions ever become a real operational problem** after virtual walls: the only way to get raw range data the SDK won't give is to ADD your own sensor (external ultrasonic array or depth/ToF cam on the Android device) and fuse THAT with CV at the app layer. That's a **hardware modification** (Vishal's domain, real cost) — do NOT build speculatively; only if virtual walls prove insufficient in practice.

  - **What it unlocks (everything physical):** #71 navigate-to-desk, autonomous patrol, auto-return-to-charge, escort/guide. Nothing moves intelligently without it.
  - **Pieces to build:**
    1. **Build maps** with the CSJBot vendor mapping tool (drive the floor once); save named maps.
    2. **`navigate`/`goto` intent in spine** (MISSING today — only drive/head/arm/wave/stop) + wire `RealRobotSDK` to CSJBot's point-to-point nav API; surface nav state via the existing sensor pipeline (`running/blocked/wait`).
    3. **Waypoint & zone management** in the admin app — name points ("reception", "sales desk", "charging dock"). Data model partly ready: `patrol_route.waypoints jsonb [{x,y,heading,dwell_s,narration}]`; Flutter `patrol_routes` feature (`MapCanvas`, `patrol_panels`) is UI scaffolding.
    4. **Map + live robot-position visualization** in admin.
  - **Dependencies:** physical robot + CSJBot mapping tools (Hardware bring-up gated).
  - **"Is it THE most important feature?"** It's the *foundation for an entire category* (all physical autonomy), so critically important — but **not the immediate next step.** Recognition + voice + notification deliver reception value *without* navigation. Build the brain first; #83 unlocks the legs (Phase 3).

---

## Candidate feature backlog (exploration — 2026-06)

A menu to prioritize from. Many are already anticipated in the schema (grounding noted in parens). Not scheduled.

**Physical autonomy (all need #83 mapping):**
- **Autonomous night patrol** — `patrol_route` table built (`active_from`/`active_to`, `narration`, `enabled`); `capture_patrol` kind exists.
- **Auto-return-to-charge / docking** — battery-low → navigate to dock (CSJBot dock/charge listeners; Phase 1.5 #43).
- **Escort / guide visitor to a room**; lead-mode (visitor follows).
- **Multi-floor** — elevator/door integration (CSJBot SDK supports; site-specific).

**Security / monitoring:**
- **Intrusion detection** — after-hours person detection → alert + frame capture (schema ready: `capture_intrusion`, 365-day retention).
- Incident/anomaly capture + alerts.

**Reception / visitor experience:**
- Visitor check-in + host notification (#70); appointment/calendar pre-booking.
- **Greet-by-name** (recognition → personalized greeting); multi-language; touchscreen directory/FAQ on chest screen.
- Visitor badge — QR/print or send-to-phone pass.
- **Telepresence** — visitor ↔ remote staff video call through the robot.

**Conversational (with #80 voice / #82 avatar):**
- Voice Q&A; animated avatar; sentiment/engagement read.

**Admin / analytics:**
- **Mission Control dashboard** (in progress — `MISSION_CONTROL_BUILD.md`).
- Footfall / dwell / peak-time analytics; staff attendance via recognition.
- Health & diagnostics (battery, motor overload, self-check — Phase 1.5 #44).

**Platform / robustness:**
- OTA update + lifecycle (#49); SDK auth visibility (#51); **WebRTC camera upgrade** (lower latency than MJPEG).

---

**🟦 Zone mapping & virtual boundaries (#84) — semantic layer on top of #83. Added 2026-06 per user request.**

User idea: "auto-map the office (showroom vs inside office) with boundaries using CV/OpenCV." **Honest correction recorded so this isn't mis-built:** the geometric/boundary map comes from **CSJBot's built-in SLAM** (depth/LIDAR), NOT from OpenCV on the RGB camera — monocular camera mapping is drift-prone and the wrong tool when the platform already does sensor SLAM. CV adds the **semantic** layer on top:
  - **Operator-tagged zones (reliable, recommended):** on the SLAM map, draw/label zones ("Showroom", "Office") + **virtual boundaries / no-go geofences** ("don't cross into office during business hours"). `patrol_route` table + Flutter `MapCanvas` are scaffolding for this.
  - **CV-assisted labeling (hint only):** during a mapping run, use camera scene/object recognition to *suggest* zone labels. Don't treat auto vision-segmentation as source of truth — unreliable.
  - **ArUco/AprilTag markers (robust CV trick):** printed markers around the office → OpenCV reads them cheaply for solid zone/landmark identification, far more reliable than scene classification.
  - **Depends on #83** (the SLAM map must exist first) + physical robot.

**🟩 Computer Vision suite (#86) — capability menu (formalized from the CV table, 2026-06).** The camera + spine face-api pipeline already exists; these layer on. Continuous/autonomous CV → run on **spine** (reuse frame pipeline); interactive → browser. **DPDP:** presence/object/anomaly detection (no identity) is clean; demographics/emotion/age-gender on visitors is biometric-adjacent — OUT unless Vishal signs off (consistent with no-customer-biometrics).
  - **Face recognition** (in progress) — greet staff/known by name (face-api).
  - **Person detection & counting** — footfall, "someone's here → greet", occupancy (YOLO/COCO-SSD).
  - **Object detection** — unattended bags/packages at reception, products, obstacles (YOLO/COCO).
  - **Approach / wave / gesture** — trigger greeting when someone walks up (MediaPipe pose/hands).
  - **OCR / business-card / ID / QR scan** — visitor self check-in, badge scan (Tesseract / vision API).
  - **ArUco/AprilTag markers** — cheap robust zone/landmark ID for navigation (OpenCV).
  - **Anomaly / activity (after-hours)** — security patrol: motion, fallen person, intruder. Schema ready: `capture_intrusion` (365-day retention).
  - **Product recognition** — showroom "what is this?" Q&A (custom classifier / vision API).
  - **Liveness / anti-spoof** — block photo-of-photo enrollment (face-api + inter-frame motion).
  - **Tools:** face-api.js (faces, have it), YOLO/COCO-SSD (objects/people), MediaPipe (pose/hands/face mesh), OpenCV (markers, motion, contours), Tesseract (OCR), or cloud vision (Google Vision / AWS Rekognition) as alternatives.

**🟨 Payment / checkout (#85) — visitors/customers pay via the Mikee app. Added 2026-06 per user request.**

Reception robot pivots slightly into commerce/kiosk. Doable and well-trodden in India — but it's a real compliance surface, so build it backend-driven and minimize PCI scope.
  - **Recommended approach: UPI QR / hosted checkout via an Indian PSP (Razorpay or Cashfree).** Robot displays a **UPI QR or hosted checkout page** → customer pays on **their own phone** (PhonePe/GPay/Paytm). Card data NEVER touches the robot or our servers → stays **out of PCI-DSS scope**. UPI is the dominant rail in India and ideal for a kiosk (no card-reader hardware needed — just the chest screen).
  - **Architecture (backend-driven — NEVER trust the client to confirm payment):**
    1. Flutter → spine: create order (amount, item, visitor contact for receipt).
    2. Spine → PSP order API (**secret keys on spine ONLY, in env**) → returns order id / QR / hosted URL.
    3. Flutter shows the QR / checkout.
    4. Customer pays on their phone.
    5. PSP → spine **webhook** (`payment.captured`) → spine **verifies the HMAC signature** → marks order paid → pushes status to the app (WS) → success + receipt (email/SMS).
    - **Mark paid ONLY on the verified webhook** — never because the client said so. Webhooks must be idempotent (PSPs retry).
  - **Data model (NEW — none exists today):** `order` (amount, status, items, visitor ref), `payment` (psp_order_id, psp_payment_id, status, amount), optional `product`/`catalog`. Minimal PII; **store NO card data, ever**.
  - **Security / compliance:**
    * Hosted/QR flow keeps card data off our systems (PCI scope minimized).
    * Secrets only on spine; Flutter gets the public key / order id only.
    * Mandatory webhook **signature (HMAC) verification** — reuse the `xboom-flow` webhook-auth discipline (#14–#17: Exotel/MyOperator/Interakt + secret rotation).
    * Idempotency + reconciliation + refund handling; receipts via email/SMS; DPDP-minimal storage.
  - **Scope first:** define WHAT is being sold (showroom products? services? appointments?) — that drives the catalog/order model.
  - **Effort:** medium–large (distinct commerce domain). Avoid card-terminal hardware unless truly required (adds PCI + hardware).

**🟢 Done this session (cloud, branch `claude/clever-brown-8kLaJ`):**

- **Live camera view in the admin app** — new cross-platform `MjpegView` (`app/lib/features/live_feed/widgets/`): native `<img>`/HtmlElementView on web, pure-Dart JPEG frame parser (`mjpeg_parser.dart`, unit-tested) on mobile/desktop. Wired into the Live Feed screen + Control screen feed cards with a start/stop toggle, reading the robot IP from `settingsProvider` → `http://<ip>:8080/stream`. Closes the gap where those panels were static `videocam` icons. Works against the mock camera today; "just works" when #62 swaps in the real feed.
- **Settings ↔ provider fix** — the Settings "Robot IP" field previously wrote only to local widget state, so it never reached the stream URL. Now seeds from and persists to `settingsProvider`. Added `http: ^1.2.0` dep + `robotStreamUrl()` helper in `constants.dart`.

**🌐 Cross-project (xboom-flow, separate repo):**

- **#14–#17** Webhook auth header migration (Exotel / MyOperator / Interakt + 30-day secret rotation)

> **Note on task tracking:** Claude Code's task list is session-local — it does NOT sync across machines or sessions. The numbered tasks (#14–#54) live in the Windows session's task tool. When you (iMac Claude) need to track work, create your own tasks; use the numbers above as cross-reference IDs only.

---

## Critical gotchas

### 1. The #53 wire-format bug — ✅ RESOLVED (commit `7a19c83`)

**Historical, kept for context.** `spine/src/server.ts` used to do `{ type: 'event', event: event.type, ...event }`; the spread clobbered `type` with `RobotEvent`'s own `type`. The fix destructures it cleanly:
```ts
const { type: eventType, ...rest } = event;
const msg: SpineMessage = { type: 'event', event: eventType, eventPayload: rest };
```
`SpineMessage` was updated to `event?: string` + `eventPayload?: Record<string, any>`. Both consumers now read `eventPayload`:
- `app/lib/services/spine/spine_service.dart` — `event` branch reads `msg['event']` + `msg['eventPayload']` (logs only for now; Phase 1B wires to UI).
- `viewer_web/index.html` — `handleSpineMessage` reads `msg.eventPayload`.

No action needed. Don't re-introduce the spread.

### 2. STOP location

When wiring new sensor or intent code: STOP state lives in `spine/src/commands/interlocks.ts` via `getStoppedState()`, NOT in the SDK. Use the injected predicate pattern from `createSensorPipeline` if you need STOP awareness in new code.

### 3. tsc baseline

```bash
cd spine && npx tsc --noEmit
```

Clean of the old #53 wire-format errors (fixed in `7a19c83`). The only remaining output is an unrelated config deprecation: `tsconfig.json(8,25): TS5107 moduleResolution=node10 is deprecated`. **New code should add zero new errors.** Verify before committing.

### 4. Test baseline

```bash
cd spine && npm install && npm test    # fresh containers need install first
```

**49 tests must pass** (was 47; the #53 fix added 2 event-handling cases). Every behavioral change adds a vitest case.

### 5. Real hardware is unavailable

All Phase 1A code runs against `MockRobotSDK`. **Correction to earlier notes:** `RealRobotSDK` (`spine/src/robot/real.ts`) is *not* a no-op — it implements intent→command translation over WS ports 8081/8082/8083 and HTTP snapshot. What's true: it has **never been run against hardware**, `onSensorEvent` is a no-op, and `getStatus` is static. The Kotlin in `SENSOR_BRIDGE.md` is reference code; it has NOT been built or tested. See the Hardware bring-up epic (#60–#64). Don't deploy `robot_app/` against a real Mikee until that epic runs.

### 5b. Camera view needs on-device verification

The new `MjpegView` (this session) was written **without a Flutter SDK in the cloud container — not compiled or `flutter analyze`'d here.** Before relying on it: `cd app && flutter pub get && flutter analyze && flutter test`. The web path uses `dart:html` + `dart:ui_web` (fine for `flutter run -d chrome`; not Wasm builds). The mobile path streams via `package:http`. The `mjpeg_parser.dart` slicer has unit tests (`app/test/mjpeg_parser_test.dart`); the platform rendering needs a real device/browser + a running MJPEG source (mock camera in `robot_app`, or any MJPEG URL). Note: the **Dashboard** mini live-feed card still shows a hardcoded `192.168.1.42` placeholder — not yet wired to `MjpegView` (out of scope this pass).

### 6. Orphan-rewriter (Windows-only)

If you're reading this on Windows, beware: long multi-line `feat:` / `docs:` commit messages get auto-rewritten by the orphan fleet. `chore:` one-liners pass through cleanly. **On iMac you're safe** — no orphan, no rewriter.

### 7. `.claude/settings.json`

Per-machine. Don't commit it. Permission grants will rebuild as you approve commands on the new machine.

---

## Recommended next step

### Next up (2026-06-18) — pick one; Phase 2 recognition + enrollment + #70/#87 are all done

> **Nishant's planned order (2026-06-19):** **(0) Firebase setup first** — provision the Firebase project + `google-services.json`/`GoogleService-Info.plist` + FCM service-account key (`FCM_SERVICE_ACCOUNT`/`FCM_PROJECT_ID` for spine) to light up #90 Part B push (Android + iOS). **THEN tackle #82 (avatar) and #80 (voice).** Both remain in the pipeline (sections above) and are explicitly kept active per user request. The step-by-step Firebase guide was delivered in chat (not yet a repo doc — add `docs/FIREBASE_SETUP.md` if it needs to persist).

The strongest candidates, roughly in priority order:

1. **🔴 Production auth go-live (security).** Highest-value hardening — see the "Production auth go-live checklist" near the top. Re-enable `router.dart:118` login, set `JWT_SECRET`, leave `DEV_AUTH_BYPASS` unset, mint a kiosk credential for `robot_app`. Until then all biometric/PII endpoints + the WS only work via the dev bypass.
2. **🟡 Recognition robustness.** The nearest-neighbour gap is OVERLAPPING at 6 people (threshold dropped to 0.53 for precision). Re-enroll the loose/short captures (rohit + Amit = 4 poses each) sharper/more-frontal, then re-run `scripts/enroll/calibrate.js` and raise the threshold back toward the gap midpoint.
3. **🟦 #71 navigate-to-desk** — the Phase-3 premium layer on #70. BLOCKED on **#83 mapping & navigation foundation** (no `navigate`/`goto` intent exists; needs a CSJBot-built floor map). Big multi-track effort.
4. **#70 polish:** wire a real SMTP email sender (currently log-only), test the WhatsApp/Interakt path against a live key, and set real `notify_channel` values on hosts (most are NULL).
5. **🟪 Voice (#80) / 🟩 avatar (#82)** — larger conversational tracks; KB/`conversation` schema is half-ready.

**Per-session env reminders (DHCP — re-set each session):** `spine/.env ROBOT_IP` and `robot_app kSpineBaseUrl` point at this session's IPs; the robot's adb/IP changes between sessions.

```bash
# Sync + baselines
git pull origin main
cd spine && npm install && npm test     # 46 pass (mock SDK + its flaky timing tests removed 2026-06-26)
npx tsc --noEmit                         # clean
```

### If you're on **Windows** → Path A (recommended)

Resolve **#54** first. Multi-file feature work (Phase 1.5) is unsafe while the orphan can silently rewrite messages. Diagnostic command in the task list above.

After #54 is resolved, Phase 1.5 (#43–#47) is fully runnable.

### Either machine — free wins that don't need #54 or Flutter

- **#48** mic volume monitoring (transient state, no Supabase logging — narrow surface)
- **#49** OTA + shutdown lifecycle (defensive, mock-only changes)
- **#51** SDK auth state (defensive banner)

Each is ~1–2h spine work, single-file diff. Safe to bundle as `chore:` commits.

---

## Cross-machine context

### Memory files (Windows-only, NOT in this repo)

The original Windows session built extended context in personal memory files at `C:\Users\Nishant\.claude\projects\<project-id>\memory\`. Two scopes:

**Git Bash session scope:**
- `mikee-overview.md` — full architectural snapshot
- `mikee-lidar-integration.md` — SDK research (raw LIDAR not exposed; high-level events are)
- `mikee-sdk-roadmap.md` — ~70-listener CSJBot SDK inventory mapped to status
- Plus xboom-flow memos (separate project)

**VS Code Claude Code session scope (also Windows):**
- `mikee-phase1a-sensors.md` — Phase 1A state + gotchas
- `git-history-orphan-rewriter.md` — #54 hazard fully diagnosed

**iMac doesn't have any of these.** This `HANDOFF.md` + `CLAUDE.md` are designed to be sufficient without them. If you (iMac Claude) need deeper context on a specific topic, ask the user to paste the relevant memory file's contents.

### Sync discipline

1. **Always `git push` before switching machines.** Habit: "switching laptops → push first."
2. **Always `git pull` before starting work on the other machine.**
3. **Update this file at end-of-session.** Replace `Last updated`, refresh "What just shipped" + "Pipeline status" + "Recommended next step". Commit as `chore: update session handoff`.

---

## Quick-reference paths

| What | Where |
|---|---|
| Phase 1A spine code | `spine/src/sensors.ts`, `spine/src/types.ts`, `spine/src/server.ts` |
| Phase 1A tests | `spine/tests/sensors.test.ts` |
| Real sensor source (no-op until bridge lands) | `spine/src/robot/real.ts` `onSensorEvent` |
| Native bridge reference (NOT deployed) | `robot_app/docs/SENSOR_BRIDGE.md` |
| Wire-format fix (#53, DONE `7a19c83`) | `spine/src/server.ts` event handler · `app/lib/services/spine/spine_service.dart` · `viewer_web/index.html` |
| Phase 1B target (#42) | `app/lib/services/spine/spine_state.dart` (model) · `app/lib/features/control/widgets/` (new cards) · `control_screen.dart` (wire-in) |
| STOP state | `spine/src/commands/interlocks.ts` |
| Project context | `CLAUDE.md` |
| Status snapshot (older) | `PROJECT_STATUS.md` |
| Flutter app summary | `FLUTTER_APP_SUMMARY.md` |
| Known blocker | `ISSUE_EMAIL_RATE_LIMIT.md` |

---

## Update protocol

This file is a living doc. At end of every cross-machine session, refresh:

1. `Last updated:` line at top
2. "What just shipped" table — add new commits
3. "Pipeline status" — move completed tasks, add new ones, update blockers
4. "Recommended next step" — what should the next session start with
5. Any new critical gotchas
6. **`README.md`** — keep it current whenever architecture, components, status, ports, env vars, or build commands change (standing instruction from Nishant, 2026-06-19). It's the public top-level orientation doc; don't let it drift.

Commit as `chore: update session handoff` and `git push` before switching machines.
