/**
 * kb-sources.ts — managed KB content sources (a URL or a website crawl) that can
 * be refreshed on demand or on a schedule.
 *
 * The problem this solves: before this, an ingested URL / crawl was a one-time
 * snapshot with no persistent record, and re-ingesting DUPLICATED chunks. Here
 * every URL/crawl is a `kb_source` row, and a re-sync deletes that source's
 * chunks by `source_id` then re-ingests — the same clean delete-then-reingest
 * pattern kb-staff.ts uses for staff. The scheduler in server.ts calls
 * runDueSyncs() on a cadence; the admin calls syncSource() for "Sync now".
 *
 * All Supabase access is service-role (spine), so RLS stays closed (migration
 * 019). Voyage embedding is rate-limited (free tier ~3 req/min) → syncs run one
 * source at a time and reuse kb-staff's withRetry.
 */

import { SupabaseClient } from '@supabase/supabase-js';
import { ingestUrl, IngestDeps } from './kb-ingest';
import { crawlSite, CrawlDeps } from './kb-crawl';
import { withRetry } from './kb-staff';

export type KbSourceKind = 'url' | 'crawl';

export interface KbSource {
  id: string;
  kind: KbSourceKind;
  url: string;
  topic: string | null;
  max_pages: number | null;
  auto_sync: boolean;
  sync_interval_hours: number;
  last_synced_at: string | null;
  last_status: string | null;
  last_error: string | null;
  chunk_count: number;
}

const SELECT =
  'id, kind, url, topic, max_pages, auto_sync, sync_interval_hours, last_synced_at, last_status, last_error, chunk_count';

/** All managed sources, newest-updated first. */
export async function listSources(supabase: SupabaseClient): Promise<KbSource[]> {
  const { data, error } = await supabase
    .from('kb_source')
    .select(SELECT)
    .order('updated_at', { ascending: false });
  if (error) throw new Error(`kb sources load failed: ${error.message}`);
  return (data ?? []) as KbSource[];
}

/**
 * Record (or return the existing) managed source for a URL/crawl. Idempotent on
 * (kind, url) — adding the same page/site twice reuses the row, so its auto-sync
 * settings + chunks are preserved. Returns the full row.
 */
export async function recordSource(
  supabase: SupabaseClient,
  input: { kind: KbSourceKind; url: string; topic?: string; max_pages?: number }
): Promise<KbSource> {
  const { data, error } = await supabase
    .from('kb_source')
    .upsert(
      {
        kind: input.kind,
        url: input.url,
        topic: input.topic ?? null,
        max_pages: input.max_pages ?? null,
      },
      { onConflict: 'kind,url', ignoreDuplicates: false }
    )
    .select(SELECT)
    .single();
  if (error) throw new Error(`kb source record failed: ${error.message}`);
  return data as KbSource;
}

/** Delete every chunk owned by a source (before a re-sync, or on removal). */
export async function deleteSourceChunks(supabase: SupabaseClient, sourceId: string): Promise<void> {
  const { error } = await supabase.from('kb_chunk').delete().eq('source_id', sourceId);
  if (error) throw new Error(`kb source chunk cleanup failed: ${error.message}`);
}

/** Stamp the outcome of a sync onto the source row. */
async function markSynced(
  supabase: SupabaseClient,
  id: string,
  outcome: { status: string; chunkCount: number; error: string | null }
): Promise<void> {
  await supabase
    .from('kb_source')
    .update({
      last_synced_at: new Date().toISOString(),
      last_status: outcome.status,
      last_error: outcome.error,
      chunk_count: outcome.chunkCount,
    })
    .eq('id', id);
}

/** Public stamp for the async interactive crawl (onFinish) to record its result. */
export async function recordSyncOutcome(
  supabase: SupabaseClient,
  id: string,
  outcome: { chunks: number; ok: boolean; error?: string | null }
): Promise<void> {
  await markSynced(supabase, id, {
    status: outcome.ok ? 'ok' : 'error',
    chunkCount: outcome.chunks,
    error: outcome.error ?? null,
  });
}

/**
 * Refresh ONE source: delete its old chunks, re-ingest (URL fetch or site
 * crawl) tagging chunks with source_id, and stamp the result. Throws on
 * failure (after recording last_status='error') so the caller can log.
 */
export async function syncSource(
  supabase: SupabaseClient,
  source: KbSource,
  deps: CrawlDeps = {}
): Promise<{ chunks: number }> {
  await deleteSourceChunks(supabase, source.id);
  let chunks = 0;
  try {
    if (source.kind === 'url') {
      const ingestDeps: IngestDeps = deps;
      const r = await withRetry(() =>
        ingestUrl(
          supabase,
          { url: source.url, topic: source.topic ?? undefined, source_id: source.id },
          ingestDeps
        )
      );
      chunks = r.chunks;
    } else {
      const r = await crawlSite(
        supabase,
        {
          url: source.url,
          max_pages: source.max_pages ?? undefined,
          topic: source.topic ?? undefined,
          source_id: source.id,
        },
        deps
      );
      chunks = r.chunks;
    }
    await markSynced(supabase, source.id, { status: 'ok', chunkCount: chunks, error: null });
    return { chunks };
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    await markSynced(supabase, source.id, { status: 'error', chunkCount: chunks, error: reason });
    throw err;
  }
}

/**
 * Sources whose auto-sync is on and whose interval has elapsed (never-synced
 * counts as due). Pure-ish: filtered in JS against [now] so it's unit-testable
 * without time-travel SQL.
 */
export async function dueSources(
  supabase: SupabaseClient,
  now: Date = new Date()
): Promise<KbSource[]> {
  const { data, error } = await supabase.from('kb_source').select(SELECT).eq('auto_sync', true);
  if (error) throw new Error(`kb due-sources load failed: ${error.message}`);
  return (data ?? []).filter(s => isDue(s as KbSource, now)) as KbSource[];
}

/** Whether a source is due for re-sync at [now]. Exported for tests. */
export function isDue(s: KbSource, now: Date): boolean {
  if (!s.auto_sync) return false;
  if (!s.last_synced_at) return true;
  const elapsedMs = now.getTime() - new Date(s.last_synced_at).getTime();
  return elapsedMs >= Math.max(1, s.sync_interval_hours) * 3600_000;
}

/** Toggle auto-sync / interval for one source. */
export async function updateSourceSync(
  supabase: SupabaseClient,
  id: string,
  patch: { auto_sync?: boolean; sync_interval_hours?: number }
): Promise<void> {
  const update: Record<string, unknown> = {};
  if (typeof patch.auto_sync === 'boolean') update.auto_sync = patch.auto_sync;
  if (typeof patch.sync_interval_hours === 'number') {
    update.sync_interval_hours = Math.max(1, Math.floor(patch.sync_interval_hours));
  }
  if (Object.keys(update).length === 0) return;
  const { error } = await supabase.from('kb_source').update(update).eq('id', id);
  if (error) throw new Error(`kb source update failed: ${error.message}`);
}

/** Remove a source; its chunks cascade-delete via the FK (migration 019). */
export async function deleteSource(supabase: SupabaseClient, id: string): Promise<number> {
  const { error, count } = await supabase
    .from('kb_source')
    .delete({ count: 'exact' })
    .eq('id', id);
  if (error) throw new Error(`kb source delete failed: ${error.message}`);
  return count ?? 0;
}

/** Fetch one source by id (for "Sync now"). */
export async function getSource(supabase: SupabaseClient, id: string): Promise<KbSource | null> {
  const { data, error } = await supabase.from('kb_source').select(SELECT).eq('id', id).maybeSingle();
  if (error) throw new Error(`kb source fetch failed: ${error.message}`);
  return (data as KbSource | null) ?? null;
}

/**
 * Sync every due source, one at a time (Voyage rate limit). Never throws — a
 * failing source is recorded (last_status='error') and the loop continues.
 * Returns counts for the scheduler to log.
 */
export async function runDueSyncs(
  supabase: SupabaseClient,
  deps: CrawlDeps = {}
): Promise<{ due: number; synced: number; failed: number }> {
  const due = await dueSources(supabase);
  let synced = 0;
  let failed = 0;
  for (const s of due) {
    try {
      await syncSource(supabase, s, deps);
      synced++;
    } catch {
      failed++; // already stamped onto the row by syncSource
    }
  }
  return { due: due.length, synced, failed };
}
