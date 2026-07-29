/**
 * tests/face-recognition-source.test.ts — recognizer frame-source injection
 *
 * Phase 0: FaceRecognitionService no longer builds robot URLs — frames come
 * from an injected FrameSource (server wires it to sdk.captureFrame). These
 * tests verify the injection contract; the face-api pipeline itself is mocked
 * (needs loaded models + real frames).
 */

import { describe, it, expect, vi } from 'vitest';

vi.mock('../src/services/face-embedding', () => ({
  extractEmbedding: vi.fn(async () => ({ ok: false, reason: 'no_face' })),
}));

import { FaceRecognitionService } from '../src/services/face-recognition';
import { extractEmbedding } from '../src/services/face-embedding';
import { FACE_CONFIG } from '../src/config/face-recognition';

const noopSupabase = {} as any;

describe('FaceRecognitionService frame source', () => {
  it('asks the source for a frame with the configured timeout', async () => {
    const frameSource = vi.fn(async () => Buffer.from([0xff, 0xd8, 0, 0]));
    const svc = new FaceRecognitionService(frameSource, noopSupabase, () => {});
    await (svc as any).detectOnce();
    expect(frameSource).toHaveBeenCalledWith(FACE_CONFIG.frame_timeout_ms);
    expect(extractEmbedding).toHaveBeenCalledWith(await frameSource.mock.results[0].value);
  });

  it('skips the cycle cleanly when the source returns null (camera unreachable)', async () => {
    vi.mocked(extractEmbedding).mockClear();
    const frameSource = vi.fn(async () => null);
    const svc = new FaceRecognitionService(frameSource, noopSupabase, () => {});
    await expect((svc as any).detectOnce()).resolves.toBeUndefined();
    expect(extractEmbedding).not.toHaveBeenCalled();
  });
});
