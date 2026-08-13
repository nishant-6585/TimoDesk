/**
 * entra.ts — Microsoft Entra ID (Azure AD) → staff directory sync.
 *
 * Pulls the org's users from Microsoft Graph (client-credentials flow — an app
 * registration with Application permission `User.Read.All`, admin-consented)
 * and mirrors them into the `staff` table:
 *
 *   • match by staff.entra_id (migration 021); first run adopts existing rows
 *     by case-insensitive full_name so manual enrollments gain an entra_id
 *     instead of duplicating;
 *   • create missing users (person_type 'Employee');
 *   • update name/role/phone; set notify_channel to `email:<mail>` ONLY when
 *     empty (an operator-chosen slack/whatsapp channel is never clobbered);
 *   • active follows Graph accountEnabled, and synced rows whose Graph account
 *     disappeared are deactivated (NOT deleted — face embeddings and DPDP
 *     erasure stay an explicit human action). Manually-created staff
 *     (entra_id NULL) are never deactivated by the sync.
 *
 * On top of the one-shot user mirror, `runEntraSync` orchestrates the full
 * recurring sync (migration 022):
 *
 *   • incremental /users/delta with the deltaLink persisted in
 *     entra_sync_state (410 Gone → transparent full resync);
 *   • directory-photo → face-embedding import (services/entra-photos.ts),
 *     gated on the consent security group (ENTRA_CONSENT_GROUP_ID) — see the
 *     DPDP section of docs/ENTRA_ID_INTEGRATION_PLAN.md;
 *   • offboarding purge: synced staff deactivated for longer than
 *     ENTRA_OFFBOARD_PURGE_DAYS lose their `entra-photo:*` embeddings
 *     automatically (audit-logged). On-robot enrollments are never auto-purged.
 *
 * Env: ENTRA_TENANT_ID, ENTRA_CLIENT_ID, ENTRA_CLIENT_SECRET (+ optional
 * ENTRA_CONSENT_GROUP_ID, ENTRA_PHOTO_CONSENT_MODE, ENTRA_SYNC_INTERVAL_MIN,
 * ENTRA_OFFBOARD_PURGE_DAYS, ENTRA_MIN_FACE_PX, ENTRA_CLIENT_SECRET_EXPIRES).
 * All HTTP goes through an injectable fetch so tests never touch Microsoft.
 */

import { SupabaseClient } from '@supabase/supabase-js';
import { logEvent } from '../supabase/events';
import { syncEntraPhotos, EntraPhotoSummary, EntraPhotoDeps } from './entra-photos';

export interface GraphUser {
  id: string;
  displayName: string | null;
  jobTitle: string | null;
  mail: string | null;
  mobilePhone: string | null;
  accountEnabled: boolean;
}

export interface EntraSyncSummary {
  fetched: number;
  created: number;
  updated: number;
  adopted: number; // existing manual rows that gained an entra_id (name match)
  deactivated: number;
}

export interface EntraDeps {
  fetchImpl?: typeof fetch;
}

const GRAPH_USER_SELECT = 'id,displayName,jobTitle,mail,mobilePhone,accountEnabled';
const GRAPH_BASE = 'https://graph.microsoft.com/v1.0';
const DELTA_STATE_KEY = 'users_delta';

export function entraConfigured(): boolean {
  return !!(
    process.env.ENTRA_TENANT_ID &&
    process.env.ENTRA_CLIENT_ID &&
    process.env.ENTRA_CLIENT_SECRET
  );
}

/** Client-credentials token for Graph (https://graph.microsoft.com/.default). */
export async function getGraphToken(deps: EntraDeps = {}): Promise<string> {
  const f = deps.fetchImpl ?? fetch;
  const tenant = process.env.ENTRA_TENANT_ID;
  const resp = await f(`https://login.microsoftonline.com/${tenant}/oauth2/v2.0/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: process.env.ENTRA_CLIENT_ID ?? '',
      client_secret: process.env.ENTRA_CLIENT_SECRET ?? '',
      scope: 'https://graph.microsoft.com/.default',
      grant_type: 'client_credentials',
    }).toString(),
  });
  if (!resp.ok) {
    const detail = await resp.text().catch(() => '');
    throw new Error(`Entra token request failed: ${resp.status} ${detail}`.trim());
  }
  const data = (await resp.json()) as { access_token?: string };
  if (!data.access_token) throw new Error('Entra token response had no access_token');
  return data.access_token;
}

/** All users, following @odata.nextLink pagination. */
export async function fetchGraphUsers(token: string, deps: EntraDeps = {}): Promise<GraphUser[]> {
  const f = deps.fetchImpl ?? fetch;
  const users: GraphUser[] = [];
  let url: string | null = `${GRAPH_BASE}/users?$select=${GRAPH_USER_SELECT}&$top=999`;
  while (url) {
    const resp: Response = await f(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!resp.ok) {
      const detail = await resp.text().catch(() => '');
      throw new Error(`Graph /users failed: ${resp.status} ${detail}`.trim());
    }
    const page = (await resp.json()) as { value?: GraphUser[]; '@odata.nextLink'?: string };
    users.push(...(page.value ?? []));
    url = page['@odata.nextLink'] ?? null;
  }
  return users;
}

/** One user by Graph id; null when the account no longer exists (404). */
export async function fetchGraphUser(
  token: string,
  id: string,
  deps: EntraDeps = {}
): Promise<GraphUser | null> {
  const f = deps.fetchImpl ?? fetch;
  const resp = await f(`${GRAPH_BASE}/users/${id}?$select=${GRAPH_USER_SELECT}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (resp.status === 404) return null;
  if (!resp.ok) {
    const detail = await resp.text().catch(() => '');
    throw new Error(`Graph /users/${id} failed: ${resp.status} ${detail}`.trim());
  }
  return (await resp.json()) as GraphUser;
}

export interface DeltaChanges {
  changedIds: string[];
  removedIds: string[];
  deltaLink: string;
}

/**
 * Follow a stored deltaLink and collect changed / removed user ids.
 * Returns 'resync' when Graph invalidated the token (410 Gone) — the caller
 * falls back to a full enumeration and mints a fresh deltaLink.
 *
 * Deliberately id-only: delta responses include just the CHANGED properties of
 * an updated user, so we re-fetch each changed user in full rather than trying
 * to merge partial objects into the mirror rules.
 */
export async function fetchDeltaChanges(
  token: string,
  deltaLink: string,
  deps: EntraDeps = {}
): Promise<DeltaChanges | 'resync'> {
  const f = deps.fetchImpl ?? fetch;
  const changedIds: string[] = [];
  const removedIds: string[] = [];
  let url: string | null = deltaLink;
  let nextDeltaLink: string | null = null;
  while (url) {
    const resp: Response = await f(url, { headers: { Authorization: `Bearer ${token}` } });
    if (resp.status === 410) return 'resync';
    if (!resp.ok) {
      const detail = await resp.text().catch(() => '');
      throw new Error(`Graph /users/delta failed: ${resp.status} ${detail}`.trim());
    }
    const page = (await resp.json()) as {
      value?: Array<{ id: string; '@removed'?: unknown }>;
      '@odata.nextLink'?: string;
      '@odata.deltaLink'?: string;
    };
    for (const item of page.value ?? []) {
      if (!item.id) continue;
      if (item['@removed']) removedIds.push(item.id);
      else changedIds.push(item.id);
    }
    nextDeltaLink = page['@odata.deltaLink'] ?? nextDeltaLink;
    url = page['@odata.nextLink'] ?? null;
  }
  if (!nextDeltaLink) throw new Error('Graph /users/delta response had no @odata.deltaLink');
  return { changedIds, removedIds, deltaLink: nextDeltaLink };
}

/**
 * Mint a deltaLink representing "now" WITHOUT enumerating users
 * ($deltaToken=latest). Paired with a full /users fetch so the first sync is
 * one enumeration, not two. Null on failure — the next sync just runs full again.
 */
export async function fetchLatestDeltaLink(
  token: string,
  deps: EntraDeps = {}
): Promise<string | null> {
  const f = deps.fetchImpl ?? fetch;
  try {
    const resp = await f(
      `${GRAPH_BASE}/users/delta?$select=${GRAPH_USER_SELECT}&$deltaToken=latest`,
      { headers: { Authorization: `Bearer ${token}` } }
    );
    if (!resp.ok) return null;
    const page = (await resp.json()) as { '@odata.deltaLink'?: string };
    return page['@odata.deltaLink'] ?? null;
  } catch {
    return null;
  }
}

/**
 * User-object members of the consent security group, transitively (nested
 * groups resolve). The /microsoft.graph.user cast keeps devices and service
 * principals out of the consent set.
 */
export async function fetchGroupMemberIds(
  token: string,
  groupId: string,
  deps: EntraDeps = {}
): Promise<Set<string>> {
  const f = deps.fetchImpl ?? fetch;
  const ids = new Set<string>();
  let url: string | null =
    `${GRAPH_BASE}/groups/${groupId}/transitiveMembers/microsoft.graph.user?$select=id&$top=999`;
  while (url) {
    const resp: Response = await f(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!resp.ok) {
      const detail = await resp.text().catch(() => '');
      throw new Error(`Graph group members failed: ${resp.status} ${detail}`.trim());
    }
    const page = (await resp.json()) as { value?: Array<{ id: string }>; '@odata.nextLink'?: string };
    for (const m of page.value ?? []) if (m.id) ids.add(m.id);
    url = page['@odata.nextLink'] ?? null;
  }
  return ids;
}

interface StaffRow {
  id: string;
  full_name: string;
  role: string | null;
  phone: string | null;
  notify_channel: string | null;
  active: boolean;
  entra_id: string | null;
  entra_deactivated_at?: string | null;
}

interface ApplyOptions {
  /** Full enumeration: deactivate synced rows absent from the Graph result. */
  deactivateMissing: boolean;
  /** Delta: explicit '@removed' user ids to deactivate. */
  removedIds?: string[];
}

/**
 * Mirror Graph users into staff (module-doc rules). Deactivation sets
 * entra_deactivated_at (offboarding purge clock); re-enabling clears it.
 */
export async function applyGraphUsers(
  supabase: SupabaseClient,
  graphUsers: GraphUser[],
  opts: ApplyOptions
): Promise<EntraSyncSummary> {
  const users = graphUsers.filter(u => (u.displayName ?? '').trim());

  const { data: staffRows, error } = await supabase
    .from('staff')
    .select('id, full_name, role, phone, notify_channel, active, entra_id, entra_deactivated_at');
  if (error) throw new Error(`staff load failed: ${error.message}`);
  const staff = (staffRows ?? []) as StaffRow[];

  const byEntraId = new Map(staff.filter(s => s.entra_id).map(s => [s.entra_id as string, s]));
  const byName = new Map(staff.map(s => [s.full_name.trim().toLowerCase(), s]));
  const nowIso = new Date().toISOString();

  const summary: EntraSyncSummary = {
    fetched: users.length,
    created: 0,
    updated: 0,
    adopted: 0,
    deactivated: 0,
  };

  for (const u of users) {
    const name = (u.displayName ?? '').trim();
    let row = byEntraId.get(u.id);
    let adopting = false;
    if (!row) {
      row = byName.get(name.toLowerCase());
      if (row?.entra_id) row = undefined; // name collides with a different synced user
      adopting = !!row;
    }

    const desired = {
      full_name: name,
      role: u.jobTitle ?? row?.role ?? null,
      phone: u.mobilePhone ?? row?.phone ?? null,
      // Respect an operator-set channel; only fill from Graph when empty.
      notify_channel: row?.notify_channel || (u.mail ? `email:${u.mail}` : null),
      active: u.accountEnabled,
      entra_id: u.id,
    };

    if (!row) {
      const { error: insErr } = await supabase.from('staff').insert({
        ...desired,
        person_type: 'Employee',
        entra_synced_at: nowIso,
        entra_deactivated_at: u.accountEnabled ? null : nowIso,
      });
      if (insErr) throw new Error(`staff insert failed for "${name}": ${insErr.message}`);
      summary.created++;
      continue;
    }

    const changed =
      row.full_name !== desired.full_name ||
      row.role !== desired.role ||
      row.phone !== desired.phone ||
      row.notify_channel !== desired.notify_channel ||
      row.active !== desired.active ||
      row.entra_id !== desired.entra_id;
    if (changed) {
      const patch: Record<string, unknown> = { ...desired, entra_synced_at: nowIso };
      // Offboarding clock: starts when Graph disables the account, stops on re-enable.
      if (row.active && !desired.active) patch.entra_deactivated_at = nowIso;
      if (!row.active && desired.active) patch.entra_deactivated_at = null;
      const { error: updErr } = await supabase.from('staff').update(patch).eq('id', row.id);
      if (updErr) throw new Error(`staff update failed for "${name}": ${updErr.message}`);
      if (adopting) summary.adopted++;
      else summary.updated++;
    }
  }

  // Deactivate synced rows: on a full enumeration anyone missing from Graph, on
  // a delta run only the explicit '@removed' ids (absence from a delta page is
  // "unchanged", not "departed").
  const goneIds = opts.deactivateMissing
    ? staff
        .filter(s => s.entra_id && s.active && !users.some(u => u.id === s.entra_id))
        .map(s => s.entra_id as string)
    : (opts.removedIds ?? []);
  for (const gone of goneIds) {
    const s = byEntraId.get(gone);
    if (!s || !s.active) continue;
    const { error: deacErr } = await supabase
      .from('staff')
      .update({ active: false, entra_deactivated_at: nowIso, entra_synced_at: nowIso })
      .eq('id', s.id);
    if (deacErr) throw new Error(`staff deactivate failed for "${s.full_name}": ${deacErr.message}`);
    summary.deactivated++;
  }

  return summary;
}

/**
 * One-shot full user mirror (token + full /users fetch + apply). Kept as the
 * simple entry point; `runEntraSync` is the recurring orchestrator.
 */
export async function syncEntraStaff(
  supabase: SupabaseClient,
  deps: EntraDeps = {}
): Promise<EntraSyncSummary> {
  if (!entraConfigured()) {
    throw new Error('Entra not configured — set ENTRA_TENANT_ID / ENTRA_CLIENT_ID / ENTRA_CLIENT_SECRET');
  }
  const token = await getGraphToken(deps);
  const graphUsers = await fetchGraphUsers(token, deps);
  return applyGraphUsers(supabase, graphUsers, { deactivateMissing: true });
}

// ---------------------------------------------------------------------------
// Sync-state persistence (delta cursor)
// ---------------------------------------------------------------------------

async function readSyncState(supabase: SupabaseClient, key: string): Promise<string | null> {
  const { data, error } = await supabase
    .from('entra_sync_state')
    .select('value')
    .eq('key', key)
    .maybeSingle();
  if (error) {
    // Missing table (migration 022 not applied) must not break the sync — it
    // just stays full-enumeration until the migration lands.
    console.warn(`[Entra] sync-state read failed (falling back to full sync): ${error.message}`);
    return null;
  }
  return (data as { value?: string } | null)?.value ?? null;
}

async function writeSyncState(supabase: SupabaseClient, key: string, value: string): Promise<void> {
  const { error } = await supabase
    .from('entra_sync_state')
    .upsert({ key, value, updated_at: new Date().toISOString() });
  if (error) console.warn(`[Entra] sync-state write failed: ${error.message}`);
}

// ---------------------------------------------------------------------------
// Offboarding purge
// ---------------------------------------------------------------------------

export interface OffboardPurgeSummary {
  staff_purged: number;
  embeddings_deleted: number;
}

/**
 * Delete `entra-photo:*` embeddings of synced staff that have been deactivated
 * for longer than `days` (DPDP storage limitation). Manual (on-robot)
 * enrollments are untouched — full erasure stays the human DELETE /staff/{id}.
 */
export async function purgeOffboardedEmbeddings(
  supabase: SupabaseClient,
  days: number,
  logEventImpl: typeof logEvent = logEvent
): Promise<OffboardPurgeSummary> {
  const summary: OffboardPurgeSummary = { staff_purged: 0, embeddings_deleted: 0 };
  const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;

  const { data: rows, error } = await supabase
    .from('staff')
    .select('id, full_name, active, entra_id, entra_deactivated_at');
  if (error) throw new Error(`staff load failed: ${error.message}`);

  const due = ((rows ?? []) as StaffRow[]).filter(
    s =>
      s.entra_id &&
      !s.active &&
      s.entra_deactivated_at &&
      new Date(s.entra_deactivated_at).getTime() < cutoff
  );

  for (const s of due) {
    const { count } = await supabase
      .from('staff_face_embedding')
      .select('id', { count: 'exact', head: true })
      .eq('staff_id', s.id)
      .like('consent_ref', 'entra-photo:%');
    if (!count) continue; // already purged (or never had a directory-photo embedding)

    const { error: delErr } = await supabase
      .from('staff_face_embedding')
      .delete()
      .eq('staff_id', s.id)
      .like('consent_ref', 'entra-photo:%');
    if (delErr) throw new Error(`offboard purge failed for "${s.full_name}": ${delErr.message}`);

    await supabase
      .from('staff')
      .update({ entra_photo_etag: null, entra_photo_status: 'purged' })
      .eq('id', s.id);

    summary.staff_purged++;
    summary.embeddings_deleted += count;
    await logEventImpl('entra_offboard_purge', {
      staff_id: s.id,
      full_name: s.full_name,
      embeddings_deleted: count,
      deactivated_at: s.entra_deactivated_at,
    });
  }
  return summary;
}

// ---------------------------------------------------------------------------
// Recurring orchestrator + status
// ---------------------------------------------------------------------------

export interface EntraRunDeps extends EntraDeps {
  embedImpl?: EntraPhotoDeps['embedImpl'];
  logEventImpl?: typeof logEvent;
}

export interface EntraRunSummary extends EntraSyncSummary {
  mode: 'full' | 'delta';
  removed: number;
  photos: EntraPhotoSummary | null;
  photos_skipped_reason?: string;
  offboard: OffboardPurgeSummary | null;
}

export function entraSyncIntervalMinutes(): number {
  const n = Number(process.env.ENTRA_SYNC_INTERVAL_MIN ?? '360');
  return Number.isFinite(n) && n >= 0 ? n : 360;
}

/**
 * The full recurring sync: users (delta when a cursor exists) → photos
 * (consent-gated) → offboarding purge → persist the delta cursor.
 */
export async function runEntraSync(
  supabase: SupabaseClient,
  deps: EntraRunDeps = {}
): Promise<EntraRunSummary> {
  if (!entraConfigured()) {
    throw new Error('Entra not configured — set ENTRA_TENANT_ID / ENTRA_CLIENT_ID / ENTRA_CLIENT_SECRET');
  }
  const logEventImpl = deps.logEventImpl ?? logEvent;
  const started = Date.now();
  try {
    const token = await getGraphToken(deps);

    // --- users: delta when we have a cursor, full enumeration otherwise -----
    let mode: 'full' | 'delta' = 'full';
    let userSummary: EntraSyncSummary;
    let removed = 0;
    let newDeltaLink: string | null = null;

    const storedDelta = await readSyncState(supabase, DELTA_STATE_KEY);
    let deltaResult: DeltaChanges | 'resync' | null = null;
    if (storedDelta) {
      deltaResult = await fetchDeltaChanges(token, storedDelta, deps);
    }

    if (deltaResult && deltaResult !== 'resync') {
      mode = 'delta';
      // Delta pages carry only changed properties — re-fetch changed users in
      // full so the mirror rules see complete objects. A 404 mid-fetch means
      // the user vanished between the delta and now → treat as removed.
      const changedUsers: GraphUser[] = [];
      const removedIds = [...deltaResult.removedIds];
      for (const id of deltaResult.changedIds) {
        const u = await fetchGraphUser(token, id, deps);
        if (u) changedUsers.push(u);
        else removedIds.push(id);
      }
      userSummary = await applyGraphUsers(supabase, changedUsers, {
        deactivateMissing: false,
        removedIds,
      });
      removed = removedIds.length;
      newDeltaLink = deltaResult.deltaLink;
    } else {
      // No cursor yet, or Graph said 410 resync — full enumeration + fresh cursor.
      const graphUsers = await fetchGraphUsers(token, deps);
      userSummary = await applyGraphUsers(supabase, graphUsers, { deactivateMissing: true });
      newDeltaLink = await fetchLatestDeltaLink(token, deps);
    }

    // --- photos (consent-gated biometrics) ---------------------------------
    let photos: EntraPhotoSummary | null = null;
    let photosSkippedReason: string | undefined;
    const consentMode = (process.env.ENTRA_PHOTO_CONSENT_MODE ?? 'group').toLowerCase();
    const groupId = process.env.ENTRA_CONSENT_GROUP_ID;
    if (consentMode === 'group' && !groupId) {
      // Fail-closed: no consent mechanism → no biometric processing.
      photosSkippedReason =
        'photo embedding disabled — set ENTRA_CONSENT_GROUP_ID (or ENTRA_PHOTO_CONSENT_MODE=all with a documented lawful basis)';
    } else {
      const consented =
        consentMode === 'group' && groupId
          ? await fetchGroupMemberIds(token, groupId, deps)
          : null; // mode 'all': every synced employee
      photos = await syncEntraPhotos(supabase, token, consented, {
        fetchImpl: deps.fetchImpl,
        embedImpl: deps.embedImpl,
        logEventImpl,
      });
    }

    // --- offboarding purge -------------------------------------------------
    const purgeDays = Number(process.env.ENTRA_OFFBOARD_PURGE_DAYS ?? '30');
    const offboard =
      Number.isFinite(purgeDays) && purgeDays > 0
        ? await purgeOffboardedEmbeddings(supabase, purgeDays, logEventImpl)
        : null;

    if (newDeltaLink) await writeSyncState(supabase, DELTA_STATE_KEY, newDeltaLink);

    const summary: EntraRunSummary = {
      ...userSummary,
      mode,
      removed,
      photos,
      ...(photosSkippedReason ? { photos_skipped_reason: photosSkippedReason } : {}),
      offboard,
    };
    lastRun = {
      at: new Date().toISOString(),
      ok: true,
      duration_ms: Date.now() - started,
      summary,
      error: null,
    };
    return summary;
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    lastRun = {
      at: new Date().toISOString(),
      ok: false,
      duration_ms: Date.now() - started,
      summary: null,
      error: reason,
    };
    throw err;
  }
}

interface LastRun {
  at: string;
  ok: boolean;
  duration_ms: number;
  summary: EntraRunSummary | null;
  error: string | null;
}

let lastRun: LastRun | null = null;
let nextRunAt: string | null = null;

/** Called by the server scheduler so /entra/status can show the next run. */
export function markNextEntraRun(at: Date | null): void {
  nextRunAt = at ? at.toISOString() : null;
}

export interface EntraStatus {
  configured: boolean;
  tenant_set: boolean;
  consent_mode: string;
  consent_group_set: boolean;
  sync_interval_min: number;
  offboard_purge_days: number;
  secret_expires: string | null; // ENTRA_CLIENT_SECRET_EXPIRES (ops-recorded, not from Graph)
  last_run: LastRun | null;
  next_run_at: string | null;
}

export function getEntraStatus(): EntraStatus {
  const purgeDays = Number(process.env.ENTRA_OFFBOARD_PURGE_DAYS ?? '30');
  return {
    configured: entraConfigured(),
    tenant_set: !!process.env.ENTRA_TENANT_ID,
    consent_mode: (process.env.ENTRA_PHOTO_CONSENT_MODE ?? 'group').toLowerCase(),
    consent_group_set: !!process.env.ENTRA_CONSENT_GROUP_ID,
    sync_interval_min: entraSyncIntervalMinutes(),
    offboard_purge_days: Number.isFinite(purgeDays) ? purgeDays : 30,
    secret_expires: process.env.ENTRA_CLIENT_SECRET_EXPIRES ?? null,
    last_run: lastRun,
    next_run_at: nextRunAt,
  };
}
