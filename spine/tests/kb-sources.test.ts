/**
 * kb-sources.test.ts — managed KB sources: due-selection logic and the
 * delete-then-reingest refresh (no network, no Supabase — deps injected).
 */
import { describe, it, expect } from 'vitest';
import { SupabaseClient } from '@supabase/supabase-js';
import { isDue, syncSource, KbSource } from '../src/services/kb-sources';

function source(over: Partial<KbSource> = {}): KbSource {
  return {
    id: 'src-1',
    kind: 'url',
    url: 'https://xboom.in/about',
    topic: null,
    max_pages: null,
    auto_sync: true,
    sync_interval_hours: 24,
    last_synced_at: null,
    last_status: null,
    last_error: null,
    chunk_count: 0,
    ...over,
  };
}

describe('isDue', () => {
  const now = new Date('2026-08-13T12:00:00Z');

  it('never-synced + auto_sync → due', () => {
    expect(isDue(source({ last_synced_at: null }), now)).toBe(true);
  });

  it('auto_sync off → never due', () => {
    expect(isDue(source({ auto_sync: false, last_synced_at: null }), now)).toBe(false);
  });

  it('synced within the interval → not due', () => {
    const oneHourAgo = new Date(now.getTime() - 1 * 3600_000).toISOString();
    expect(isDue(source({ sync_interval_hours: 24, last_synced_at: oneHourAgo }), now)).toBe(false);
  });

  it('interval elapsed → due', () => {
    const twoDaysAgo = new Date(now.getTime() - 48 * 3600_000).toISOString();
    expect(isDue(source({ sync_interval_hours: 24, last_synced_at: twoDaysAgo }), now)).toBe(true);
  });
});

/** Minimal chainable fake that records delete/update calls in order. */
function makeFakeSupabase(order: string[]) {
  const updates: Array<Record<string, unknown>> = [];
  const supabase = {
    from(table: string) {
      return {
        delete() {
          return {
            eq(_col: string, _val: string) {
              order.push(`delete:${table}`);
              return Promise.resolve({ error: null });
            },
          };
        },
        update(obj: Record<string, unknown>) {
          return {
            eq(_col: string, _val: string) {
              order.push(`update:${table}`);
              updates.push(obj);
              return Promise.resolve({ error: null });
            },
          };
        },
      };
    },
  } as unknown as SupabaseClient;
  return { supabase, updates };
}

describe('syncSource (url)', () => {
  it('deletes the source chunks BEFORE re-ingesting (dedup) and stamps ok', async () => {
    const order: string[] = [];
    const { supabase, updates } = makeFakeSupabase(order);
    const upserted: Array<{ source_id?: string }> = [];

    const html = `<p>${'xboom builds drones, robots, and marine ROVs across land air and water. '.repeat(3)}</p>`;
    const result = await syncSource(supabase, source(), {
      fetchPage: () => Promise.resolve(html),
      upsert: (_sb, chunk) => {
        order.push('upsert');
        upserted.push(chunk);
        return Promise.resolve();
      },
    });

    // Dedup: the source's old chunks are deleted before any new chunk is written.
    expect(order[0]).toBe('delete:kb_chunk');
    expect(order.indexOf('delete:kb_chunk')).toBeLessThan(order.indexOf('upsert'));
    // Every re-ingested chunk is tagged with the source id (the re-sync key).
    expect(upserted.length).toBeGreaterThan(0);
    expect(upserted.every(c => c.source_id === 'src-1')).toBe(true);
    // Outcome is stamped onto kb_source as a success.
    expect(result.chunks).toBe(upserted.length);
    const stamp = updates.at(-1)!;
    expect(stamp.last_status).toBe('ok');
    expect(stamp.chunk_count).toBe(upserted.length);
  });

  it('records an error stamp (and rethrows) when ingest fails', async () => {
    const order: string[] = [];
    const { supabase, updates } = makeFakeSupabase(order);

    await expect(
      syncSource(supabase, source(), {
        fetchPage: () => Promise.reject(new Error('boom: page unreachable')),
      })
    ).rejects.toThrow(/boom/);

    const stamp = updates.at(-1)!;
    expect(stamp.last_status).toBe('error');
    expect(String(stamp.last_error)).toMatch(/boom/);
  });
});
