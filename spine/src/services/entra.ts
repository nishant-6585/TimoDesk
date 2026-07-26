/**
 * entra.ts — Microsoft Entra ID (Azure AD) → staff directory sync.
 *
 * Pulls the org's users from Microsoft Graph (client-credentials flow — an app
 * registration with Application permission `User.Read.All`, admin-consented)
 * and mirrors them into the `staff` table:
 *
 *   • match by staff.entra_id (migration 016); first run adopts existing rows
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
 * Env: ENTRA_TENANT_ID, ENTRA_CLIENT_ID, ENTRA_CLIENT_SECRET.
 * All HTTP goes through an injectable fetch so tests never touch Microsoft.
 */

import { SupabaseClient } from '@supabase/supabase-js';

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
  let url: string | null =
    'https://graph.microsoft.com/v1.0/users' +
    '?$select=id,displayName,jobTitle,mail,mobilePhone,accountEnabled&$top=999';
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

interface StaffRow {
  id: string;
  full_name: string;
  role: string | null;
  phone: string | null;
  notify_channel: string | null;
  active: boolean;
  entra_id: string | null;
}

/** Mirror Graph users into staff. See the module doc for the exact rules. */
export async function syncEntraStaff(
  supabase: SupabaseClient,
  deps: EntraDeps = {}
): Promise<EntraSyncSummary> {
  if (!entraConfigured()) {
    throw new Error('Entra not configured — set ENTRA_TENANT_ID / ENTRA_CLIENT_ID / ENTRA_CLIENT_SECRET');
  }
  const token = await getGraphToken(deps);
  const graphUsers = (await fetchGraphUsers(token, deps)).filter(u => (u.displayName ?? '').trim());

  const { data: staffRows, error } = await supabase
    .from('staff')
    .select('id, full_name, role, phone, notify_channel, active, entra_id');
  if (error) throw new Error(`staff load failed: ${error.message}`);
  const staff = (staffRows ?? []) as StaffRow[];

  const byEntraId = new Map(staff.filter(s => s.entra_id).map(s => [s.entra_id as string, s]));
  const byName = new Map(staff.map(s => [s.full_name.trim().toLowerCase(), s]));

  const summary: EntraSyncSummary = {
    fetched: graphUsers.length,
    created: 0,
    updated: 0,
    adopted: 0,
    deactivated: 0,
  };

  for (const u of graphUsers) {
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
      const { error: insErr } = await supabase
        .from('staff')
        .insert({ ...desired, person_type: 'Employee' });
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
      const { error: updErr } = await supabase.from('staff').update(desired).eq('id', row.id);
      if (updErr) throw new Error(`staff update failed for "${name}": ${updErr.message}`);
      if (adopting) summary.adopted++;
      else summary.updated++;
    }
  }

  // Deactivate synced rows whose Graph account no longer exists.
  const graphIds = new Set(graphUsers.map(u => u.id));
  for (const s of staff) {
    if (s.entra_id && s.active && !graphIds.has(s.entra_id)) {
      const { error: deacErr } = await supabase
        .from('staff')
        .update({ active: false })
        .eq('id', s.id);
      if (deacErr) throw new Error(`staff deactivate failed for "${s.full_name}": ${deacErr.message}`);
      summary.deactivated++;
    }
  }

  return summary;
}
