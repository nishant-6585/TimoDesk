/**
 * kb-ingest.ts — KB platform ingestion: raw text or a website URL → chunks →
 * embeddings → kb_chunk rows.
 *
 * This is the server half of the "manage the knowledge base" platform: the
 * admin app (later) and curl (today) POST content here instead of running
 * scripts/kb/ingest.js by hand. Chunking + HTML stripping are pure functions
 * so they're unit-testable without Voyage/Supabase; the ingest orchestrators
 * take an injectable upsert/fetch for the same reason (rag.ts pattern).
 */

import { SupabaseClient } from '@supabase/supabase-js';
import { upsertChunk } from './kb';

/** Target chunk size. Voyage handles far more, but retrieval quality favours
 * focused chunks; ~1200 chars ≈ a few spoken-answer-sized paragraphs. */
export const CHUNK_MAX_CHARS = 1200;

/**
 * Split text into KB-sized chunks on paragraph boundaries. Paragraphs are
 * packed greedily up to [maxChars]; a single oversized paragraph is split on
 * sentence boundaries (and hard-split as a last resort) so no chunk exceeds
 * the cap. Pure — no I/O.
 */
export function chunkText(text: string, maxChars: number = CHUNK_MAX_CHARS): string[] {
  const paragraphs = text
    .split(/\n\s*\n/)
    .map(p => p.replace(/\s+/g, ' ').trim())
    .filter(p => p.length > 0);

  const pieces: string[] = [];
  for (const p of paragraphs) {
    if (p.length <= maxChars) {
      pieces.push(p);
      continue;
    }
    // Oversized paragraph → sentence packing, hard split as last resort.
    let current = '';
    for (const sentence of p.split(/(?<=[.!?])\s+/)) {
      if (sentence.length > maxChars) {
        if (current) pieces.push(current), (current = '');
        for (let i = 0; i < sentence.length; i += maxChars) {
          pieces.push(sentence.slice(i, i + maxChars));
        }
        continue;
      }
      if ((current + ' ' + sentence).trim().length > maxChars) {
        if (current) pieces.push(current);
        current = sentence;
      } else {
        current = (current + ' ' + sentence).trim();
      }
    }
    if (current) pieces.push(current);
  }

  // Greedily merge small neighbouring paragraphs so we don't create a row per line.
  const chunks: string[] = [];
  let current = '';
  for (const piece of pieces) {
    if ((current + '\n\n' + piece).trim().length > maxChars) {
      if (current) chunks.push(current);
      current = piece;
    } else {
      current = current ? current + '\n\n' + piece : piece;
    }
  }
  if (current) chunks.push(current);
  return chunks;
}

/**
 * Very small HTML→text converter for website ingestion. Drops script/style/nav
 * chrome, converts block-level tags to paragraph breaks, strips the rest, and
 * decodes the common entities. Deliberately dependency-free — reception KB
 * pages are simple marketing/FAQ pages, not JS apps (a headless browser is out
 * of scope; JS-rendered sites should be pasted in as text instead).
 */
export function htmlToText(html: string): string {
  let s = html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<noscript[\s\S]*?<\/noscript>/gi, ' ')
    .replace(/<(nav|header|footer|aside)[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ');
  // Block-level closers → paragraph breaks so chunking sees structure.
  s = s.replace(/<\/(p|div|section|article|li|h[1-6]|tr|table|blockquote)>/gi, '\n\n');
  s = s.replace(/<(br|hr)\s*\/?>/gi, '\n');
  s = s.replace(/<[^>]+>/g, ' ');
  s = s
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'");
  // Collapse whitespace but keep paragraph breaks.
  return s
    .split(/\n\s*\n/)
    .map(p => p.replace(/\s+/g, ' ').trim())
    .filter(p => p.length > 0)
    .join('\n\n');
}

export interface IngestDeps {
  upsert?: (
    supabase: SupabaseClient,
    chunk: { topic?: string; content: string; is_faq?: boolean; source?: string; source_id?: string }
  ) => Promise<void>;
  fetchPage?: (url: string) => Promise<string>;
}

export interface IngestResult {
  chunks: number;
}

/**
 * Chunk + embed + store a block of text. Chunks shorter than a few words are
 * skipped (page chrome, stray headings). Returns how many rows were written.
 */
export async function ingestText(
  supabase: SupabaseClient,
  input: { text: string; topic?: string; is_faq?: boolean; source?: string; source_id?: string },
  deps: IngestDeps = {}
): Promise<IngestResult> {
  const upsert = deps.upsert ?? upsertChunk;
  const chunks = chunkText(input.text).filter(c => c.length >= 20);
  for (const content of chunks) {
    await upsert(supabase, {
      topic: input.topic,
      content,
      is_faq: input.is_faq ?? false,
      source: input.source ?? 'manual',
      source_id: input.source_id,
    });
  }
  return { chunks: chunks.length };
}

async function defaultFetchPage(url: string): Promise<string> {
  const resp = await fetch(url, {
    headers: { 'User-Agent': 'MikeeKB/1.0 (+reception knowledge base ingester)' },
    signal: AbortSignal.timeout(15_000),
  });
  if (!resp.ok) throw new Error(`fetch failed: ${resp.status} ${resp.statusText}`);
  const type = resp.headers.get('content-type') ?? '';
  if (!/text\/html|text\/plain/.test(type)) {
    throw new Error(`unsupported content-type "${type}" — paste the content as text instead`);
  }
  return resp.text();
}

/**
 * Fetch a public web page, strip it to text, and ingest it. The page URL is
 * recorded as the chunk `source` so stale content can be found + re-ingested.
 * Only http(s) URLs are allowed.
 */
export async function ingestUrl(
  supabase: SupabaseClient,
  input: { url: string; topic?: string; source_id?: string },
  deps: IngestDeps = {}
): Promise<IngestResult> {
  const parsed = new URL(input.url); // throws on garbage
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error('only http(s) URLs are supported');
  }
  const fetchPage = deps.fetchPage ?? defaultFetchPage;
  const html = await fetchPage(input.url);
  const text = htmlToText(html);
  if (text.length < 40) throw new Error('page produced no usable text (JS-rendered site? paste as text instead)');
  return ingestText(
    supabase,
    { text, topic: input.topic, source: input.url, source_id: input.source_id },
    deps
  );
}
