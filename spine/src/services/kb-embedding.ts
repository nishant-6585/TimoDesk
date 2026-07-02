/**
 * kb-embedding.ts — text embeddings for the KB voice brain (T5).
 *
 * Wraps the Voyage AI embeddings API (voyage-3.5, 1024-dim) behind one function
 * so the provider is a single seam. Voyage uses ASYMMETRIC embeddings: KB chunks
 * are embedded with input_type='document' and questions with input_type='query'
 * — using the right type on each side materially improves retrieval quality.
 *
 * fetch-only (Node 18+ global), no SDK. Gated on VOYAGE_API_KEY; throws a clear
 * error when unset so callers can surface "voice brain not configured".
 */

/** Must equal the vector() dimension in migration 014. */
export const KB_EMBED_DIM = 1024;

const VOYAGE_URL = 'https://api.voyageai.com/v1/embeddings';
const MODEL = process.env.VOYAGE_MODEL || 'voyage-3.5';

export type EmbedInputType = 'query' | 'document';

/**
 * Embed a single text as a 1024-dim vector.
 * @param text      the chunk or question to embed
 * @param inputType 'document' for stored KB chunks, 'query' for a user question
 */
export async function embedText(text: string, inputType: EmbedInputType): Promise<number[]> {
  const apiKey = process.env.VOYAGE_API_KEY;
  if (!apiKey) {
    throw new Error('VOYAGE_API_KEY not set — KB embedding/search is unavailable');
  }

  const resp = await fetch(VOYAGE_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      input: text,
      model: MODEL,
      input_type: inputType,
      output_dimension: KB_EMBED_DIM,
    }),
  });

  if (!resp.ok) {
    const detail = await resp.text().catch(() => '');
    throw new Error(`voyage embed failed: ${resp.status} ${detail}`.trim());
  }

  const json = (await resp.json()) as { data?: Array<{ embedding?: number[] }> };
  const embedding = json.data?.[0]?.embedding;
  if (!embedding || embedding.length !== KB_EMBED_DIM) {
    throw new Error(`voyage embed returned ${embedding?.length ?? 0} dims, expected ${KB_EMBED_DIM}`);
  }
  return embedding;
}
