/**
 * tests/kb-ingest.test.ts — KB platform ingestion (chunking, HTML→text, and
 * the text/URL orchestrators with injected deps — no Voyage/Supabase/network).
 */

import { describe, it, expect, vi } from 'vitest';
import { chunkText, htmlToText, ingestText, ingestUrl, CHUNK_MAX_CHARS } from '../src/services/kb-ingest';

const supabase = {} as any; // unused when deps are injected

describe('chunkText', () => {
  it('returns one chunk for a short paragraph', () => {
    expect(chunkText('xboom builds land, air and water robots.')).toEqual([
      'xboom builds land, air and water robots.',
    ]);
  });

  it('merges small paragraphs into one chunk up to the cap', () => {
    const text = 'Para one.\n\nPara two.\n\nPara three.';
    expect(chunkText(text)).toEqual(['Para one.\n\nPara two.\n\nPara three.']);
  });

  it('splits when the cap is exceeded and never emits an oversized chunk', () => {
    const para = 'A sentence that repeats itself for padding purposes. ';
    const text = `${para.repeat(40)}\n\n${para.repeat(40)}`; // ~2 × 2160 chars
    const chunks = chunkText(text);
    expect(chunks.length).toBeGreaterThan(1);
    for (const c of chunks) expect(c.length).toBeLessThanOrEqual(CHUNK_MAX_CHARS);
  });

  it('hard-splits a single monster sentence rather than exceeding the cap', () => {
    const monster = 'x'.repeat(CHUNK_MAX_CHARS * 2 + 100);
    const chunks = chunkText(monster);
    expect(chunks.length).toBe(3);
    for (const c of chunks) expect(c.length).toBeLessThanOrEqual(CHUNK_MAX_CHARS);
  });

  it('drops empty/whitespace-only paragraphs', () => {
    expect(chunkText('\n\n   \n\nReal content.\n\n \n')).toEqual(['Real content.']);
  });
});

describe('htmlToText', () => {
  it('strips tags, scripts, styles and chrome; keeps paragraph structure', () => {
    const html = `
      <html><head><style>.x{color:red}</style><script>alert(1)</script></head>
      <body>
        <nav><a href="/">Home</a></nav>
        <h1>About xboom</h1>
        <p>We build robots &amp; drones.</p>
        <footer>© 2026</footer>
      </body></html>`;
    const text = htmlToText(html);
    expect(text).toContain('About xboom');
    expect(text).toContain('We build robots & drones.');
    expect(text).not.toContain('alert(1)');
    expect(text).not.toContain('color:red');
    expect(text).not.toContain('Home');
    expect(text).not.toContain('©');
    expect(text.split('\n\n').length).toBeGreaterThanOrEqual(2);
  });

  it('decodes common entities', () => {
    expect(htmlToText('<p>a &lt;b&gt; &quot;c&quot; &#39;d&#39;&nbsp;e</p>')).toBe(
      'a <b> "c" \'d\' e'
    );
  });
});

describe('ingestText', () => {
  it('upserts one row per chunk and reports the count', async () => {
    const upsert = vi.fn(async () => {});
    const result = await ingestText(
      supabase,
      { text: 'Para one is long enough.\n\nPara two is long enough too.', topic: 'about' },
      { upsert }
    );
    // Small paragraphs merge into one chunk (see chunkText) — one upsert.
    expect(result.chunks).toBe(1);
    expect(upsert).toHaveBeenCalledTimes(1);
    expect(upsert).toHaveBeenCalledWith(supabase, {
      topic: 'about',
      content: 'Para one is long enough.\n\nPara two is long enough too.',
      is_faq: false,
      source: 'manual',
    });
  });

  it('skips fragments shorter than 20 chars (page chrome)', async () => {
    const upsert = vi.fn(async () => {});
    const result = await ingestText(supabase, { text: 'Menu' }, { upsert });
    expect(result.chunks).toBe(0);
    expect(upsert).not.toHaveBeenCalled();
  });
});

describe('ingestUrl', () => {
  it('fetches, strips HTML, and ingests with the URL as source', async () => {
    const upsert = vi.fn(async () => {});
    const fetchPage = vi.fn(async () =>
      '<html><body><p>xboom builds land, air and water robots for enterprise customers.</p></body></html>');
    const result = await ingestUrl(
      supabase,
      { url: 'https://xboom.in/about', topic: 'about' },
      { upsert, fetchPage }
    );
    expect(fetchPage).toHaveBeenCalledWith('https://xboom.in/about');
    expect(result.chunks).toBe(1);
    expect(upsert).toHaveBeenCalledWith(supabase, {
      topic: 'about',
      content: 'xboom builds land, air and water robots for enterprise customers.',
      is_faq: false,
      source: 'https://xboom.in/about',
    });
  });

  it('rejects non-http(s) URLs', async () => {
    await expect(
      ingestUrl(supabase, { url: 'file:///etc/passwd' }, { fetchPage: vi.fn() })
    ).rejects.toThrow(/only http/);
  });

  it('rejects pages that strip down to nothing (JS-rendered)', async () => {
    const fetchPage = vi.fn(async () => '<html><body><div id="root"></div></body></html>');
    await expect(
      ingestUrl(supabase, { url: 'https://spa.example.com' }, { fetchPage })
    ).rejects.toThrow(/no usable text/);
  });
});
