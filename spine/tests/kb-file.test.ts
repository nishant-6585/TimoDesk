/**
 * kb-file.test.ts — document ingestion: extension dispatch, size/empty guards,
 * text extraction for the plain-text routes, and the ingest orchestration with
 * injected extract/upsert (no Voyage/Supabase).
 */
import { describe, it, expect } from 'vitest';
import { SupabaseClient } from '@supabase/supabase-js';
import {
  extensionOf,
  extractFileText,
  ingestFile,
  MAX_FILE_BYTES,
} from '../src/services/kb-file';

const fakeSupabase = {} as SupabaseClient;

describe('extensionOf', () => {
  it('recognises supported extensions case-insensitively', () => {
    expect(extensionOf('Company Profile.PDF')).toBe('pdf');
    expect(extensionOf('policies.docx')).toBe('docx');
    expect(extensionOf('notes.txt')).toBe('txt');
    expect(extensionOf('README.md')).toBe('md');
  });

  it('rejects unsupported and extension-less names', () => {
    expect(extensionOf('archive.zip')).toBeNull();
    expect(extensionOf('legacy.doc')).toBeNull(); // old Word format is NOT supported
    expect(extensionOf('noextension')).toBeNull();
  });
});

describe('extractFileText', () => {
  it('decodes txt and md as UTF-8', async () => {
    const text = 'Office hours are 9 to 6, Monday to Friday.';
    expect(await extractFileText(Buffer.from(text, 'utf8'), 'hours.txt')).toBe(text);
    expect(await extractFileText(Buffer.from(text, 'utf8'), 'hours.md')).toBe(text);
  });

  it('throws on unsupported file types', async () => {
    await expect(extractFileText(Buffer.from('x'), 'virus.exe')).rejects.toThrow(/unsupported file type/);
  });

  it('throws on empty files', async () => {
    await expect(extractFileText(Buffer.alloc(0), 'empty.txt')).rejects.toThrow(/file is empty/);
  });

  it('throws on oversized files without reading them', async () => {
    const big = Buffer.alloc(MAX_FILE_BYTES + 1);
    big.fill(97); // 'a'
    await expect(extractFileText(big, 'big.txt')).rejects.toThrow(/file too large/);
  });
});

describe('ingestFile', () => {
  it('decodes base64, extracts, and ingests with the filename as source', async () => {
    const stored: Array<{ content: string; source?: string; topic?: string }> = [];
    const text = 'xboom builds land, air, and water robots for enterprise customers across India.';
    const result = await ingestFile(
      fakeSupabase,
      { filename: 'profile.txt', file_b64: Buffer.from(text).toString('base64'), topic: 'company' },
      {
        upsert: async (_s, chunk) => {
          stored.push(chunk);
        },
      }
    );
    expect(result.chunks).toBe(1);
    expect(stored[0].content).toContain('land, air, and water');
    expect(stored[0].source).toBe('profile.txt');
    expect(stored[0].topic).toBe('company');
  });

  it('rejects documents that produce no usable text (scanned PDFs)', async () => {
    await expect(
      ingestFile(
        fakeSupabase,
        { filename: 'scan.pdf', file_b64: Buffer.from('%PDF-1.4').toString('base64') },
        { extract: async () => '   ' } // parser returned whitespace only
      )
    ).rejects.toThrow(/no usable text/);
  });
});
