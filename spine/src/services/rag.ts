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
import { getMcpPluginRegistry, buildMcpRequestExtras } from './mcp-plugins';
import { getKbProviderRegistry, queryProviders, ProviderAnswer } from './kb-providers';

/** Confidence needed for a cached FAQ answer to skip the LLM entirely (blueprint §06.2). */
export const FAQ_FAST_PATH_THRESHOLD = 0.85;

/** Below this top-hit similarity the local KB counts as a MISS and 3rd-party
 * providers get a turn (local-first priority). Grounded Claude on weak context
 * would answer "I'll connect you to a team member" anyway. */
export const LOCAL_MISS_THRESHOLD = 0.4;

/** Latest Claude model per project convention. Grounded, on-brand concierge voice. */
const CLAUDE_MODEL = process.env.CLAUDE_MODEL || 'claude-opus-4-8';

export type AnswerSource = 'kb' | 'claude' | 'handoff' | 'provider';

export interface Answer {
  answer: string;
  source: AnswerSource;
  similarity: number | null; // top hit similarity, or null if the KB was empty
  chunks: KbHit[]; // the retrieved context (for observability / debugging)
  provider?: string; // set when source === 'provider' — which 3rd-party KB answered
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

/** Extra grounding line added when MCP plugin tools are available to the model. */
const TOOLS_PROMPT_ADDENDUM = `
- Connected tools (calendar, messaging, ticketing) may be available. Use them ONLY to answer the visitor's question or do what they explicitly asked (e.g. check availability, notify a host). Summarise the result in the same 2-3 spoken sentences.`;

/**
 * Generate a grounded spoken answer with Claude. Thinking is left OFF (omitted)
 * and effort is low — a 2-3 sentence grounded answer isn't a reasoning task, and
 * voice latency matters more than depth here. The system prompt's final-answer-only
 * rule prevents reasoning leaking into the visible response (Opus 4.8 note).
 *
 * MCP plugins: when MCP_TOOLS_ENABLED=true and plugins are enabled in the
 * registry, the call goes through the beta MCP connector so the model can use
 * external tools (Slack, calendar, CRM). Default OFF — the plain grounded call
 * below is the demo-critical voice path and stays untouched.
 */
async function generateGroundedAnswer(question: string, chunks: KbHit[]): Promise<string> {
  const client = new Anthropic(); // reads ANTHROPIC_API_KEY from env

  const extras =
    process.env.MCP_TOOLS_ENABLED === 'true'
      ? buildMcpRequestExtras(getMcpPluginRegistry().enabledPlugins())
      : null;

  if (extras) return generateWithMcpTools(client, question, chunks, extras);

  const resp = await client.messages.create({
    model: CLAUDE_MODEL,
    max_tokens: 512,
    output_config: { effort: 'low' },
    system: SYSTEM_PROMPT,
    messages: [{ role: 'user', content: buildUserPrompt(question, chunks) }],
  });
  return extractText(resp.content);
}

function extractText(content: Array<{ type: string }>): string {
  return content
    .filter((b): b is Anthropic.TextBlock => b.type === 'text')
    .map(b => b.text)
    .join('')
    .trim();
}

/**
 * Grounded answer via the Claude API MCP connector (beta mcp-client-2025-11-20).
 * The connector runs the tool loop server-side; a long-running turn can return
 * stop_reason 'pause_turn' — re-send with the assistant turn appended to resume
 * (bounded, so a wedged tool can't hang the reception line).
 */
async function generateWithMcpTools(
  client: Anthropic,
  question: string,
  chunks: KbHit[],
  extras: NonNullable<ReturnType<typeof buildMcpRequestExtras>>
): Promise<string> {
  const messages: Anthropic.Beta.BetaMessageParam[] = [
    { role: 'user', content: buildUserPrompt(question, chunks) },
  ];

  const MAX_CONTINUATIONS = 3;
  for (let i = 0; ; i++) {
    const resp = await client.beta.messages.create({
      model: CLAUDE_MODEL,
      max_tokens: 1024,
      output_config: { effort: 'low' },
      system: SYSTEM_PROMPT + TOOLS_PROMPT_ADDENDUM,
      betas: extras.betas,
      mcp_servers: extras.mcp_servers,
      // mcp_toolset entries — one per declared server, required by the connector.
      tools: extras.tools as unknown as Anthropic.Beta.BetaToolUnion[],
      messages,
    });
    if (resp.stop_reason !== 'pause_turn' || i >= MAX_CONTINUATIONS) {
      return extractText(resp.content);
    }
    messages.push({ role: 'assistant', content: resp.content });
  }
}

export interface AskDeps {
  search?: (q: string) => Promise<KbHit[]>;
  generate?: (q: string, chunks: KbHit[]) => Promise<string>;
  /** Injectable 3rd-party fallback — defaults to the provider registry chain. */
  askProviders?: (q: string) => Promise<ProviderAnswer | null>;
}

/** Pure: does this search result count as a local-KB miss? */
export function isLocalMiss(topSimilarity: number | null): boolean {
  return topSimilarity === null || topSimilarity < LOCAL_MISS_THRESHOLD;
}

/**
 * True when the spine grounded an answer (local KB, cached FAQ, or a registered
 * 3rd-party provider) — the ElevenLabs agent should then PREFER this answer over
 * any overlapping document in its OWN hosted KB. A 'handoff' means everything
 * local missed, so the agent is free to fall back to its own KB, then a human.
 * This is the "local KB wins on overlap" rule, surfaced to the agent as the
 * `authoritative` flag on the /elevenlabs/ask response.
 */
export function isAuthoritative(source: AnswerSource): boolean {
  return source !== 'handoff';
}

function defaultAskProviders(question: string): Promise<ProviderAnswer | null> {
  return queryProviders(getKbProviderRegistry().enabledInOrder(), question);
}

/**
 * Answer a visitor question — LOCAL-FIRST chain:
 *   1. FAQ fast-path (confident local FAQ hit → cached answer, no LLM).
 *   2. Decent local context → grounded Claude over local chunks.
 *   3. Local miss → enabled 3rd-party KB providers, in priority order.
 *   4. Nothing anywhere → grounded Claude (says it'll hand off to a human).
 * Dependencies are injectable so the orchestration is testable without hitting
 * Voyage, Anthropic, or any provider.
 */
export async function askQuestion(
  supabase: SupabaseClient,
  question: string,
  deps: AskDeps = {}
): Promise<Answer> {
  const search = deps.search ?? ((q: string) => searchKb(supabase, q, { limit: 5 }));
  const generate = deps.generate ?? generateGroundedAnswer;
  const askProviders = deps.askProviders ?? defaultAskProviders;

  const chunks = await search(question);
  const topSimilarity = chunks[0]?.similarity ?? null;

  const faq = pickFaqAnswer(chunks);
  if (faq) {
    return { answer: faq.content, source: 'kb', similarity: faq.similarity, chunks };
  }

  if (isLocalMiss(topSimilarity)) {
    const external = await askProviders(question);
    if (external) {
      return {
        answer: external.answer,
        source: 'provider',
        similarity: topSimilarity,
        chunks,
        provider: external.provider,
      };
    }
  }

  const answer = await generate(question, chunks);
  // A local miss that no provider could answer means Claude was given weak or
  // empty context, so its RULES make it promise a human ("I'll connect you to a
  // team member"). Tag that as 'handoff' rather than 'claude' — otherwise the
  // promise is invisible to callers and nobody is ever actually paged.
  const source: AnswerSource = isLocalMiss(topSimilarity) ? 'handoff' : 'claude';
  return { answer, source, similarity: topSimilarity, chunks };
}
