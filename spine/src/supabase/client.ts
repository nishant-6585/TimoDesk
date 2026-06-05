/**
 * supabase/client.ts — Supabase client initialization
 * Gracefully handles missing credentials (dev mode)
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';

let client: SupabaseClient | null = null;
let isConfigured = false;

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (url && key) {
  try {
    client = createClient(url, key);
    isConfigured = true;
    console.log('✓ Supabase configured — events will be logged');
  } catch (err) {
    console.warn('⚠ Supabase initialization failed:', err);
    client = null;
    isConfigured = false;
  }
} else {
  console.warn(
    '⚠ Supabase not configured — events will not be persisted. ' +
      'Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY to enable.'
  );
}

export function getSupabaseClient(): SupabaseClient | null {
  return client;
}

export function isSupabaseConfigured(): boolean {
  return isConfigured;
}
