/**
 * rag.ts — the voice brain (T6 FAQ fast-path + T7 grounded Claude fallback).
 *
 * Pipeline (blueprint §06):
 *   question → searchKb → FAQ fast-path (is_faq hit, similarity > 0.85) → cached answer
 *                       → miss → grounded Claude (top-k chunks + rules) → spoken answer
 *
 * Text-first: this module takes a typed question and returns a spoken-style
 * answer string. STT (mic → text) and TTS (text → speaker) bolt on later (P2);
 * the brain is proven against text input first.
 */

import Anthropic from '@anthropic-ai/sdk';
import { SupabaseClient } from '@supabase/supabase-js';
import { searchKb, KbHit } from './kb';

/** Confidence needed for a cached FAQ answer to skip the LLM entirely (blueprint §06.2). */
export const FAQ_FAST_PATH_THRESHOLD = 0.85;

/** Latest Claude model per project convention. Grounded, on-brand concierge voice. */
const CLAUDE_MODEL = process.env.CLAUDE_MODEL || 'claude-opus-4-8';

export type AnswerSource = 'kb' | 'claude' | 'handoff';

export interface Answer {
  answer: string;
  source: AnswerSource;
  similarity: number | null; // top hit similarity, or null if the KB was empty
  chunks: KbHit[]; // the retrieved context (for observability / debugging)
}

/**
 * FAQ fast-path decision — pure, so it's unit-testable. Returns the cached FAQ
 * chunk to answer with directly, or null if we should fall through to Claude.
 */
export function pickFaqAnswer(hits: KbHit[]): KbHit | null {
  const top = hits[0];
  if (top && top.is_faq && top.similarity >= FAQ_FAST_PATH_THRESHOLD) return top;
  return null;
}

/** Spoken-answer system prompt (blueprint §06.3). Persona + strict grounding rules. */
const SYSTEM_PROMPT = `You are Timo, the reception robot at xboom (xboom.in), an Indian company building robots, drones, and underwater ROVs — the only company doing land, air, AND water. You greet visitors and answer their questions at reception.

RULES:
- Answer in 2-3 spoken sentences. This is voice, not text — no lists, no markdown.
- Use ONLY the CONTEXT below. If the answer isn't there, say you'll connect them to a team member. Never invent facts, prices, or specifications.
- Indian/British English. Warm, professional, concise. No emojis.
- Never give pricing, quotes, or commitments — route those to a human.
- Respond with ONLY the spoken answer. No preamble, no reasoning, no "Here is".`;

function buildUserPrompt(question: string, chunks: KbHit[]): string {
  const context = chunks.length
    ? chunks.map((c, i) => `[${i + 1}] ${c.content}`).join('\n\n')
    : '(no relevant knowledge-base entries found)';
  return `CONTEXT:\n${context}\n\nVISITOR QUESTION: ${question}`;
}

/**
 * Generate a grounded spoken answer with Claude. Thinking is left OFF (omitted)
 * and effort is low — a 2-3 sentence grounded answer isn't a reasoning task, and
 * voice latency matters more than depth here. The system prompt's final-answer-only
 * rule prevents reasoning leaking into the visible response (Opus 4.8 note).
 */
async function generateGroundedAnswer(question: string, chunks: KbHit[]): Promise<string> {
  const client = new Anthropic(); // reads ANTHROPIC_API_KEY from env
  const resp = await client.messages.create({
    model: CLAUDE_MODEL,
    max_tokens: 512,
    output_config: { effort: 'low' },
    system: SYSTEM_PROMPT,
    messages: [{ role: 'user', content: buildUserPrompt(question, chunks) }],
  });
  const text = resp.content
    .filter((b): b is Anthropic.TextBlock => b.type === 'text')
    .map(b => b.text)
    .join('')
    .trim();
  return text;
}

export interface AskDeps {
  search?: (q: string) => Promise<KbHit[]>;
  generate?: (q: string, chunks: KbHit[]) => Promise<string>;
}

/**
 * Answer a visitor question: FAQ fast-path when confident, else grounded Claude.
 * Dependencies are injectable so the orchestration is testable without hitting
 * Voyage or Anthropic.
 */
export async function askQuestion(
  supabase: SupabaseClient,
  question: string,
  deps: AskDeps = {}
): Promise<Answer> {
  const search = deps.search ?? ((q: string) => searchKb(supabase, q, { limit: 5 }));
  const generate = deps.generate ?? generateGroundedAnswer;

  const chunks = await search(question);
  const topSimilarity = chunks[0]?.similarity ?? null;

  const faq = pickFaqAnswer(chunks);
  if (faq) {
    return { answer: faq.content, source: 'kb', similarity: faq.similarity, chunks };
  }

  const answer = await generate(question, chunks);
  return { answer, source: 'claude', similarity: topSimilarity, chunks };
}
