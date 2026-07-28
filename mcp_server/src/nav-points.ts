/**
 * nav-points.ts — read-only lookup of saved navigation points.
 *
 * Points live in Supabase (nav_points table, anon-readable per migration 011);
 * the Flutter admin and robot app read them the same way. Actions still go
 * through the spine — this module only resolves "meeting room" → a SLAM pose.
 */

export interface NavPoint {
  id: string;
  name: string;
  description: string | null;
  x: number;
  y: number;
  z: number;
  rotation: number;
  kind: 'navigation' | 'welcome';
  arrival_text: string | null;
}

export class NavPointsClient {
  constructor(
    private readonly supabaseUrl: string,
    private readonly anonKey: string,
    private readonly fetchFn: typeof fetch = fetch
  ) {}

  async list(): Promise<NavPoint[]> {
    if (!this.supabaseUrl || !this.anonKey) {
      throw new Error(
        'SUPABASE_URL / SUPABASE_ANON_KEY not configured — navigation-point tools are unavailable'
      );
    }
    const url =
      `${this.supabaseUrl}/rest/v1/nav_points` +
      `?select=id,name,description,x,y,z,rotation,kind,arrival_text&order=sort_order.asc`;
    const resp = await this.fetchFn(url, {
      headers: { apikey: this.anonKey, Authorization: `Bearer ${this.anonKey}` },
    });
    if (!resp.ok) {
      throw new Error(`nav_points fetch failed: HTTP ${resp.status} ${await resp.text()}`);
    }
    return (await resp.json()) as NavPoint[];
  }

  /** Case-insensitive name match; exact match wins over substring match. */
  async findByName(name: string): Promise<{ point: NavPoint | null; all: NavPoint[] }> {
    const all = await this.list();
    const needle = name.trim().toLowerCase();
    const exact = all.find(p => p.name.toLowerCase() === needle);
    if (exact) return { point: exact, all };
    const partial = all.filter(p => p.name.toLowerCase().includes(needle));
    return { point: partial.length === 1 ? partial[0] : null, all };
  }
}
