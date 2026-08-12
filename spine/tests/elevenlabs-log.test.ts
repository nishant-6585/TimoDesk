/**
 * tests/elevenlabs-log.test.ts — the visitor-question fragment echoed into the
 * spine log by /elevenlabs/ask.
 *
 * WHY THE LOG EXISTS: it is the only signal that distinguishes "the ElevenLabs
 * agent called our KB tool" from "the agent answered from its own hosted KB".
 * No line on a live voice turn means the question never reached us — and so the
 * `authoritative` contract (local KB wins on overlap) never got a say.
 *
 * WHY IT'S TRUNCATED: the question is a visitor utterance. The log is a short
 * recognisable fragment, not a transcript — transcripts belong on the /voice/log
 * path, which is PII-scrubbed and purged after 7 days (DPDP).
 */

import { describe, it, expect } from 'vitest';
import { elevenLabsLogQuestion, LOG_QUESTION_MAX } from '../src/handlers/kb';

describe('elevenLabsLogQuestion', () => {
  it('passes a short question through unchanged', () => {
    expect(elevenLabsLogQuestion('What does xboom do?')).toBe('What does xboom do?');
  });

  it('collapses newlines and runs of whitespace to single spaces', () => {
    expect(elevenLabsLogQuestion('  where is\n\tthe   meeting room ? ')).toBe(
      'where is the meeting room ?'
    );
  });

  it('truncates a long question and marks it with an ellipsis', () => {
    const long = 'a'.repeat(LOG_QUESTION_MAX + 40);
    const out = elevenLabsLogQuestion(long);
    expect(out).toBe(`${'a'.repeat(LOG_QUESTION_MAX)}…`);
    // The fragment never grows without bound, however long the utterance was.
    expect(out.length).toBe(LOG_QUESTION_MAX + 1);
  });

  it('keeps a question of exactly the limit intact (no stray ellipsis)', () => {
    const exact = 'b'.repeat(LOG_QUESTION_MAX);
    expect(elevenLabsLogQuestion(exact)).toBe(exact);
  });

  it('returns an empty string for whitespace-only input', () => {
    expect(elevenLabsLogQuestion('   \n  ')).toBe('');
  });
});
