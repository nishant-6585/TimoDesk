import { describe, it, expect } from 'vitest';
import { NavPointsClient, NavPoint } from '../src/nav-points.js';

const POINTS: NavPoint[] = [
  { id: '1', name: 'Reception', description: null, x: 0, y: 0, z: 0, rotation: 0, kind: 'welcome', arrival_text: null },
  { id: '2', name: 'Meeting Room', description: 'Main meeting room', x: 3.2, y: 1.1, z: 0, rotation: 90, kind: 'navigation', arrival_text: 'We have arrived at the meeting room.' },
  { id: '3', name: 'Meeting Room B', description: null, x: 5, y: 2, z: 0, rotation: 180, kind: 'navigation', arrival_text: null },
];

function clientWith(points: NavPoint[], status = 200): NavPointsClient {
  const fakeFetch = (async () =>
    new Response(JSON.stringify(points), { status })) as unknown as typeof fetch;
  return new NavPointsClient('https://example.supabase.co', 'anon-key', fakeFetch);
}

describe('NavPointsClient.findByName', () => {
  it('matches exact name case-insensitively', async () => {
    const { point } = await clientWith(POINTS).findByName('meeting room');
    expect(point?.id).toBe('2');
  });

  it('exact match wins over substring matches', async () => {
    // "Meeting Room" is a substring of "Meeting Room B" — exact must win.
    const { point } = await clientWith(POINTS).findByName('Meeting Room');
    expect(point?.id).toBe('2');
  });

  it('resolves an unambiguous partial match', async () => {
    const { point } = await clientWith(POINTS).findByName('recep');
    expect(point?.id).toBe('1');
  });

  it('returns null on ambiguous partial match', async () => {
    const { point, all } = await clientWith(POINTS).findByName('room b');
    expect(point?.id).toBe('3'); // unique
    const ambiguous = await clientWith(POINTS).findByName('meeting');
    expect(ambiguous.point).toBeNull();
    expect(all).toHaveLength(3);
  });

  it('throws a clear error when Supabase is not configured', async () => {
    const c = new NavPointsClient('', '', fetch);
    await expect(c.list()).rejects.toThrow(/SUPABASE_URL/);
  });

  it('surfaces HTTP failures', async () => {
    await expect(clientWith([], 500).list()).rejects.toThrow(/HTTP 500/);
  });
});
