/**
 * tools.ts — MCP tool registrations for the Mikee reception robot.
 *
 * Every action routes through the spine's intent layer, so the existing safety
 * interlocks (STOP latch, auth) apply to MCP clients exactly as they do to the
 * admin app. Read-only data (nav points) comes from Supabase, same as the apps.
 */

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { SpineClient, SpineMessage } from './spine-client.js';
import { NavPointsClient, NavPoint } from './nav-points.js';

export interface ToolDeps {
  spine: SpineClient;
  navPoints: NavPointsClient;
}

interface ToolResult {
  content: { type: 'text'; text: string }[];
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
  [key: string]: unknown;
}

function ok(structured: Record<string, unknown>, text?: string): ToolResult {
  return {
    content: [{ type: 'text', text: text ?? JSON.stringify(structured, null, 2) }],
    structuredContent: structured,
  };
}

function fail(message: string): ToolResult {
  return { content: [{ type: 'text', text: `Error: ${message}` }], isError: true };
}

function errText(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

/** Turn a spine ack/error message into a tool result. */
function fromSpine(msg: SpineMessage, successText: string): ToolResult {
  if (msg.type === 'error') {
    return fail(String(msg.message ?? 'spine rejected the intent'));
  }
  return ok({ result: msg }, successText);
}

function pointSummary(p: NavPoint): Record<string, unknown> {
  return {
    name: p.name,
    kind: p.kind,
    description: p.description,
    arrival_text: p.arrival_text,
    pose: { x: p.x, y: p.y, z: p.z, rotation: p.rotation },
  };
}

export function registerTools(server: McpServer, deps: ToolDeps): void {
  const { spine, navPoints } = deps;

  // ---------- Status & telemetry ----------

  server.registerTool(
    'mikee_get_status',
    {
      title: 'Get Robot Status',
      description:
        'Get the Mikee robot\'s live status: online/offline, battery, and sensor state. ' +
        'Use this first to check the robot is reachable before sending commands.',
      inputSchema: {},
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () => {
      try {
        const msg = await spine.sendIntent({ intent: 'get_status' });
        return fromSpine(msg, `Robot status: ${JSON.stringify(msg.status ?? msg, null, 2)}`);
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  server.registerTool(
    'mikee_take_snapshot',
    {
      title: 'Take Camera Snapshot',
      description:
        'Capture a photo from the robot\'s camera. The image is saved to the admin Gallery ' +
        '(Supabase); the result includes the capture ID when storage is configured.',
      inputSchema: {},
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async () => {
      try {
        const msg = await spine.sendIntent({ intent: 'snapshot' });
        return fromSpine(msg, 'Snapshot captured and saved to the gallery.');
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  // ---------- Gestures ----------

  server.registerTool(
    'mikee_wave',
    {
      title: 'Wave',
      description: 'Make the robot wave its arm — a greeting gesture for visitors or demos.',
      inputSchema: {},
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async () => {
      try {
        return fromSpine(await spine.sendIntent({ intent: 'wave' }), 'Mikee waved.');
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  // ---------- Navigation ----------

  server.registerTool(
    'mikee_list_nav_points',
    {
      title: 'List Navigation Points',
      description:
        'List the saved navigation points (named SLAM poses) the robot can drive to, e.g. ' +
        '"Reception", "Meeting Room". Use these names with mikee_navigate_to and mikee_start_patrol.',
      inputSchema: {},
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () => {
      try {
        const all = await navPoints.list();
        const structured = { count: all.length, points: all.map(pointSummary) };
        const text = all.length
          ? all.map(p => `- ${p.name} (${p.kind})${p.description ? ` — ${p.description}` : ''}`).join('\n')
          : 'No navigation points saved yet. Capture points in the admin app first.';
        return ok(structured, text);
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  server.registerTool(
    'mikee_navigate_to',
    {
      title: 'Navigate To Point',
      description:
        'Send the robot to a saved navigation point by name (case-insensitive; partial names ' +
        'work when unambiguous). Navigation runs asynchronously — the tool returns once the spine ' +
        'accepts the goal, not when the robot arrives. Requires a loaded SLAM map and localization. ' +
        'Optionally override what the robot says on arrival with arrival_text.',
      inputSchema: {
        point_name: z.string().min(1).describe('Name of a saved navigation point, e.g. "Meeting Room"'),
        arrival_text: z.string().optional().describe('Optional phrase the robot speaks on arrival'),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async ({ point_name, arrival_text }) => {
      try {
        const { point, all } = await navPoints.findByName(point_name);
        if (!point) {
          const names = all.map(p => p.name).join(', ') || '(none saved)';
          return fail(`No unique navigation point matches "${point_name}". Available points: ${names}`);
        }
        const msg = await spine.sendIntent({
          intent: 'navi',
          point: { x: point.x, y: point.y, z: point.z, rotation: point.rotation },
          name: point.name,
          source: 'mcp',
          arrivalText: arrival_text ?? point.arrival_text ?? undefined,
        });
        return fromSpine(msg, `Navigation to "${point.name}" started. The robot announces arrival when it gets there.`);
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  server.registerTool(
    'mikee_cancel_navigation',
    {
      title: 'Cancel Navigation',
      description: 'Cancel the active navigation goal (or patrol leg) and stop the robot where it is.',
      inputSchema: {},
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () => {
      try {
        return fromSpine(await spine.sendIntent({ intent: 'cancel_navi' }), 'Navigation cancelled.');
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  server.registerTool(
    'mikee_dock',
    {
      title: 'Return To Charging Dock',
      description: 'Send the robot back to its charging station.',
      inputSchema: {},
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async () => {
      try {
        return fromSpine(await spine.sendIntent({ intent: 'dock' }), 'Robot is heading to the charging dock.');
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  server.registerTool(
    'mikee_start_patrol',
    {
      title: 'Start Patrol',
      description:
        'Start a patrol route through saved navigation points, in order, optionally looping until ' +
        'stopped. Point names must match saved points (see mikee_list_nav_points). Low battery ' +
        'automatically aborts the patrol and docks.',
      inputSchema: {
        point_names: z.array(z.string().min(1)).min(1).describe('Ordered list of saved point names to visit'),
        loop: z.boolean().default(true).describe('Repeat the route until stopped (default true)'),
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    },
    async ({ point_names, loop }) => {
      try {
        const all = await navPoints.list();
        const byName = new Map(all.map(p => [p.name.toLowerCase(), p]));
        const missing: string[] = [];
        const points = point_names.map(n => {
          const p = byName.get(n.trim().toLowerCase());
          if (!p) missing.push(n);
          return p;
        });
        if (missing.length) {
          return fail(
            `Unknown point(s): ${missing.join(', ')}. Available: ${all.map(p => p.name).join(', ') || '(none)'}`
          );
        }
        const msg = await spine.sendIntent({
          intent: 'patrol_start',
          loop,
          points: (points as NavPoint[]).map(p => ({
            x: p.x, y: p.y, z: p.z, rotation: p.rotation,
            name: p.name,
            arrivalText: p.arrival_text ?? undefined,
          })),
        });
        return fromSpine(msg, `Patrol started through: ${point_names.join(' → ')}${loop ? ' (looping)' : ''}.`);
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  server.registerTool(
    'mikee_stop_patrol',
    {
      title: 'Stop Patrol',
      description: 'Stop the active patrol route.',
      inputSchema: {},
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () => {
      try {
        return fromSpine(await spine.sendIntent({ intent: 'patrol_stop' }), 'Patrol stopped.');
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  // ---------- Safety ----------

  server.registerTool(
    'mikee_emergency_stop',
    {
      title: 'Emergency STOP',
      description:
        'EMERGENCY STOP: halt the robot and latch the safety interlock. All motion commands are ' +
        'blocked until mikee_resume is called. Use for safety, not to end a normal navigation ' +
        '(use mikee_cancel_navigation for that).',
      inputSchema: {},
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    },
    async () => {
      try {
        return fromSpine(
          await spine.sendIntent({ intent: 'stop' }),
          'STOP engaged. Motion is locked out until resume.'
        );
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  server.registerTool(
    'mikee_resume',
    {
      title: 'Resume After STOP',
      description: 'Release the emergency-stop interlock so the robot accepts motion commands again.',
      inputSchema: {},
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () => {
      try {
        return fromSpine(await spine.sendIntent({ intent: 'resume' }), 'Interlock released — robot can move again.');
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  // ---------- Knowledge base / reception ----------

  server.registerTool(
    'mikee_ask_knowledge_base',
    {
      title: 'Ask the Knowledge Base',
      description:
        'Ask the reception knowledge base a question, exactly as a visitor would ask the robot. ' +
        'Returns a spoken-style grounded answer plus its source: "kb" (cached FAQ hit), "claude" ' +
        '(generated from retrieved KB chunks), or "handoff" (KB had no answer). Read-only.',
      inputSchema: {
        question: z.string().min(2).describe('The visitor question, e.g. "What does xboom build?"'),
      },
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async ({ question }) => {
      try {
        const resp = await spine.http<{ ok: boolean; answer: string; source: string; similarity: number | null }>(
          '/ask',
          { method: 'POST', body: { question } }
        );
        return ok(
          { answer: resp.answer, source: resp.source, similarity: resp.similarity },
          resp.answer
        );
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  server.registerTool(
    'mikee_kb_status',
    {
      title: 'Knowledge Base Status',
      description: 'Get knowledge-base health: chunk counts and ingest status.',
      inputSchema: {},
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () => {
      try {
        const resp = await spine.http<Record<string, unknown>>('/kb/status');
        return ok(resp);
      } catch (err) {
        return fail(errText(err));
      }
    }
  );

  server.registerTool(
    'mikee_list_staff',
    {
      title: 'List Staff',
      description:
        'List enrolled staff members known to the reception system (names/roles from the staff ' +
        'directory; no biometric data is returned).',
      inputSchema: {},
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    async () => {
      try {
        const resp = await spine.http<Record<string, unknown>>('/staff');
        return ok(resp);
      } catch (err) {
        return fail(errText(err));
      }
    }
  );
}
