import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase configuration
const String supabaseUrl = 'https://agjygqllxdclyzfxidgy.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFnanlncWxseGRjbHl6ZnhpZGd5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2NTY0MzIsImV4cCI6MjA5NjIzMjQzMn0.TbdiNQqayGDRuTnJn4HiO9mNCsg7zaVU7cl2Js8odgg';

// Initialize Supabase (call this in main.dart before running the app)
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
}

// Singleton accessor
SupabaseClient get supabaseClient => Supabase.instance.client;
