/**
 * KB platform endpoints — manage the reception knowledge base over HTTP.
 *
 *   POST   /kb/ingest       { text, topic?, is_faq? }  → chunk + embed + store
 *   POST   /kb/ingest-url   { url, topic? }            → fetch page → same
 *   GET    /kb/chunks                                  → list (id, topic, …)
 *   DELETE /kb/chunks/{id}                             → remove a chunk
 *
 * Same auth model as the other endpoints (JWT / kiosk token / dev bypass).
 *
 * Also here: POST /elevenlabs/ask — the ElevenLabs Conversational-AI server
 * tool webhook. The agent calls this mid-conversation to answer from OUR KB
 * (RAG /ask) instead of its ungrounded hosted LLM — HANDOFF "two brains"
 * resolution, option B. Authenticated by a dedicated shared secret because
 * ElevenLabs can't hold a Supabase JWT; fail-closed when the secret is unset.
 */

import { IncomingMessage, ServerResponse } from 'http';
import { SupabaseClient } from '@supabase/supabase-js';
import { authorizeRequest } from '../auth/middleware';
import { logEvent } from '../supabase/events';
import { ingestText, ingestUrl } from '../services/kb-ingest';
import { ingestFile } from '../services/kb-file';
import { crawlJobs } from '../services/kb-crawl';
import { askQuestion } from '../services/rag';

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise(resolve => {
    let b = '';
    req.on('data', c => (b += c.toString()));
    req.on('end', () => resolve(b));
  });
}

function json(res: ServerResponse, status: number, payload: unknown): void {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

/** POST /kb/ingest — chunk + embed + store a block of text. */
export async function handleKbIngest(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  let body: { text?: unknown; topic?: unknown; is_faq?: unknown };
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    return json(res, 400, { ok: false, reason: 'Invalid JSON body' });
  }
  const text = typeof body.text === 'string' ? body.text.trim() : '';
  if (!text) return json(res, 400, { ok: false, reason: 'text is required' });

  try {
    const result = await ingestText(supabase, {
      text,
      topic: typeof body.topic === 'string' ? body.topic : undefined,
      is_faq: body.is_faq === true,
    });
    await logEvent('kb_ingested', { actor: auth.userId, kind: 'text', chunks: result.chunks });
    return json(res, 200, { ok: true, chunks: result.chunks });
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    console.error('[kb/ingest] failed:', reason);
    return json(res, 500, { ok: false, reason });
  }
}

/** POST /kb/ingest-url — fetch a public page, strip to text, ingest. */
export async function handleKbIngestUrl(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  let body: { url?: unknown; topic?: unknown };
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    return json(res, 400, { ok: false, reason: 'Invalid JSON body' });
  }
  const url = typeof body.url === 'string' ? body.url.trim() : '';
  if (!url) return json(res, 400, { ok: false, reason: 'url is required' });

  try {
    const result = await ingestUrl(supabase, {
      url,
      topic: typeof body.topic === 'string' ? body.topic : undefined,
    });
    await logEvent('kb_ingested', { actor: auth.userId, kind: 'url', url, chunks: result.chunks });
    return json(res, 200, { ok: true, chunks: result.chunks, source: url });
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    console.error('[kb/ingest-url] failed:', reason);
    // Bad URLs / unusable pages are caller errors, not server faults.
    const status = /only http|unsupported content-type|no usable text|Invalid URL/.test(reason) ? 400 : 500;
    return json(res, status, { ok: false, reason });
  }
}

/** POST /kb/ingest-file — { filename, file_b64, topic? } → extract text (pdf/docx/txt/md) → ingest. */
export async function handleKbIngestFile(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  let body: { filename?: unknown; file_b64?: unknown; topic?: unknown };
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    return json(res, 400, { ok: false, reason: 'Invalid JSON body' });
  }
  const filename = typeof body.filename === 'string' ? body.filename.trim() : '';
  const fileB64 = typeof body.file_b64 === 'string' ? body.file_b64 : '';
  if (!filename || !fileB64) {
    return json(res, 400, { ok: false, reason: 'filename and file_b64 are required' });
  }

  try {
    const result = await ingestFile(supabase, {
      filename,
      file_b64: fileB64,
      topic: typeof body.topic === 'string' ? body.topic : undefined,
    });
    await logEvent('kb_ingested', { actor: auth.userId, kind: 'file', filename, chunks: result.chunks });
    return json(res, 200, { ok: true, chunks: result.chunks, source: filename });
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    console.error('[kb/ingest-file] failed:', reason);
    const status = /unsupported file type|file is empty|file too large|no usable text/.test(reason) ? 400 : 500;
    return json(res, status, { ok: false, reason });
  }
}

/** POST /kb/crawl — { url, max_pages?, topic? } → background crawl job. */
export async function handleKbCrawlStart(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  let body: { url?: unknown; max_pages?: unknown; topic?: unknown };
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    return json(res, 400, { ok: false, reason: 'Invalid JSON body' });
  }
  const url = typeof body.url === 'string' ? body.url.trim() : '';
  if (!url) return json(res, 400, { ok: false, reason: 'url is required' });

  try {
    const job = crawlJobs.start(supabase, {
      url,
      max_pages: typeof body.max_pages === 'number' ? body.max_pages : undefined,
      topic: typeof body.topic === 'string' ? body.topic : undefined,
    });
    await logEvent('kb_crawl_started', { actor: auth.userId, url, max_pages: job.max_pages, job_id: job.id });
    return json(res, 202, { ok: true, job });
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    return json(res, 400, { ok: false, reason });
  }
}

/** GET /kb/crawl — recent crawl jobs (newest first). */
export async function handleKbCrawlList(
  req: IncomingMessage,
  res: ServerResponse
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });
  return json(res, 200, { ok: true, jobs: crawlJobs.list() });
}

/** GET /kb/crawl/{id} — one crawl job's progress. */
export async function handleKbCrawlGet(
  req: IncomingMessage,
  res: ServerResponse,
  jobId: string
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });
  const job = crawlJobs.get(jobId);
  if (!job) return json(res, 404, { ok: false, reason: 'crawl job not found' });
  return json(res, 200, { ok: true, job });
}

/** GET /kb/chunks — list the knowledge base (no embeddings in the payload). */
export async function handleKbList(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  const { data, error } = await supabase
    .from('kb_chunk')
    .select('id, topic, content, is_faq, source, updated_at')
    .order('updated_at', { ascending: false });
  if (error) return json(res, 500, { ok: false, reason: error.message });
  return json(res, 200, { ok: true, chunks: data ?? [] });
}

/** DELETE /kb/chunks/{id} — remove a chunk. Audit-logged (KB shapes answers). */
export async function handleKbDelete(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient,
  chunkId: string
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  const { error, count } = await supabase
    .from('kb_chunk')
    .delete({ count: 'exact' })
    .eq('id', chunkId);
  if (error) return json(res, 500, { ok: false, reason: error.message });
  if (!count) return json(res, 404, { ok: false, reason: 'chunk not found' });

  await logEvent('kb_chunk_deleted', { actor: auth.userId, chunk_id: chunkId });
  return json(res, 200, { ok: true });
}

/**
 * Pure payload builder for /kb/status — split out so the readiness logic is
 * unit-testable without HTTP plumbing.
 */
export function kbStatusPayload(
  chunkCount: number,
  faqCount: number,
  env: NodeJS.ProcessEnv
): Record<string, unknown> {
  const embeddings = Boolean(env.VOYAGE_API_KEY);
  const llm = Boolean(env.ANTHROPIC_API_KEY);
  const voice = Boolean(env.ELEVENLABS_TOOL_SECRET);
  return {
    ok: true,
    chunks: chunkCount,
    faq_chunks: faqCount,
    // What the UIs surface: which halves of the brain are configured.
    embeddings_ready: embeddings, // VOYAGE_API_KEY — required to ingest & search
    llm_ready: llm, // ANTHROPIC_API_KEY — required for non-FAQ RAG answers
    voice_grounding_ready: voice, // ELEVENLABS_TOOL_SECRET — agent webhook auth
    ready: embeddings && llm,
  };
}

/** GET /kb/status — chunk counts + which KB capabilities are configured. */
export async function handleKbStatus(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  const { count, error } = await supabase
    .from('kb_chunk')
    .select('id', { count: 'exact', head: true });
  if (error) return json(res, 500, { ok: false, reason: error.message });
  const { count: faqCount } = await supabase
    .from('kb_chunk')
    .select('id', { count: 'exact', head: true })
    .eq('is_faq', true);

  return json(res, 200, kbStatusPayload(count ?? 0, faqCount ?? 0, process.env));
}

/**
 * POST /elevenlabs/ask — server-tool webhook for the ElevenLabs agent.
 *
 * Configure in the ElevenLabs dashboard as a webhook tool:
 *   URL:    https://<spine>/elevenlabs/ask
 *   Header: x-tool-secret: <ELEVENLABS_TOOL_SECRET>
 *   Body:   { "question": "<the visitor's question>" }
 *
 * Returns { answer, source } — the agent speaks `answer` verbatim-ish, which
 * keeps its replies grounded in our KB (never its own hosted LLM's guesses).
 * Fail-closed: without the env secret the endpoint refuses every call.
 */
export async function handleElevenLabsAsk(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const secret = process.env.ELEVENLABS_TOOL_SECRET;
  if (!secret) {
    return json(res, 503, { ok: false, reason: 'ELEVENLABS_TOOL_SECRET not configured' });
  }
  const presented = req.headers['x-tool-secret'];
  if (presented !== secret) {
    return json(res, 401, { ok: false, reason: 'invalid tool secret' });
  }

  let body: { question?: unknown };
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    return json(res, 400, { ok: false, reason: 'Invalid JSON body' });
  }
  const question = typeof body.question === 'string' ? body.question.trim() : '';
  if (!question) return json(res, 400, { ok: false, reason: 'question is required' });

  try {
    const result = await askQuestion(supabase, question);
    // Flat shape — ElevenLabs feeds the tool result straight to the agent.
    return json(res, 200, { answer: result.answer, source: result.source });
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    console.error('[elevenlabs/ask] failed:', reason);
    // Give the agent a speakable fallback rather than an opaque 500.
    return json(res, 200, {
      answer: "I couldn't reach the knowledge base just now — let me connect you to a team member.",
      source: 'handoff',
    });
  }
}
