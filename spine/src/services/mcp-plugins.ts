/**
 * mcp-plugins.ts — the MCP plugin platform.
 *
 * A file-backed registry of external MCP servers (Slack, Microsoft 365, CRM,
 * ticketing, …) that can be added/removed/toggled at runtime via /mcp/plugins
 * HTTP endpoints — no code changes per integration. Enabled plugins are handed
 * to the Claude API's MCP connector (`mcp_servers` + `mcp_toolset`, beta
 * `mcp-client-2025-11-20`) so the voice brain can call their tools.
 *
 * Secrets: authorization tokens are stored in the JSON file (keep it out of
 * git — it lives next to .env) and are NEVER returned by the HTTP endpoints.
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { dirname, resolve } from 'path';

export interface McpPlugin {
  /** Unique handle, e.g. "slack", "ms365", "freshdesk". */
  name: string;
  /** MCP endpoint URL (Streamable HTTP transport). */
  url: string;
  /** Optional OAuth bearer / access token for the MCP server. */
  authorization_token?: string;
  /** Disabled plugins stay configured but are not offered to the model. */
  enabled: boolean;
  /** Human note shown in the admin. */
  description?: string;
}

/** Plugin as exposed over HTTP — token replaced by a has_token flag. */
export type RedactedPlugin = Omit<McpPlugin, 'authorization_token'> & { has_token: boolean };

const NAME_RE = /^[a-z0-9][a-z0-9_-]{0,63}$/i;

export function validatePlugin(input: Partial<McpPlugin>): string | null {
  if (!input.name || !NAME_RE.test(input.name)) {
    return 'name is required: 1-64 chars, letters/digits/dash/underscore';
  }
  if (!input.url || !/^https?:\/\/.+/.test(input.url)) {
    return 'url is required and must be http(s)';
  }
  return null;
}

export function redact(p: McpPlugin): RedactedPlugin {
  const { authorization_token, ...rest } = p;
  return { ...rest, has_token: Boolean(authorization_token) };
}

export class McpPluginRegistry {
  private plugins: McpPlugin[] = [];

  constructor(private readonly filePath: string) {
    this.load();
  }

  private load(): void {
    if (!existsSync(this.filePath)) {
      this.plugins = [];
      return;
    }
    try {
      const raw = JSON.parse(readFileSync(this.filePath, 'utf8')) as { plugins?: McpPlugin[] };
      this.plugins = Array.isArray(raw.plugins) ? raw.plugins : [];
    } catch (err) {
      console.error(`[McpPlugins] Failed to parse ${this.filePath} — starting empty:`, err);
      this.plugins = [];
    }
  }

  private save(): void {
    mkdirSync(dirname(this.filePath), { recursive: true });
    writeFileSync(this.filePath, JSON.stringify({ plugins: this.plugins }, null, 2) + '\n');
  }

  list(): RedactedPlugin[] {
    return this.plugins.map(redact);
  }

  add(input: Partial<McpPlugin>): { ok: true; plugin: RedactedPlugin } | { ok: false; reason: string } {
    const invalid = validatePlugin(input);
    if (invalid) return { ok: false, reason: invalid };
    if (this.plugins.some(p => p.name.toLowerCase() === input.name!.toLowerCase())) {
      return { ok: false, reason: `plugin "${input.name}" already exists — remove it first to replace` };
    }
    const plugin: McpPlugin = {
      name: input.name!,
      url: input.url!,
      enabled: input.enabled ?? true,
      ...(input.authorization_token ? { authorization_token: input.authorization_token } : {}),
      ...(input.description ? { description: input.description } : {}),
    };
    this.plugins.push(plugin);
    this.save();
    console.log(`[McpPlugins] Added plugin "${plugin.name}" (${plugin.url}), enabled=${plugin.enabled}`);
    return { ok: true, plugin: redact(plugin) };
  }

  remove(name: string): boolean {
    const before = this.plugins.length;
    this.plugins = this.plugins.filter(p => p.name.toLowerCase() !== name.toLowerCase());
    if (this.plugins.length === before) return false;
    this.save();
    console.log(`[McpPlugins] Removed plugin "${name}"`);
    return true;
  }

  setEnabled(name: string, enabled: boolean): RedactedPlugin | null {
    const plugin = this.plugins.find(p => p.name.toLowerCase() === name.toLowerCase());
    if (!plugin) return null;
    plugin.enabled = enabled;
    this.save();
    console.log(`[McpPlugins] Plugin "${plugin.name}" ${enabled ? 'enabled' : 'disabled'}`);
    return redact(plugin);
  }

  enabledPlugins(): McpPlugin[] {
    return this.plugins.filter(p => p.enabled);
  }
}

/**
 * Request extras for the Claude API MCP connector. Every server in
 * `mcp_servers` must be referenced by exactly one `mcp_toolset` entry.
 * Spread into a `client.beta.messages.create` call when plugins are enabled.
 */
export function buildMcpRequestExtras(plugins: McpPlugin[]): {
  betas: string[];
  mcp_servers: Array<{ type: 'url'; url: string; name: string; authorization_token?: string }>;
  tools: Array<{ type: 'mcp_toolset'; mcp_server_name: string }>;
} | null {
  if (!plugins.length) return null;
  return {
    betas: ['mcp-client-2025-11-20'],
    mcp_servers: plugins.map(p => ({
      type: 'url' as const,
      url: p.url,
      name: p.name,
      ...(p.authorization_token ? { authorization_token: p.authorization_token } : {}),
    })),
    tools: plugins.map(p => ({ type: 'mcp_toolset' as const, mcp_server_name: p.name })),
  };
}

let registry: McpPluginRegistry | null = null;

/** Singleton registry; path from MCP_PLUGINS_PATH (default ./mcp-plugins.json). */
export function getMcpPluginRegistry(): McpPluginRegistry {
  if (!registry) {
    registry = new McpPluginRegistry(resolve(process.env.MCP_PLUGINS_PATH ?? 'mcp-plugins.json'));
  }
  return registry;
}
