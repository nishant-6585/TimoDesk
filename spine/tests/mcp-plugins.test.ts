/**
 * mcp-plugins.test.ts — the MCP plugin platform registry.
 * File-backed CRUD, validation, token redaction, and the Claude API
 * MCP-connector request shape (mcp_servers + mcp_toolset pairing).
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync, readFileSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import {
  McpPluginRegistry,
  buildMcpRequestExtras,
  validatePlugin,
} from '../src/services/mcp-plugins';

let dir: string;
let filePath: string;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'mcp-plugins-'));
  filePath = join(dir, 'mcp-plugins.json');
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe('McpPluginRegistry', () => {
  it('starts empty when no file exists', () => {
    expect(new McpPluginRegistry(filePath).list()).toEqual([]);
  });

  it('adds a plugin, persists it, and reloads from disk', () => {
    const reg = new McpPluginRegistry(filePath);
    const result = reg.add({
      name: 'slack',
      url: 'https://mcp.slack.com/mcp',
      authorization_token: 'xoxp-secret',
      description: 'Team notifications',
    });
    expect(result.ok).toBe(true);

    // A fresh registry instance sees the persisted plugin (with its token).
    const reloaded = new McpPluginRegistry(filePath);
    expect(reloaded.enabledPlugins()).toHaveLength(1);
    expect(reloaded.enabledPlugins()[0].authorization_token).toBe('xoxp-secret');
  });

  it('never exposes tokens via list()', () => {
    const reg = new McpPluginRegistry(filePath);
    reg.add({ name: 'slack', url: 'https://mcp.slack.com/mcp', authorization_token: 'xoxp-secret' });
    const [listed] = reg.list();
    expect(listed).not.toHaveProperty('authorization_token');
    expect(listed.has_token).toBe(true);
    expect(JSON.stringify(reg.list())).not.toContain('xoxp-secret');
  });

  it('rejects duplicate names (case-insensitive) and invalid input', () => {
    const reg = new McpPluginRegistry(filePath);
    reg.add({ name: 'slack', url: 'https://mcp.slack.com/mcp' });
    const dup = reg.add({ name: 'Slack', url: 'https://other.example.com/mcp' });
    expect(dup.ok).toBe(false);

    expect(validatePlugin({ name: 'bad name!', url: 'https://x.com' })).toMatch(/name/);
    expect(validatePlugin({ name: 'ok', url: 'ftp://x.com' })).toMatch(/url/);
    expect(validatePlugin({ name: 'ok', url: 'https://mcp.linear.app/mcp' })).toBeNull();
  });

  it('enable/disable toggles membership in enabledPlugins()', () => {
    const reg = new McpPluginRegistry(filePath);
    reg.add({ name: 'ms365', url: 'https://mcp.example.com/m365' });
    expect(reg.enabledPlugins()).toHaveLength(1);

    expect(reg.setEnabled('ms365', false)?.enabled).toBe(false);
    expect(reg.enabledPlugins()).toHaveLength(0);
    expect(reg.setEnabled('ms365', true)?.enabled).toBe(true);
    expect(reg.setEnabled('nope', true)).toBeNull();
  });

  it('removes plugins and reports missing names', () => {
    const reg = new McpPluginRegistry(filePath);
    reg.add({ name: 'crm', url: 'https://mcp.example.com/crm' });
    expect(reg.remove('crm')).toBe(true);
    expect(reg.remove('crm')).toBe(false);
    expect(JSON.parse(readFileSync(filePath, 'utf8')).plugins).toEqual([]);
  });
});

describe('buildMcpRequestExtras', () => {
  it('returns null with no plugins (caller falls back to the plain voice path)', () => {
    expect(buildMcpRequestExtras([])).toBeNull();
  });

  it('pairs every mcp_server with exactly one mcp_toolset (API requirement)', () => {
    const extras = buildMcpRequestExtras([
      { name: 'slack', url: 'https://mcp.slack.com/mcp', authorization_token: 't1', enabled: true },
      { name: 'crm', url: 'https://mcp.example.com/crm', enabled: true },
    ]);
    expect(extras).not.toBeNull();
    expect(extras!.betas).toEqual(['mcp-client-2025-11-20']);
    expect(extras!.mcp_servers.map(s => s.name)).toEqual(['slack', 'crm']);
    expect(extras!.tools).toEqual([
      { type: 'mcp_toolset', mcp_server_name: 'slack' },
      { type: 'mcp_toolset', mcp_server_name: 'crm' },
    ]);
    // Token flows to the server declaration only when present.
    expect(extras!.mcp_servers[0].authorization_token).toBe('t1');
    expect(extras!.mcp_servers[1]).not.toHaveProperty('authorization_token');
  });
});
