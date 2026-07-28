import { describe, it, expect } from 'vitest';
import { kbStatusPayload } from '../src/handlers/kb';

describe('kbStatusPayload', () => {
  it('reports full readiness when all keys are present', () => {
    const p = kbStatusPayload(12, 3, {
      VOYAGE_API_KEY: 'v',
      ANTHROPIC_API_KEY: 'a',
      ELEVENLABS_TOOL_SECRET: 's',
    } as NodeJS.ProcessEnv);
    expect(p).toMatchObject({
      ok: true,
      chunks: 12,
      faq_chunks: 3,
      embeddings_ready: true,
      llm_ready: true,
      voice_grounding_ready: true,
      ready: true,
    });
  });

  it('is not ready without the embedding key, even with the LLM key', () => {
    const p = kbStatusPayload(0, 0, {
      ANTHROPIC_API_KEY: 'a',
    } as NodeJS.ProcessEnv);
    expect(p.embeddings_ready).toBe(false);
    expect(p.llm_ready).toBe(true);
    expect(p.voice_grounding_ready).toBe(false);
    expect(p.ready).toBe(false);
  });

  it('treats empty-string keys as unset', () => {
    const p = kbStatusPayload(1, 0, {
      VOYAGE_API_KEY: '',
      ANTHROPIC_API_KEY: '',
      ELEVENLABS_TOOL_SECRET: '',
    } as NodeJS.ProcessEnv);
    expect(p.ready).toBe(false);
    expect(p.voice_grounding_ready).toBe(false);
  });
});
