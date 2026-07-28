/**
 * kb-file.ts — document ingestion for the KB platform: PDF / Word / plain
 * text files → extracted text → the existing chunk/embed pipeline.
 *
 * Extraction dispatch is by file extension (browsers lie about MIME types for
 * Office docs). Parsers are lazy-imported so the spine boots fast and tests of
 * the dispatch logic don't need the binary parsers at all.
 */

import { SupabaseClient } from '@supabase/supabase-js';
import { ingestText, IngestDeps, IngestResult } from './kb-ingest';

/** Uploads above this are rejected — reception documents, not archives. */
export const MAX_FILE_BYTES = 15 * 1024 * 1024;

export const SUPPORTED_EXTENSIONS = ['pdf', 'docx', 'txt', 'md'] as const;
export type SupportedExtension = (typeof SUPPORTED_EXTENSIONS)[number];

/** Pure: pick the parser route for a filename, or null if unsupported. */
export function extensionOf(filename: string): SupportedExtension | null {
  const ext = filename.toLowerCase().split('.').pop() ?? '';
  return (SUPPORTED_EXTENSIONS as readonly string[]).includes(ext)
    ? (ext as SupportedExtension)
    : null;
}

/** Extract plain text from a document buffer. Throws on unsupported types. */
export async function extractFileText(buf: Buffer, filename: string): Promise<string> {
  const ext = extensionOf(filename);
  if (!ext) {
    throw new Error(
      `unsupported file type "${filename}" — supported: ${SUPPORTED_EXTENSIONS.join(', ')}`
    );
  }
  if (buf.length === 0) throw new Error('file is empty');
  if (buf.length > MAX_FILE_BYTES) {
    throw new Error(`file too large (${Math.round(buf.length / 1024 / 1024)} MB, max 15 MB)`);
  }

  switch (ext) {
    case 'txt':
    case 'md':
      return buf.toString('utf8');
    case 'pdf': {
      // Deep import dodges pdf-parse's debug harness (runs on bare index import).
      const { default: pdfParse } = await import('pdf-parse/lib/pdf-parse.js' as string);
      const parsed = await pdfParse(buf);
      return String(parsed.text ?? '');
    }
    case 'docx': {
      const { default: mammoth } = await import('mammoth');
      const result = await mammoth.extractRawText({ buffer: buf });
      return String(result.value ?? '');
    }
  }
}

/**
 * Decode + extract + ingest an uploaded document. The filename is recorded as
 * the chunk `source` so stale documents can be found and re-ingested.
 */
export async function ingestFile(
  supabase: SupabaseClient,
  input: { filename: string; file_b64: string; topic?: string },
  deps: IngestDeps & { extract?: (buf: Buffer, filename: string) => Promise<string> } = {}
): Promise<IngestResult> {
  const extract = deps.extract ?? extractFileText;
  const buf = Buffer.from(input.file_b64, 'base64');
  const text = (await extract(buf, input.filename)).trim();
  if (text.length < 40) {
    throw new Error('document produced no usable text (scanned/image-only PDF? paste as text instead)');
  }
  return ingestText(supabase, { text, topic: input.topic, source: input.filename }, deps);
}
