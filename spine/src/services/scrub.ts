/**
 * scrub.ts — PII redaction for conversation transcripts before they are stored.
 *
 * The `conversation` table's contract (migration 002) says transcripts must be
 * PII-scrubbed before insert, and /voice/log's comment claimed it happened
 * "upstream" — it did not, anywhere. Visitor names, phone numbers and emails
 * spoken at reception were landing verbatim in a 7-day-retained table.
 *
 * Scope, deliberately narrow: this redacts CONTACT identifiers that are both
 * high-risk and reliably matchable — emails, phone numbers, and long digit runs
 * (card/ID-like). It does NOT attempt to strip names from free text: name
 * detection on STT output is unreliable, and over-redacting would gut the
 * transcript's analytics value. The structured visitor name lives in `visitor`
 * (retention-bound, erasable) — that, not the transcript, is the record of who
 * came in.
 *
 * Redaction is destructive by design: we store the placeholder, never the
 * original, so there is nothing to leak later.
 */

/** Order matters: email before phone, or an email's digits get phone-matched. */
const RULES: Array<{ re: RegExp; with: string }> = [
  // Email addresses.
  { re: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g, with: '[email]' },
  // Phone numbers: optional +country, then 7-15 digits with spaces/dashes/dots.
  // Requires a boundary so it can't eat part of a longer number run.
  { re: /(?<!\d)(?:\+\d{1,3}[\s.-]?)?(?:\d[\s.-]?){7,14}\d(?!\d)/g, with: '[phone]' },
  // Long bare digit runs (16+) — card/ID shaped.
  { re: /(?<!\d)\d{16,}(?!\d)/g, with: '[number]' },
];

/** Redact contact PII from a single string. */
export function scrubText(input: string): string {
  let out = input;
  for (const rule of RULES) out = out.replace(rule.re, rule.with);
  return out;
}

/**
 * Recursively scrub every string value in a transcript entry, preserving shape
 * (role, kind, timestamps and other structure survive untouched). Depth-capped
 * so a malformed/cyclic payload can't spin the reception line.
 */
export function scrubValue(value: unknown, depth = 0): unknown {
  if (depth > 8) return value;
  if (typeof value === 'string') return scrubText(value);
  if (Array.isArray(value)) return value.map(v => scrubValue(v, depth + 1));
  if (value && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = scrubValue(v, depth + 1);
    }
    return out;
  }
  return value;
}

/** Scrub a whole transcript/action array ahead of the `conversation` insert. */
export function scrubTranscript(entries: unknown[]): unknown[] {
  return entries.map(e => scrubValue(e));
}
