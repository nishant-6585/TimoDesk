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
half (**F1-intake, F4, F5**) is the missing core and is partly blocked by the vendor
mic-firmware wall. V2 (F8, F9) has only a nav foundation.

**MVP completion ≈ 55–60%.** This pipeline closes the gap.

---

## P0 — Unblock + finish the near-done MVP (do first, mostly parallelizable)

These need no new infra and bank the features that are 85% there.

### T1 · ⛔ Resolve the audio I/O vendor wall  — *gates the entire voice layer*
- **Why:** Blueprint Gate Zero "Audio I/O" was only *verbally* confirmed; in practice
  the robot transcribes internally but won't forward mic audio/text to a 3rd-party app
  (see memory `robot-mic-vendor-wall`). This blocks F1 voice intake, F4, F5.
- **Action (not pure code — Vishal/procurement):**
  1. Escalate to Alpha Robotics / CSJBot: get programmatic mic PCM stream OR a
     forward-transcript API in writing (contractual annexure per blueprint §02).
  2. Fallback decision: mount an **external USB mic** on the Android chest device and
     capture via Flutter — bypasses the firmware wall entirely.
- **Done when:** raw mic audio (or a transcript event) reaches our code on the device.
- **Note:** Do **not** let this block T7–T9 (the brain builds text-first without it).

### T2 · 🟡 F7 — Remote photo capture → Supabase Storage → gallery
- **Why:** Blueprint F7 (LOW effort, MVP). Snapshot intent + `capture` table exist;
  verify the full chain to cloud storage + reviewable gallery with attribution.
- **Steps:** confirm `snapshot` intent → SDK capture → upload to Supabase Storage →
  `capture` row (kind=`admin_snapshot`, `taken_by`, `purge_after`) → admin gallery.
- **Done when:** an admin-tapped photo is saved to cloud and viewable later, attributed.

### T3 · 🟡 F3 — Recognition robustness pass
- **Why:** Nearest-neighbour gap is OVERLAPPING at 6 enrolled people (threshold dropped
  to 0.53 for precision; gap ~0.014). Brittle as staff grows.
- **Steps:** re-enroll the loose/short captures (sharper, frontal) → re-run
  `scripts/enroll/calibrate.js` → raise threshold toward the gap midpoint. Confirm
  consent fields (`consent_at`/`consent_ref`) are written on every enrol (DPDP).
- **Done when:** enrolled staff greeted reliably; non-enrolled never falsely matched.

### T4 · 🟡 F1 (notification half) — Host handoff hardening
- **Why:** #70 ships visitor row + notify, but email is **log-only** and most hosts
  have NULL `notify_channel`. Blueprint requires a working triple-channel handoff.
- **Steps:** wire real SMTP sender; test WhatsApp/Interakt against a live key; set real
  `notify_channel` (`slack:` / `whatsapp:` / `email:`) on all hosts.
- **Done when:** a visitor check-in actually reaches the host on all three channels.

---

## P1 — The voice brain, text-first (blueprint §6 — build now, no mic needed)

> Blueprint rule: *"Build a text-only version first. Prove the brain before the ears."*
> This entire phase is **independent of the T1 mic blocker.**

### T5 · 🔴 KB content + ingestion pipeline
- **Why:** F4 needs a knowledge base. `kb_chunk` table exists but embeddings are NULL.
- **Steps:** Vishal supplies curated Q&A/topic content (brand voice) → chunk it →
  embed each chunk (1536-d to match schema) → populate `kb_chunk.embedding`, set
  `is_faq=true` on high-frequency ones. Embed-on-write helper in spine.
- **Done when:** KB chunks are stored with embeddings; a cosine query returns sane hits.

### T6 · 🔴 F4 — FAQ fast-path (retrieval, text in → answer out)
- **Why:** Blueprint F4. Sub-2s cached answers from KB.
- **Steps:** embed query → pgvector cosine search → if `is_faq` && score > 0.85 →
  return cached answer. Text endpoint in spine, no audio yet.
- **Done when:** typed FAQ question returns the right KB answer < 1.5s.

### T7 · 🔴 F5 — Open Q&A Claude fallback (grounded RAG)
- **Why:** Blueprint F5. KB miss → grounded Claude answer.
- **Steps:** on miss → build grounded prompt (top-k KB chunks + company-context block +
  strict rules: 2–3 spoken sentences, Indian/British English, no pricing → route to
  handoff) → call **Claude** (`claude-opus-4-8`, read the `claude-api` skill first) →
  stream answer. Log to `conversation` (PII-scrubbed, retention-bound).
- **Done when:** typed novel question gets a sensible grounded answer; out-of-scope
  routes to handoff. (Greeting already proves TTS-out.)

---

## P2 — Wire the ears + mouth (needs T1 unblocked)

### T8 · ⛔ STT integration  — *blocked by T1*
- **Why:** Blueprint §6. Stream mic → managed STT (Deepgram/Google), wake on face-detect,
  stop on silence (cost control). Evaluate Indian-English accuracy.
- **Done when:** spoken question becomes text feeding T6/T7.

### T9 · 🟡 TTS + latency tuning + fillers
- **Why:** ElevenLabs greeting works; extend to full answers. Add the filler-line trick
  on the Claude-fallback path; stream TTS (start speaking before full synthesis).
- **Done when:** end-to-end voice loop feels conversational (FAQ <1.5s, fallback covered
  by filler).

### T10 · ⛔ F1 (intake half) — Voice visitor capture  — *blocked by T1*
- **Why:** Completes F1's DoD: scripted intake (name → company → host) by voice, entity
  parse, visitor row — **no keyboard**. Manual check-in (T4) is the interim path.
- **Done when:** a walk-in is greeted, gives details by voice, correct visitor record
  appears in Supabase within seconds.

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
T1 (mic unblock) ──────────────┐
                               ▼
T5 → T6 → T7  (brain, text)   T8 → T9 → T10  (voice I/O)  → T14 (demo) → T13 (go-live)
   (no blocker — start now)      (needs T1)

T2, T3, T4 (finish vision MVP) — parallel, start now
T11, T12 (deploy/CI) — parallel, T12 anytime
T15, T16 (V2) — after MVP
```

**Recommended start this session:** T2, T3, T4 (bank the near-done MVP) +
T5/T6 (start the brain text-first) — none are blocked. Escalate T1 to Vishal in parallel.
