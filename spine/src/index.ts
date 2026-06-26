/**
 * index.ts — Spine entry point
 * Connects to the real robot → starts server
 */

import { RobotSDK } from './robot/interface';
import { RealRobotSDK } from './robot/real';
import { startServer } from './server';
import { startCameraServer } from './camera';
import { isSupabaseConfigured } from './supabase/client';

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('    TIMO RECEPTION ROBOT — SPINE (Integration Gateway)');
  console.log('═══════════════════════════════════════════════════════════════\n');

  // 1. Connect to the robot
  const robotIP = process.env.ROBOT_IP || '192.168.99.101';
  console.log(`🤖 Connecting to robot at ${robotIP}`);
  const sdk: RobotSDK = new RealRobotSDK({ robotIP });

  // 2. Check Supabase
  if (isSupabaseConfigured()) {
    console.log('📊 Supabase configured — events will be logged');
  } else {
    console.log('⚠️  Supabase not configured — events will be logged to console only');
  }

  // 3. Check auth: Supabase JWKS (ES256) verification needs SUPABASE_URL.
  if (process.env.SUPABASE_URL) {
    console.log('🔒 JWT auth enabled (Supabase JWKS / ES256)');
  } else {
    console.log('⚠️  SUPABASE_URL not set — JWKS auth unavailable (dev bypass only)');
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
