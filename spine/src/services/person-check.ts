/**
 * services/person-check.ts — transient person-presence scan for escort mode.
 *
 * One scan = sweep the head through a small LR range, grab a snapshot at each
 * position (the same robot /snapshot endpoint the recognizer and enrollment
 * use, via sdk.takeSnapshot), and pass if ANY frame contains a person. The
 * sweep catches a visitor standing slightly off-axis behind the robot.
 *
 * "Person" is proxied by face detection (services/face-embedding.countFaces):
 * detection boxes only — no landmarks, no descriptors, no identity, nothing
 * stored. This is deliberate DPDP posture (no visitor biometrics, ever) and
 * reuses the one loaded face-api pipeline instead of adding a body-detection
 * model. Limitation: the visitor must be roughly facing the robot when it
 * pauses and looks around — flag for hardware tuning.
 */

import { RobotSDK } from '../robot/interface';
import { countFaces } from './face-embedding';

export interface PersonScanOptions {
  headSweepLR: number[]; // head LR positions scanned, center first (0–100)
  headUD: number; // head UD held during the sweep (0–100)
  headSettleMs: number; // wait after each head move before grabbing a frame
  detect: (frame: Buffer) => Promise<boolean>; // injectable for tests
}

export const SCAN_DEFAULTS: Omit<PersonScanOptions, 'detect'> = {
  headSweepLR: [50, 30, 70],
  headUD: 50,
  headSettleMs: 700,
};

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/**
 * Build a scanner bound to the SDK. Returns a function performing one full
 * scan → true if a person appeared in any frame. Never throws: a failed head
 * move or frame is a miss (fail-safe — the escort stops rather than walking
 * off unverified).
 */
export function createPersonScanner(
  sdk: Pick<RobotSDK, 'takeSnapshot' | 'setHeadPosition'>,
  opts: Partial<PersonScanOptions> = {}
): () => Promise<boolean> {
  const cfg: PersonScanOptions = {
    ...SCAN_DEFAULTS,
    detect: async (frame) => (await countFaces(frame)) > 0,
    ...opts,
  };

  return async (): Promise<boolean> => {
    let found = false;
    for (const lr of cfg.headSweepLR) {
      try {
        await sdk.setHeadPosition(lr, cfg.headUD);
        await sleep(cfg.headSettleMs);
        const frame = await sdk.takeSnapshot();
        if (await cfg.detect(frame)) {
          found = true;
          break;
        }
      } catch { /* bad head move / frame → try the next position */ }
    }
    // Best-effort recenter so the robot doesn't resume driving looking sideways.
    try {
      await sdk.setHeadPosition(50, 50);
    } catch { /* best-effort */ }
    return found;
  };
}
