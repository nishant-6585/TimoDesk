import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase configuration
// NOTE: this is the PUBLISHABLE key (sb_publishable_…) — browser/client-safe,
// RLS-enforced. NEVER put a secret (sb_secret_…) or legacy service_role key
// here; this file ships to browsers and phones.
const String supabaseUrl = 'https://agjygqllxdclyzfxidgy.supabase.co';
const String supabaseAnonKey = 'sb_publishable_H3Ifn1sNnlwp2MTixIt2wA_vpvIvAMR';

// Initialize Supabase (call this in main.dart before running the app)
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
}

// Singleton accessor
SupabaseClient get supabaseClient => Supabase.instance.client;
