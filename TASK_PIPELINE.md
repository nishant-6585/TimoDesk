# Timo — Pending Task Pipeline (execution order)

> Derived from the **Timo Architecture & Delivery Blueprint v1.1** (9 capabilities + DoD)
> mapped against the current TimoDesk codebase state. Serial order for one engineer.
> Last generated: 2026-06-30. Update status as tasks land.
>
> **Legend:** ✅ done · 🟡 partial · 🔴 not started · ⛔ blocked
> **Companion docs:** `HANDOFF.md` (live state), blueprint PDF (the spec), `CLAUDE.md` (rules).

---

## Where we are (one line)

Vision + control half of the MVP (**F2, F3, F6**) works on real hardware. The voice
loop (mic + ASR + TTS) also works — **the mic-wall was resolved** (ElevenLabs
Conversational AI). The remaining voice gap is **grounding** that loop in the xboom
KB so answers follow the blueprint's rules (the T5/T6/T7 RAG is built for this).
V2 (F8, F9) has only a nav foundation.

**MVP completion ≈ 70%.** This pipeline closes the gap.

---

## P0 — Unblock + finish the near-done MVP (do first, mostly parallelizable)

These need no new infra and bank the features that are 85% there.

### T1 · ✅ Audio I/O vendor wall — RESOLVED (2026-06-22)
- **Was:** the CSJBot firmware forwarded empty ASR results (`result:""`) to any
  3rd-party app — even the vendor's own demo got 28/28 empty on this robot. Looked
  like a hard blocker. (memory `robot-mic-vendor-wall`.)
- **Fix:** `CsjRobot.enableFace(true)` before `init()` (`MikeeApplication.java`)
  starts the AIUI/CAE engine **in our process**, so beamformed mic PCM reaches
  `AudioBridgePlugin.onAudio` — bypassing the system-service path. The live voice
  loop is **ElevenLabs Conversational AI** (its ASR + LLM + TTS) via
  `voice_agent.dart` (WS `convai/conversation`). Committed `967e55e`.
- **⚠️ Consequence:** the voice brain is now ElevenLabs' hosted LLM (Claude Haiku +
  a dashboard prompt), **NOT KB-grounded**. The remaining voice work is grounding it
  in the xboom KB — see T8-reframed below, not "unblock the mic".

### T2 · ✅ F7 — Remote photo capture → Supabase Storage → gallery  *(code DONE `65e8753`)*
- **Why:** Blueprint F7 (LOW effort, MVP). Snapshot intent + `capture` table exist;
  verify the full chain to cloud storage + reviewable gallery with attribution.
- **Done:** snapshot handler uploads to the `snapshots` bucket + inserts a `capture`
  row (kind=`admin_snapshot`, `actor`); `GET /captures` (signed URLs); Gallery is now
  two tabs (Snapshots / Staff). Migration 012. `spine/src/captures.ts` (5 tests).
- **⬜ Left:** apply migration 012 + run the loop on the real robot/Supabase.

### T3 · 🟡 F3 — Recognition robustness pass  *(code-half DONE `183e4ee`; bench owed)*
- **Why:** Nearest-neighbour gap is OVERLAPPING at 6 enrolled people (threshold dropped
  to 0.53 for precision; gap ~0.014). Brittle as staff grows.
- **Done (code):** `calibrate.js` now prints a per-person re-enrollment worklist
  (THIN/LOOSE flags + closest impostor pair + precision threshold). Stale comments
  fixed. Consent fields (`consent_at`/`consent_ref`) confirmed written on enrol.
- **⬜ Left (bench, needs robot):** re-enroll the flagged people sharper/frontal →
  re-run `calibrate.js` → raise threshold toward the restored gap midpoint.

### T4 · ✅ F1 (notification half) — Host handoff hardening  *(code DONE)*
- **Why:** #70 ships visitor row + notify, but email is **log-only** and most hosts
  have NULL `notify_channel`. Blueprint requires a working triple-channel handoff.
- **Done:** real email via Resend HTTP API (gated on `RESEND_API_KEY`+`NOTIFY_EMAIL_FROM`,
  log-only fallback); fixed silent send-failure (now throws on non-2xx). 5 tests.
- **⬜ Left (ops):** set real `notify_channel` on hosts; test WhatsApp/Interakt live key.

### T2.5 · ✅ NEW — Capture staff desk/location during enrollment  *(DONE, both apps)*
- **Why:** Groundwork for #71 (navigate-to-desk): record where each staff member sits.
- **Done:** migration 013 (`staff.desk_*`); `/enroll` + `PATCH /staff` accept `desk_pose`;
  `GET /staff` returns it; a "Desk location" capture tile in **both** the admin and robot
  enroll flows (via `getPosition()`). Park robot at desk → Capture → enroll.
- **⬜ Left:** the "go to desk" consumer action (part of #71).

---

## P1 — The voice brain, text-first (blueprint §6 — build now, no mic needed)

> Blueprint rule: *"Build a text-only version first. Prove the brain before the ears."*
> This entire phase is **independent of the T1 mic blocker.**

### T5 · ✅ KB content + ingestion pipeline  *(code DONE)*
- **Why:** F4 needs a knowledge base. `kb_chunk` table exists but embeddings are NULL.
- **Done:** embedding provider = **Voyage voyage-3.5 (1024-dim)**; migration 014
  re-dimensions `kb_chunk.embedding` 1536→1024 + `match_kb_chunk` cosine RPC.
  `services/kb-embedding.ts` (asymmetric query/document), `services/kb.ts`
  (searchKb/upsertChunk/backfillEmbeddings), `scripts/kb/ingest.js` (embed seeded
  rows + import from JSON).
- **⬜ Left:** apply migration 014; **Vishal supplies real KB content**; run `ingest.js`.

### T6 · ✅ F4 — FAQ fast-path  *(code DONE)*
- **Why:** Blueprint F4. Sub-2s cached answers from KB.
- **Done:** `pickFaqAnswer()` — embed query → `match_kb_chunk` → if top hit `is_faq`
  && similarity > 0.85 → return cached content, skip the LLM. `POST /ask` endpoint.
- **⬜ Left:** verify < 1.5s latency on real data.

### T7 · ✅ F5 — Open Q&A Claude fallback (grounded RAG)  *(code DONE)*
- **Why:** Blueprint F5. KB miss → grounded Claude answer.
- **Done:** `services/rag.ts` — on miss, grounded prompt (top-k chunks + spoken-answer
  rules: 2–3 sentences, Indian/British English, no pricing → handoff) → **Claude
  `claude-opus-4-8`** (thinking off + effort low + final-answer-only for voice
  latency). Dependency-injected → unit-tested without hitting the API.
- **⬜ Left:** wire STT/TTS (T8/T9); optional `conversation` logging (PII-scrubbed).

---

## P2 — Ground the voice loop in the KB (mic + TTS already work via ElevenLabs)

> The ears + mouth are DONE (ElevenLabs Conversational AI, `voice_agent.dart`).
> The gap is that ElevenLabs answers with its own generic LLM, not the xboom KB —
> so the remaining work is connecting the T5/T6/T7 grounded brain to the voice loop.

### T8 · 🟡 STT — DONE via ElevenLabs (Indian-English ASR in-platform)
- ElevenLabs does STT server-side; `user_transcript` events already reach the app
  (`voice_agent.dart`), including for on-device voice-commands. No separate STT needed.

### T9 · ✅ TTS — DONE via ElevenLabs (pcm_16000, barge-in, tuned voice)
- ElevenLabs streams `pcm_16000` back → `AudioBridgePlugin` plays it; on-device
  barge-in + Chinese-TTS mute done. Voice tuned server-side (eleven_v3).

### T10 · 🟡 Ground the ElevenLabs agent in the xboom KB — *the real remaining voice task*
- **Why:** ElevenLabs' hosted LLM isn't bound by the blueprint's grounding rules
  (KB-only, no invented pricing/specs). Wire it to the T5/T6/T7 RAG. Three options
  (see the 2026-07-02 research below / HANDOFF): (A) ElevenLabs built-in KB upload,
  (B) **server-tool webhook → spine `/ask`** (reuses our RAG — recommended), (C)
  custom-LLM endpoint on spine. **Decision pending.**
- **Done when:** a spoken question returns a KB-grounded answer; out-of-scope → handoff.

### T11-voice · 🟡 F1 (intake half) — Voice visitor capture
- **Why:** Completes F1's DoD: scripted intake (name → company → host) by voice, entity
  parse, visitor row. The voice loop exists; this is a conversation-design + parse task
  on top of it (or an ElevenLabs tool that POSTs `/visit`). Manual check-in (T4) interim.
- **Done when:** a walk-in gives details by voice, correct visitor record appears in Supabase.

---

## P3 — Hardening, deployment, go-live (blueprint §08/§12)

### T11 · 🔴 Kill hardcoded IPs + per-env config (#91)
- DHCP reservation for the robot MAC; configurable spine URL; on-prem spine + tunnel
  (TLS). Web app to a static host. `DEPLOYMENT.md`.

### T12 · 🔴 CI/CD on GitHub Actions (#92) — *independent, can start anytime*
- spine: `tsc --noEmit` + vitest; app/robot_app: analyze + build. Green-check first,
  deploy automation after T11.

### T13 · 🔴 DPDP go-live checklist (blueprint §08.2)
- Consent screen wording + revocation; documented retention windows + verified nightly
  purge; physical **reception AI notice**; **legal sign-off from Vishal**.

### T14 · 🔴 MVP demo hardening
- End-to-end dry run of the whole-project DoD: greeted by name → details by voice →
  spoken answers → host notified, zero reception staff. Latency + failure-mode pass.

---

## P4 — V2 (gated on autonomous-nav, now partially confirmed)

> Gate Zero's "autonomous navigation = UNKNOWN" is now partially answered — point-to-point
> `goto` + nav-point capture works, which de-risks both V2 features.

### T15 · 🟡 F8 — Office tour guide
- Build floor map (CSJBot mapping tool) → named waypoints → tour route with dwell +
  narration (reuse voice pipeline) → navigate station-to-station. Foundation
  (`nav_points`, `navi`/`cancel_navi`/`get_position`) exists.

### T16 · 🔴 F9 — After-hours patrol + intrusion alarm
- Scheduler activates `patrol_route` after 19:00 → person-detection across 2+ frames →
  siren (SDK) + capture (kind=`intrusion`, 1yr) + fan-out alert (Slack/WhatsApp/email
  + deep link). Degraded "smart stationary sentry" mode if nav insufficient.

---

## Critical path (the spine of the plan)

```
✅ T1 mic wall (resolved) · ✅ T8 STT · ✅ T9 TTS   (ElevenLabs loop, live)
✅ T5 → T6 → T7  (grounded brain, text)  — built, needs KB content + keys applied
                               │
                               ▼
        T10 (ground ElevenLabs in the KB)  → T11-voice (voice intake) → T14 (demo) → T13 (go-live)
        (DECISION PENDING: option A / B / C)

✅ T2 · 🟡 T3 (bench) · ✅ T4 — vision MVP, largely done
T11 (#91 IPs), T12 (#92 CI) — parallel, T12 anytime
T15, T16 (V2) — after MVP
```

**Next unblocked work:** apply migrations 012–014 + set VOYAGE/ANTHROPIC keys →
run `ingest.js` → smoke-test `/ask`. Then T10: pick option A/B/C to ground the voice
loop. Vision-side: T3 bench re-enrollment when at the robot.
