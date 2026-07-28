/**
 * kb-crawl.test.ts — website crawl jobs: pure link extraction and the BFS
 * orchestration with injected fetch/upsert (no network, no Supabase).
 */
import { describe, it, expect, vi } from 'vitest';
import { SupabaseClient } from '@supabase/supabase-js';
import { extractLinks, CrawlJobRegistry, HARD_MAX_PAGES } from '../src/services/kb-crawl';

const fakeSupabase = {} as SupabaseClient;

describe('extractLinks', () => {
  const base = 'https://xboom.in/about';

  it('resolves relative links against the page URL and keeps same-origin only', () => {
    const html = `
      <a href="/products">Products</a>
      <a href="team.html">Team</a>
      <a href="https://xboom.in/contact">Contact</a>
      <a href="https://linkedin.com/company/xboom">LinkedIn</a>`;
    const links = extractLinks(html, base);
    expect(links).toContain('https://xboom.in/products');
    expect(links).toContain('https://xboom.in/team.html');
    expect(links).toContain('https://xboom.in/contact');
    expect(links.some(l => l.includes('linkedin'))).toBe(false);
  });

  it('skips assets, mailto/tel/javascript, and strips fragments', () => {
    const html = `
      <a href="/logo.png">Logo</a>
      <a href="/brochure.pdf">Brochure</a>
      <a href="mailto:hi@xboom.in">Mail</a>
      <a href="tel:+911234">Call</a>
      <a href="javascript:void(0)">JS</a>
      <a href="/faq#pricing">FAQ</a>`;
    const links = extractLinks(html, base);
    expect(links).toEqual(['https://xboom.in/faq']);
  });

  it('dedupes repeated links', () => {
    const html = `<a href="/a">1</a><a href="/a">2</a><a href="/a#x">3</a>`;
    expect(extractLinks(html, base)).toEqual(['https://xboom.in/a']);
  });
});

describe('CrawlJobRegistry', () => {
  /** Tiny fake site: seed page links to /a and /b; /a links back to seed. */
  const site: Record<string, string> = {
    'https://xboom.in/': `<p>${'Welcome to xboom reception. '.repeat(4)}</p><a href="/a">A</a><a href="/b">B</a>`,
    'https://xboom.in/a': `<p>${'Page A talks about drones. '.repeat(4)}</p><a href="/">Home</a>`,
    'https://xboom.in/b': `<p>${'Page B talks about ROVs. '.repeat(4)}</p>`,
  };

  function fakeFetch(url: string): Promise<string> {
    const html = site[url];
    if (!html) return Promise.reject(new Error('404'));
    return Promise.resolve(html);
  }

  it('BFS-crawls same-origin pages once each and ingests their text', async () => {
    const reg = new CrawlJobRegistry();
    const sources: string[] = [];
    const job = reg.start(
      fakeSupabase,
      { url: 'https://xboom.in/' },
      {
        fetchHtml: fakeFetch,
        upsert: async (_s, chunk) => {
          sources.push(chunk.source ?? '');
        },
      }
    );
    expect(job.status).toBe('running');

    await vi.waitFor(() => expect(reg.get(job.id)!.status).toBe('done'));
    const done = reg.get(job.id)!;
    expect(done.pages_crawled).toBe(3); // seed + a + b, no revisit of seed
    expect(done.chunks).toBeGreaterThan(0);
    expect(new Set(sources)).toEqual(new Set(Object.keys(site)));
    expect(done.errors).toEqual([]);
    expect(done.finished_at).not.toBeNull();
  });

  it('respects max_pages and records per-page failures without dying', async () => {
    const reg = new CrawlJobRegistry();
    const failing = (url: string) =>
      url.endsWith('/a') ? Promise.reject(new Error('boom')) : fakeFetch(url);
    const job = reg.start(
      fakeSupabase,
      { url: 'https://xboom.in/', max_pages: 2 },
      { fetchHtml: failing, upsert: async () => {} }
    );
    await vi.waitFor(() => expect(reg.get(job.id)!.status).toBe('done'));
    const done = reg.get(job.id)!;
    expect(done.pages_crawled).toBe(2);
    expect(done.errors.length).toBeLessThanOrEqual(1); // /a may or may not fit in budget
  });

  it('clamps max_pages to the hard cap and rejects non-http seeds', () => {
    const reg = new CrawlJobRegistry();
    const job = reg.start(
      fakeSupabase,
      { url: 'https://xboom.in/', max_pages: 9999 },
      { fetchHtml: fakeFetch, upsert: async () => {} }
    );
    expect(job.max_pages).toBe(HARD_MAX_PAGES);
    expect(() => reg.start(fakeSupabase, { url: 'ftp://files.example.com' })).toThrow(/only http/);
    expect(() => reg.start(fakeSupabase, { url: 'not a url' })).toThrow();
  });

  it('lists jobs newest first', async () => {
    const reg = new CrawlJobRegistry();
    const j1 = reg.start(fakeSupabase, { url: 'https://xboom.in/' }, { fetchHtml: fakeFetch, upsert: async () => {} });
    await vi.waitFor(() => expect(reg.get(j1.id)!.status).toBe('done'));
    const j2 = reg.start(fakeSupabase, { url: 'https://xboom.in/a' }, { fetchHtml: fakeFetch, upsert: async () => {} });
    await vi.waitFor(() => expect(reg.get(j2.id)!.status).toBe('done'));
    const ids = reg.list().map(j => j.id);
    expect(ids.indexOf(j2.id)).toBeLessThanOrEqual(ids.indexOf(j1.id));
  });
});
