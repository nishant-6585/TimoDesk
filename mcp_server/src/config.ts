/**
 * config.ts — environment configuration for the Mikee MCP server.
 *
 * The MCP server is a *client* of the spine (never the robot SDK directly),
 * exactly like viewer_web and the Flutter admin. It authenticates with the
 * same kiosk/shared token the robot chest-screen uses.
 */

export interface Config {
  /** Spine HTTP base, e.g. http://192.168.1.50:4000 */
  spineHttpUrl: string;
  /** Spine WebSocket URL derived from the HTTP base unless overridden. */
  spineWsUrl: string;
  /** Token sent in the WS auth message and as HTTP Bearer (kiosk token or Supabase JWT). */
  spineToken: string;
  /** Supabase project URL — used read-only for nav_points lookups. */
  supabaseUrl: string;
  /** Supabase anon key. */
  supabaseAnonKey: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const spineHttpUrl = (env.SPINE_URL ?? 'http://127.0.0.1:4000').replace(/\/$/, '');
  const spineWsUrl = env.SPINE_WS_URL ?? spineHttpUrl.replace(/^http/, 'ws');
  return {
    spineHttpUrl,
    spineWsUrl,
    spineToken: env.SPINE_TOKEN ?? '',
    supabaseUrl: (env.SUPABASE_URL ?? '').replace(/\/$/, ''),
    supabaseAnonKey: env.SUPABASE_ANON_KEY ?? '',
  };
}
