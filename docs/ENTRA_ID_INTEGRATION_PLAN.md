# Microsoft Entra ID (Azure AD) Integration Plan

> **Customer driver:** MindSprint (Wipro-acquired) wants Mikee to plug into their existing
> Microsoft Active Directory and recognize employees using the photos already stored in the
> directory — no per-employee enrollment session in front of the robot. Beyond face
> recognition, the directory unlocks several other reception features (host notification,
> presence, calendar-aware greeting, auto-offboarding).
>
> **Status:** PLAN — researched 2026-08-13, nothing here is built except the Phase-0
> groundwork that already shipped (see "What already exists").

---

## 1. The right API: Microsoft Graph, app-only

"Active Directory" at a company like MindSprint almost always means **hybrid AD**:
on-premises AD DS synced into **Microsoft Entra ID** (renamed from Azure AD) via Entra
Connect. Employee photos stored in on-prem AD (`thumbnailPhoto`, ≤100 KB) sync into Entra
ID, and Microsoft has been unifying all M365 profile photos (Outlook/Teams) into Entra ID
storage. So one API covers both cloud-native and hybrid customers:

- **Microsoft Graph** (`https://graph.microsoft.com/v1.0`) — the *only* supported API.
  (The old "Azure AD Graph" `graph.windows.net` is retired; never target it.)
- **Auth: OAuth2 client-credentials** ("app-only") — an **app registration** in the
  customer's tenant with **Application permissions**, admin-consented once by their IT.
  No interactive login, works from a headless spine. This is exactly what
  `spine/src/services/entra.ts` already does (`getGraphToken()` → token endpoint
  `login.microsoftonline.com/{tenant}/oauth2/v2.0/token`, scope
  `https://graph.microsoft.com/.default`).

### Endpoints we need

| Purpose | Endpoint | Application permission |
|---|---|---|
| List/read users | `GET /users?$select=…` (already used) | `User.Read.All` |
| **Employee photo** | `GET /users/{id}/photo/$value` (largest) or `GET /users/{id}/photos/648x648/$value` | `User.Read.All` **or** narrower `ProfilePhoto.Read.All` |
| Photo change detection | `GET /users/{id}/photo` → `@odata.mediaEtag` | same |
| Incremental user sync | `GET /users/delta?$select=…` | `User.Read.All` |
| Consent-group membership | `GET /groups/{id}/transitiveMembers` | `GroupMember.Read.All` |
| (Phase 4) presence | `GET /users/{id}/presence` | `Presence.Read.All` |
| (Phase 4) calendar lookup | `GET /users/{id}/calendarView` | `Calendars.Read` (scope with an Exchange application access policy) |

Notes from research:

- Photo sizes: fixed ladder `48…648x648` for mailbox-backed photos; Entra-stored photos can
  be any dimension. **Always request `/photo/$value` first (returns the largest/original),
  fall back to `/photos/648x648/$value`; treat 404 as "no photo"** — plenty of directory
  users have none.
- `ProfilePhoto.Read.All` exists as an application permission and is the least-privilege
  choice for the photo fetch; we already need `User.Read.All` for the user list, which also
  covers photos. Offer MindSprint's IT both options — some security teams prefer granting
  the narrow one plus `User.ReadBasic`-style minimization, most will just consent
  `User.Read.All`.
- `/users/delta` tracks property changes but **photo binaries are not delta-tracked** —
  photo refresh needs its own pass (ETag comparison, cheap HEAD-style metadata GET).
- Throttling: Graph is generous for this volume (thousands of users, one photo each). Sync
  serially or with small concurrency (≤4), honor `Retry-After` on 429.

### App registration handshake with MindSprint IT (Phase 0, mostly paperwork)

1. MindSprint IT creates a **single-tenant app registration** in *their* tenant
   ("xboom Mikee Reception Robot"), adds the Application permissions above, clicks
   **Grant admin consent**, and issues a **client secret** (or certificate — support both;
   secrets expire ≤24 months, so record the expiry and surface it in the admin UI).
2. They hand over: **Tenant ID, Client ID, Client Secret** → spine `.env`
   (`ENTRA_TENANT_ID/CLIENT_ID/CLIENT_SECRET`, already in `.env.example`) → `secrets:push`.
3. They create a **security group** (e.g. `mikee-face-recognition-optin`) and give us its
   Object ID — see §4 Consent. HR adds employees to it as consents are collected.
4. Ask them to confirm **photo coverage**: what % of employees actually have a directory
   photo, and what the photos look like (badge photos are ideal — frontal, neutral).
   This determines how useful Phase 1 is on day one.

*Productization note:* per-customer single-tenant registration is the simplest and the
easiest to get through a Wipro security review (customer owns the app, can revoke it, sees
its sign-in logs). A multi-tenant "xboom app" that customers admin-consent to is the
long-term product play — defer it.

---

## 2. What already exists (don't rebuild)

- `spine/src/services/entra.ts` — client-credentials token + paginated `/users` fetch +
  `syncEntraStaff()`: match by `staff.entra_id` (migration 016), one-time adopt-by-name of
  manual enrollments, create as `person_type 'Employee'`, update name/role/phone, fill
  `notify_channel = email:<mail>` only when empty, `active` follows `accountEnabled`,
  vanished users deactivated (never deleted — DPDP erasure stays a human action).
- `POST /entra/sync` (`spine/src/handlers/entra.ts`, JWT-gated, 503 when unconfigured),
  audit-logged as `entra_sync`. No schedule, no admin UI, **no photos** yet.
- Face pipeline to plug into: `services/face-embedding.ts` `extractEmbedding()` is the one
  shared extractor (exactly-one-face gate, 128-d descriptor); embeddings live in
  `staff_face_embedding` (pgvector 128, `consent_at NOT NULL`, `consent_ref`); recognizer
  (`services/face-recognition.ts`) does per-person nearest-neighbour with threshold 0.53 +
  margin 0.06 + temporal voting, reloading enrolled embeddings every 30 s.

**Gap analysis → the whole feature is: photos → embeddings, consent gating, scheduling,
admin UI, and the Phase-4 extras.**

---

## 3. Phased implementation

### Phase 1 — Photo import → face embeddings (the MindSprint ask)

New `spine/src/services/entra-photos.ts` + extension of `syncEntraStaff()`:

1. After the user upsert loop, for each **consented** (§4) synced staff row:
   - `GET /users/{entra_id}/photo` → compare `@odata.mediaEtag` with new column
     `staff.entra_photo_etag`; skip when unchanged (makes re-syncs cheap).
   - Fetch binary (`/photo/$value`, fallback `/photos/648x648/$value`); 404 → record
     "no photo" and move on.
2. **Quality gates before any embedding is stored** (enrollment quality is already the #1
   recognition problem — HANDOFF 2026-08-12: 12/14 staff have sub-0.53 collisions):
   - decode OK, min face-box size (e.g. ≥120 px — a 96×96 `thumbnailPhoto` should *fail*),
   - `extractEmbedding()` exactly-one-face gate (already enforced),
   - **collision check against existing embeddings** — reuse the `/check-face`
     nearest-neighbour logic; if the new embedding lands within `threshold + margin` of a
     *different* person, flag it (`entra_photo_status = 'collision'`) instead of storing.
3. Store: one `staff_face_embedding` row with `consent_ref = 'entra-photo:<etag>'` and
   `consent_at` from the consent record (§4). Replace-on-change: delete prior
   `entra-photo:*` rows for that staff when the photo changes (manual on-robot poses are
   never touched). Upload the photo as the staff thumbnail (existing private
   `staff-photos` bucket path) only when the staff has none.
4. New columns (migration): `staff.entra_photo_etag text`,
   `staff.entra_photo_status text` (`ok | none | rejected_quality | rejected_multi_face |
   collision`), `staff.entra_synced_at timestamptz`. Extend `EntraSyncSummary` with
   `photos_fetched / embedded / skipped_unchanged / rejected / collisions`.

**Honest expectation to set with the customer:** a directory photo yields **one** frontal
embedding vs. our 5-pose on-robot enrollment, and badge photos can be years old. Rank-1
accuracy will be lower than robot-enrolled staff. The design treats the Entra photo as
*bootstrap* enrollment: everyone with a good photo is recognizable on day one, and the
admin Staff screen shows who would benefit from a 5-pose top-up (they stack — extra
embeddings for the same `staff_id` just improve nearest-neighbour). Run
`scripts/enroll/calibrate.js` after the first big import and re-check the threshold before
declaring accuracy numbers.

*Scale check:* the recognizer's in-memory linear NN over all embeddings is fine into the
low thousands of staff (128 floats each, scanned every 500 ms frame) — no work needed for a
MindSprint-sized office/site; revisit only for a many-thousand multi-site tenant.

### Phase 2 — Scheduling + delta sync + offboarding

- **Scheduled sync** in the spine (plain `setInterval`, default every 6 h,
  `ENTRA_SYNC_INTERVAL_MIN`, 0 = manual only), plus the existing on-demand `POST /entra/sync`.
- **Delta queries**: store the `/users/delta` `deltaLink` (new table `entra_sync_state` or
  a single-row settings table) so recurring syncs only touch changed users. Keep the code
  able to fall back to a full resync when the delta token expires (Graph returns 410
  `resyncRequired`). Photo ETag re-check can ride the same schedule at a lower frequency
  (e.g. daily) since photos aren't delta-tracked.
- **Offboarding**: today a disabled/vanished account only flips `active=false`. Add
  `ENTRA_OFFBOARD_PURGE_DAYS` (default 30): a deactivated *synced* row past the window gets
  its `entra-photo:*` embeddings **deleted** automatically (audit-logged), aligning with
  DPDP storage-limitation. Manual embeddings still require the human `DELETE /staff/{id}`.
  (Also worth noting in the same migration: the nightly `purge_expired_data()` currently
  never touches biometric tables — this closes half that gap for synced staff.)
- Recognizer already reloads embeddings every 30 s — no changes needed for updates to
  propagate.

### Phase 3 — Admin app UI

`app/lib/features/settings` → new **Integrations → Microsoft Entra ID** section
(mirroring the MCP-plugins/KB provider patterns: token write-only, status read back):

- Config state (tenant/client id set? secret set — masked; secret **expiry date** with a
  warning banner), consent-group ID field, sync interval.
- **Sync now** button → `POST /entra/sync`; last-sync summary card (fetched / created /
  photos embedded / rejected / collisions, timestamp, errors).
- Staff list screen: source badge (Entra vs manual — derivable from `entra_id`), photo
  status chip (`no photo` / `rejected` / `collision`) so the front-desk admin knows exactly
  who needs an on-robot top-up enrollment.
- Spine: `GET /entra/status` (configured, last summary, next run) to back the UI.

### Phase 4 — Directory-powered features beyond face recognition (the upsell menu)

Ordered by value-for-effort; each is independent:

1. **Host notification on visitor arrival** (near-free): synced staff already get
   `notify_channel = email:<mail>`; the existing visit/handoff notify path
   (`services/notify.ts`) just works for every employee without manual setup. Add Teams as
   a channel later (`ChannelMessage.Send`/chat via Graph, or an inbound Teams webhook —
   webhook is simpler and permission-free).
2. **Voice-brain directory answers**: mirror job title/department/office into the staff KB
   sync that already runs after enrollment, so "which floor does Priya sit on?" /
   "who heads procurement?" get grounded answers. `$select` extra fields:
   `department, officeLocation, employeeId, userPrincipalName`.
3. **Presence-aware escort/handoff** (`Presence.Read.All`): before walking a visitor to a
   host, check Teams presence — "Rahul is in a meeting; shall I notify him instead?".
4. **Calendar-aware reception** (`Calendars.Read`, scoped by an Exchange application access
   policy to a "robot-visible calendars" group): visitor says their name → find today's
   meeting whose subject/attendees match → "You're here for the 2 pm with Anita — she's
   been notified." This is the flagship demo but the heaviest permission ask.
5. **Entra SSO login for the admin app**: MindSprint admins sign in with their corporate
   account. Supabase Auth supports Azure/Entra as an OIDC provider, so this is
   config-plus-UI, not a new auth path in the spine (JWKS verification is unchanged).
6. **Org-chart lookups** (`/users/{id}/manager`) for the voice brain and for escalation
   chains in notifications.

---

## 4. Consent & DPDP (must be designed in, not bolted on)

Facial embeddings from HR photos are biometric processing of employees. Our current schema
*requires* consent (`consent_at NOT NULL`, enroll handler rejects `consent !== true`) and
the pipeline was built staff-only for DPDP reasons — the Entra path must meet the same bar:

- **Consent is collected by MindSprint (the employer), represented operationally as
  membership in the consent security group** (`ENTRA_CONSENT_GROUP_ID`). Only group
  members get photo embeddings; everyone else still syncs as a directory row (name, role,
  notify channel — non-biometric) with `entra_photo_status = 'no_consent'`.
- `consent_at` = the sync time the membership was first observed; `consent_ref` =
  `entra-group:<groupId>` (+ photo etag on the embedding row). The **contract with
  MindSprint must state** that they collect and retain the underlying written consents and
  keep the group membership accurate — put this in the SOW, Vishal owns the clause.
- **Withdrawal**: removed from the group → next sync deletes that person's
  `entra-photo:*` embeddings (audit-logged `entra_consent_revoked`). Offboarding purge is
  §Phase 2.
- If MindSprint declines the group mechanism, fallback config
  `ENTRA_PHOTO_CONSENT_MODE=all` (their DPO asserts a lawful basis in writing) — default
  stays `group`.

---

## 5. Risks / open questions

| Risk | Mitigation |
|---|---|
| **Photo quality/coverage unknown** — old, tiny (`thumbnailPhoto` 96 px), or missing photos | Phase-0 audit question to IT; hard quality gates; per-staff status chips; on-robot top-up path; calibrate.js audit before quoting accuracy |
| **Recognition accuracy with 1 embedding/person** — current genuine/impostor distributions already overlap at 0.53 | Same as above + collision rejection at import time; consider raising `vote_min` for entra-only staff later if needed |
| MindSprint is **on-prem AD only** (no Entra tenant) | Unlikely inside Wipro/M365, but if so: their IT stands up Entra Connect (their standard playbook), or we build a direct LDAPS connector — explicitly **out of scope** for this plan; confirm in Phase 0 |
| Client **secret expiry** (max 24 mo) silently breaks sync | Expiry stored + surfaced in admin UI; sync failure raises an audit event and admin banner; support certificate auth for longer-lived credentials |
| Wipro security review latency for admin consent | Start the Phase-0 paperwork immediately, in parallel with Phase-1 code (testable against a free dev tenant — see Test plan) |
| Photo changes not delta-tracked | ETag pass on its own (daily) cadence |
| Graph throttling on first import | Serial/low-concurrency fetch, `Retry-After` honored — thousands of photos still finish in minutes |

---

## 6. Test plan

- **Unit (vitest, spine)**: entra.ts already uses an injectable `fetchImpl` — extend the
  same pattern. New suites: photo fetch (etag unchanged / changed / 404 / non-image),
  quality gates (multi-face, small face, collision → correct `entra_photo_status`),
  consent group (member add → embed, remove → delete + audit), delta token happy path +
  410 resync, offboard purge window. Happy path + ≥1 failure mode each, per house rules.
- **Integration**: a free **Microsoft 365 Developer / Entra dev tenant** with ~10 seeded
  users + uploaded photos (some good, one group shot, one tiny, one none) — full sync →
  verify staff rows, embeddings, statuses; then live recognition of a seeded person whose
  dev-tenant photo is a real teammate's face.
- **Hardware bench** (per house rules, before "done"): enroll Nishant via Entra photo only
  → stand in front of the robot → named greeting; then remove from consent group → sync →
  no longer recognized.

## 7. Effort estimate

| Phase | Scope | Est. |
|---|---|---|
| 0 | Paperwork + dev tenant + photo audit | days (mostly waiting on MindSprint IT) |
| 1 | Photo → embedding pipeline + migration + tests | 2–3 sessions |
| 2 | Schedule + delta + offboard purge | 1–2 sessions |
| 3 | Admin UI (settings section + staff badges + status endpoint) | 1–2 sessions |
| 4 | Feature menu — each item independently 1–3 sessions | as sold |

Phases 1+2+3 are the sellable "AD-integrated face recognition" feature; Phase 4 items are
individually demoable upsells.
