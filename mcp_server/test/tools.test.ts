/**
 * End-to-end tool tests over an in-memory MCP transport: a real MCP client
 * calls the registered tools; the spine and Supabase are faked at the seam
 * (SpineClient / NavPointsClient method overrides).
 */
import { describe, it, expect, beforeEach } from 'vitest';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { registerTools, ToolDeps } from '../src/tools.js';
import { SpineClient, Intent, SpineMessage } from '../src/spine-client.js';
import { NavPointsClient, NavPoint } from '../src/nav-points.js';

const POINTS: NavPoint[] = [
  { id: '1', name: 'Reception', description: null, x: 0, y: 0, z: 0, rotation: 0, kind: 'welcome', arrival_text: null },
  { id: '2', name: 'Meeting Room', description: null, x: 3.2, y: 1.1, z: 0, rotation: 90, kind: 'navigation', arrival_text: 'Here is the meeting room.' },
];

interface FakeSpine {
  client: SpineClient;
  intents: Intent[];
  httpCalls: { path: string; body?: unknown }[];
  respondWith: (intent: Intent) => SpineMessage;
  httpRespondWith: (path: string) => unknown;
}

function makeFakeSpine(): FakeSpine {
  const fake: FakeSpine = {
    client: new SpineClient('ws://unused', 'http://unused', 'token'),
    intents: [],
    httpCalls: [],
    respondWith: intent => {
      switch (intent.intent) {
        case 'get_status':
          return { type: 'robot_status', status: { online: true, battery: 78 } };
        case 'stop':
          return { type: 'stopped' };
        case 'resume':
          return { type: 'resumed' };
        default:
          return { type: 'ack', intent: intent.intent, ok: true };
      }
    },
    httpRespondWith: path => {
      if (path === '/ask') return { ok: true, answer: 'We build robots.', source: 'kb', similarity: 0.91 };
      if (path === '/kb/status') return { ok: true, chunks: 42 };
      if (path === '/staff') return { ok: true, staff: [{ name: 'Vishal' }] };
      throw new Error(`unexpected path ${path}`);
    },
  };
  fake.client.sendIntent = async (intent: Intent) => {
    fake.intents.push(intent);
    return fake.respondWith(intent);
  };
  fake.client.http = (async (path: string, init?: { body?: unknown }) => {
    fake.httpCalls.push({ path, body: init?.body });
    return fake.httpRespondWith(path);
  }) as SpineClient['http'];
  return fake;
}

function makeFakeNavPoints(points: NavPoint[] = POINTS): NavPointsClient {
  const client = new NavPointsClient('https://x.supabase.co', 'anon');
  client.list = async () => points;
  return client;
}

async function connect(deps: ToolDeps): Promise<Client> {
  const server = new McpServer({ name: 'mikee-mcp-server-test', version: '0.0.0' });
  registerTools(server, deps);
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: 'test-client', version: '0.0.0' });
  await Promise.all([server.connect(serverTransport), client.connect(clientTransport)]);
  return client;
}

describe('mikee MCP tools', () => {
  let fake: FakeSpine;
  let client: Client;

  beforeEach(async () => {
    fake = makeFakeSpine();
    client = await connect({ spine: fake.client, navPoints: makeFakeNavPoints() });
  });

  it('registers the full tool set', async () => {
    const { tools } = await client.listTools();
    const names = tools.map(t => t.name).sort();
    expect(names).toEqual([
      'mikee_ask_knowledge_base',
      'mikee_cancel_navigation',
      'mikee_dock',
      'mikee_emergency_stop',
      'mikee_get_status',
      'mikee_kb_status',
      'mikee_list_nav_points',
      'mikee_list_staff',
      'mikee_navigate_to',
      'mikee_resume',
      'mikee_start_patrol',
      'mikee_stop_patrol',
      'mikee_take_snapshot',
      'mikee_wave',
    ]);
  });

  it('mikee_get_status returns robot status', async () => {
    const res = await client.callTool({ name: 'mikee_get_status', arguments: {} });
    expect(res.isError).toBeFalsy();
    expect(fake.intents).toEqual([{ intent: 'get_status' }]);
    expect(JSON.stringify(res.content)).toContain('battery');
  });

  it('mikee_navigate_to resolves the point and sends a navi intent with pose + arrival text', async () => {
    const res = await client.callTool({
      name: 'mikee_navigate_to',
      arguments: { point_name: 'meeting room' },
    });
    expect(res.isError).toBeFalsy();
    expect(fake.intents).toHaveLength(1);
    expect(fake.intents[0]).toMatchObject({
      intent: 'navi',
      name: 'Meeting Room',
      source: 'mcp',
      arrivalText: 'Here is the meeting room.',
      point: { x: 3.2, y: 1.1, z: 0, rotation: 90 },
    });
  });

  it('mikee_navigate_to fails with available points listed for unknown names', async () => {
    const res = await client.callTool({
      name: 'mikee_navigate_to',
      arguments: { point_name: 'cafeteria' },
    });
    expect(res.isError).toBe(true);
    const text = JSON.stringify(res.content);
    expect(text).toContain('Reception');
    expect(text).toContain('Meeting Room');
    expect(fake.intents).toHaveLength(0); // no intent sent on failed lookup
  });

  it('mikee_start_patrol maps names to poses and rejects unknown points', async () => {
    const ok = await client.callTool({
      name: 'mikee_start_patrol',
      arguments: { point_names: ['Reception', 'Meeting Room'], loop: false },
    });
    expect(ok.isError).toBeFalsy();
    expect(fake.intents[0]).toMatchObject({ intent: 'patrol_start', loop: false });
    expect((fake.intents[0].points as unknown[]).length).toBe(2);

    const bad = await client.callTool({
      name: 'mikee_start_patrol',
      arguments: { point_names: ['Nowhere'] },
    });
    expect(bad.isError).toBe(true);
  });

  it('mikee_emergency_stop and mikee_resume map to stop/resume intents', async () => {
    await client.callTool({ name: 'mikee_emergency_stop', arguments: {} });
    await client.callTool({ name: 'mikee_resume', arguments: {} });
    expect(fake.intents.map(i => i.intent)).toEqual(['stop', 'resume']);
  });

  it('spine error responses surface as tool errors', async () => {
    fake.respondWith = () => ({ type: 'error', message: 'Intent blocked by safety interlocks' });
    const res = await client.callTool({ name: 'mikee_wave', arguments: {} });
    expect(res.isError).toBe(true);
    expect(JSON.stringify(res.content)).toContain('safety interlocks');
  });

  it('mikee_ask_knowledge_base posts the question and returns answer + source', async () => {
    const res = await client.callTool({
      name: 'mikee_ask_knowledge_base',
      arguments: { question: 'What does xboom build?' },
    });
    expect(res.isError).toBeFalsy();
    expect(fake.httpCalls[0]).toEqual({ path: '/ask', body: { question: 'What does xboom build?' } });
    expect(JSON.stringify(res.structuredContent)).toContain('We build robots.');
  });
});
