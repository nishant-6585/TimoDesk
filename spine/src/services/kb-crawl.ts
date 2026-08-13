/**
 * kb-crawl.ts — same-origin website crawl jobs for the KB platform.
 *
 * POST /kb/crawl starts a background BFS from a seed URL: fetch page → strip
 * to text → ingest (existing pipeline) → follow same-origin links, up to a
 * page cap. Jobs are in-memory (the KB rows they write are durable; a lost
 * job status after a spine restart is fine for an admin-facing progress bar).
 *
 * Link extraction and BFS planning are pure/injectable so tests never fetch.
 */

import { randomUUID } from 'crypto';
import { SupabaseClient } from '@supabase/supabase-js';
import { htmlToText, ingestText, IngestDeps } from './kb-ingest';

export const DEFAULT_MAX_PAGES = 10;
export const HARD_MAX_PAGES = 50;

/** File extensions we never crawl into (binary/asset URLs). */
const SKIP_EXT_RE = /\.(jpe?g|png|gif|webp|svg|ico|css|js|mjs|json|xml|pdf|zip|gz|mp[34]|webm|woff2?|ttf)$/i;

/**
 * Pure: pull same-origin, crawlable page URLs out of an HTML document.
 * Fragments are stripped, duplicates removed, assets and off-site links
 * skipped. Returns absolute URLs.
 */
export function extractLinks(html: string, baseUrl: string): string[] {
  const base = new URL(baseUrl);
  const out = new Set<string>();
  const hrefRe = /<a\s[^>]*href\s*=\s*["']([^"']+)["'][^>]*>/gi;
  let m: RegExpExecArray | null;
  while ((m = hrefRe.exec(html)) !== null) {
    const raw = m[1].trim();
    if (!raw || /^(mailto:|tel:|javascript:|data:)/i.test(raw)) continue;
    let u: URL;
    try {
      u = new URL(raw, base);
    } catch {
      continue;
    }
    if (u.protocol !== 'http:' && u.protocol !== 'https:') continue;
    if (u.origin !== base.origin) continue;
    if (SKIP_EXT_RE.test(u.pathname)) continue;
    u.hash = '';
    out.add(u.toString());
  }
  return [...out];
}

export type CrawlStatus = 'running' | 'done' | 'error';

export interface CrawlJob {
  id: string;
  seed_url: string;
  /** Managed kb_source this crawl belongs to (chunks tagged with it for re-sync). */
  source_id?: string;
  status: CrawlStatus;
  max_pages: number;
  pages_crawled: number;
  chunks: number;
  /** Per-page failures — the crawl continues past them. */
  errors: string[];
  started_at: string;
  finished_at: string | null;
}

export interface CrawlDeps extends IngestDeps {
  /** Injectable for tests — fetch a page's HTML. */
  fetchHtml?: (url: string) => Promise<string>;
  /** Called once the background crawl finishes (used to update kb_source). */
  onFinish?: (result: { chunks: number; ok: boolean }) => void | Promise<void>;
}

/**
 * Crawl a same-origin site and return totals. Shared by the interactive registry
 * (progress reported via [onPage]) and the auto-sync scheduler (awaited
 * directly). Every page's chunks are tagged with [source_id] when given, so a
 * later re-sync deletes-by-source cleanly. Pure BFS; per-page errors are
 * collected, not thrown.
 */
export async function crawlSite(
  supabase: SupabaseClient,
  input: { url: string; max_pages?: number; topic?: string; source_id?: string },
  deps: CrawlDeps = {},
  onPage?: (pages: number, chunks: number) => void
): Promise<{ chunks: number; pages: number; errors: string[] }> {
  const seed = new URL(input.url);
  if (seed.protocol !== 'http:' && seed.protocol !== 'https:') {
    throw new Error('only http(s) URLs are supported');
  }
  const maxPages = Math.min(Math.max(input.max_pages ?? DEFAULT_MAX_PAGES, 1), HARD_MAX_PAGES);
  const fetchHtml = deps.fetchHtml ?? defaultFetchHtml;
  const queue: string[] = [seed.toString()];
  const visited = new Set<string>();
  let chunks = 0;
  let pages = 0;
  const errors: string[] = [];

  while (queue.length > 0 && pages < maxPages) {
    const url = queue.shift()!;
    if (visited.has(url)) continue;
    visited.add(url);
    try {
      const html = await fetchHtml(url);
      const text = htmlToText(html);
      if (text.length >= 40) {
        const result = await ingestText(
          supabase,
          { text, topic: input.topic, source: url, source_id: input.source_id },
          deps
        );
        chunks += result.chunks;
      }
      pages += 1;
      for (const link of extractLinks(html, url)) {
        if (!visited.has(link)) queue.push(link);
      }
    } catch (err) {
      pages += 1; // a failed page still consumes budget — no infinite retries
      errors.push(`${url}: ${err instanceof Error ? err.message : String(err)}`);
    }
    onPage?.(pages, chunks);
  }
  return { chunks, pages, errors };
}

async function defaultFetchHtml(url: string): Promise<string> {
  const resp = await fetch(url, {
    headers: { 'User-Agent': 'MikeeKB/1.0 (+reception knowledge base crawler)' },
    signal: AbortSignal.timeout(15_000),
  });
  if (!resp.ok) throw new Error(`fetch failed: ${resp.status} ${resp.statusText}`);
  const type = resp.headers.get('content-type') ?? '';
  if (!/text\/html/.test(type)) throw new Error(`not an HTML page (${type})`);
  return resp.text();
}

/** In-memory job registry. Newest first in list(). */
export class CrawlJobRegistry {
  private jobs = new Map<string, CrawlJob>();

  list(): CrawlJob[] {
    return [...this.jobs.values()].sort((a, b) => b.started_at.localeCompare(a.started_at));
  }

  get(id: string): CrawlJob | undefined {
    return this.jobs.get(id);
  }

  /**
   * Start a crawl in the background and return the job immediately. BFS,
   * sequential fetches (polite to small marketing sites), per-page errors are
   * recorded but don't kill the job.
   */
  start(
    supabase: SupabaseClient,
    input: { url: string; max_pages?: number; topic?: string; source_id?: string },
    deps: CrawlDeps = {}
  ): CrawlJob {
    const seed = new URL(input.url); // throws on garbage — surfaces as a 400 upstream
    if (seed.protocol !== 'http:' && seed.protocol !== 'https:') {
      throw new Error('only http(s) URLs are supported');
    }
    const maxPages = Math.min(Math.max(input.max_pages ?? DEFAULT_MAX_PAGES, 1), HARD_MAX_PAGES);
    const job: CrawlJob = {
      id: randomUUID(),
      seed_url: seed.toString(),
      source_id: input.source_id,
      status: 'running',
      max_pages: maxPages,
      pages_crawled: 0,
      chunks: 0,
      errors: [],
      started_at: new Date().toISOString(),
      finished_at: null,
    };
    this.jobs.set(job.id, job);

    void this.run(job, supabase, input.topic, deps).catch(async err => {
      job.status = 'error';
      job.errors.push(err instanceof Error ? err.message : String(err));
      job.finished_at = new Date().toISOString();
      await deps.onFinish?.({ chunks: job.chunks, ok: false });
    });
    return job;
  }

  private async run(
    job: CrawlJob,
    supabase: SupabaseClient,
    topic: string | undefined,
    deps: CrawlDeps
  ): Promise<void> {
    const { errors } = await crawlSite(
      supabase,
      { url: job.seed_url, max_pages: job.max_pages, topic, source_id: job.source_id },
      deps,
      (pages, chunks) => {
        job.pages_crawled = pages;
        job.chunks = chunks;
      }
    );
    job.errors.push(...errors);
    job.status = 'done';
    job.finished_at = new Date().toISOString();
    await deps.onFinish?.({ chunks: job.chunks, ok: true });
  }
}

/** Singleton registry used by the HTTP handlers (fresh instances in tests). */
export const crawlJobs = new CrawlJobRegistry();
