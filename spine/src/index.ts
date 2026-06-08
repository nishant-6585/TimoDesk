/**
 * index.ts — Spine entry point
 * Reads env → picks SDK (mock vs real) → starts server
 */

import { RobotSDK } from './robot/interface';
import { MockRobotSDK } from './robot/mock';
import { RealRobotSDK } from './robot/real';
import { startServer } from './server';
import { startCameraServer } from './camera';
import { isSupabaseConfigured } from './supabase/client';

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('    TIMO RECEPTION ROBOT — SPINE (Integration Gateway)');
  console.log('═══════════════════════════════════════════════════════════════\n');

  // 1. Pick SDK mode
  const mode = (process.env.ROBOT_MODE || 'mock').toLowerCase();
  let sdk: RobotSDK;

  if (mode === 'mock') {
    console.log('🤖 ROBOT_MODE=mock — Using MockRobotSDK (no hardware required)');
    sdk = new MockRobotSDK({ eventIntervalMs: 10000 });
  } else if (mode === 'real') {
    const robotIP = process.env.ROBOT_IP || '192.168.99.101';
    console.log(`🤖 ROBOT_MODE=real — Connecting to robot at ${robotIP}`);
    sdk = new RealRobotSDK({ robotIP });
  } else {
    console.error(`❌ Invalid ROBOT_MODE="${mode}" — must be "mock" or "real"`);
    process.exit(1);
  }

  // 2. Check Supabase
  if (isSupabaseConfigured()) {
    console.log('📊 Supabase configured — events will be logged');
  } else {
    console.log('⚠️  Supabase not configured — events will be logged to console only');
  }

  // 3. Check JWT
  const jwtSecret = process.env.JWT_SECRET;
  if (jwtSecret) {
    console.log('🔒 JWT auth enabled');
  } else {
    console.log('⚠️  JWT auth disabled — DEV MODE ONLY');
  }

  console.log('');

  // 4. Start servers
  try {
    await Promise.all([startServer(sdk), startCameraServer()]);
    console.log('');
    console.log('═══════════════════════════════════════════════════════════════');
    console.log('✓ Spine is running and ready for admin clients');
    console.log('═══════════════════════════════════════════════════════════════\n');
  } catch (err) {
    console.error('❌ Failed to start server:', err);
    process.exit(1);
  }
}

main().catch(console.error);
