/**
 * kb-providers.ts — external ("3rd-party") knowledge sources for the ask
 * pipeline, with LOCAL-FIRST priority:
 *
 *   question → local KB (FAQ fast-path / grounded Claude on good hits)
 *            → local miss → enabled providers, ascending `priority`
 *            → nothing → grounded Claude fallback (says it'll hand off)
 *
 * A provider is any HTTP endpoint that answers POST {question} with
 * {answer: "..."} — that generic shape covers ElevenLabs-style webhooks, a
 * corporate FAQ service, another Mikee spine, etc. File-backed registry next
 * to .env (mcp-plugins.json pattern); tokens never returned over HTTP.
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { dirname, resolve } from 'path';

export interface KbProvider {
  /** Unique handle, e.g. "elevenlabs", "hq-faq". */
  name: string;
  /** Provider kind. 'http': POST {question} → {answer}. */
  type: 'http';
  /** Endpoint URL. */
  url: string;
  /** Optional bearer token sent as Authorization: Bearer <token>. */
  authorization_token?: string;
  /** Ask order among providers — lower asks first. Local KB always wins. */
  priority: number;
  enabled: boolean;
  description?: string;
}

export type RedactedProvider = Omit<KbProvider, 'authorization_token'> & { has_token: boolean };

const NAME_RE = /^[a-z0-9][a-z0-9_-]{0,63}$/i;

export function validateProvider(input: Partial<KbProvider>): string | null {
  if (!input.name || !NAME_RE.test(input.name)) {
    return 'name is required: 1-64 chars, letters/digits/dash/underscore';
  }
  if (!input.url || !/^https?:\/\/.+/.test(input.url)) {
    return 'url is required and must be http(s)';
  }
  if (input.type !== undefined && input.type !== 'http') {
    return "type must be 'http'";
  }
  if (input.priority !== undefined && (!Number.isInteger(input.priority) || input.priority < 0)) {
    return 'priority must be a non-negative integer';
  }
  return null;
}

export function redactProvider(p: KbProvider): RedactedProvider {
  const { authorization_token, ...rest } = p;
  return { ...rest, has_token: Boolean(authorization_token) };
}

export class KbProviderRegistry {
  private providers: KbProvider[] = [];

  constructor(private readonly filePath: string) {
    this.load();
  }

  private load(): void {
    if (!existsSync(this.filePath)) {
      this.providers = [];
      return;
    }
    try {
      const raw = JSON.parse(readFileSync(this.filePath, 'utf8')) as { providers?: KbProvider[] };
      this.providers = Array.isArray(raw.providers) ? raw.providers : [];
    } catch (err) {
      console.error(`[kb-providers] failed to read ${this.filePath}:`, err);
      this.providers = [];
    }
  }

  private save(): void {
    mkdirSync(dirname(this.filePath), { recursive: true });
    writeFileSync(this.filePath, JSON.stringify({ providers: this.providers }, null, 2) + '\n');
  }

  list(): RedactedProvider[] {
    return [...this.providers]
      .sort((a, b) => a.priority - b.priority || a.name.localeCompare(b.name))
      .map(redactProvider);
  }

  /** Enabled providers in ask order — full records, for the ask chain only. */
  enabledInOrder(): KbProvider[] {
    return this.providers
      .filter(p => p.enabled)
      .sort((a, b) => a.priority - b.priority || a.name.localeCompare(b.name));
  }

  add(input: {
    name: string;
    url: string;
    authorization_token?: string;
    priority?: number;
    enabled?: boolean;
    description?: string;
  }): RedactedProvider {
    const invalid = validateProvider(input);
    if (invalid) throw new Error(invalid);
    if (this.providers.some(p => p.name.toLowerCase() === input.name.toLowerCase())) {
      throw new Error(`provider "${input.name}" already exists`);
    }
    const provider: KbProvider = {
      name: input.name,
      type: 'http',
      url: input.url,
      ...(input.authorization_token ? { authorization_token: input.authorization_token } : {}),
      priority: input.priority ?? this.nextPriority(),
      enabled: input.enabled ?? true,
      ...(input.description ? { description: input.description } : {}),
    };
    this.providers.push(provider);
    this.save();
    return redactProvider(provider);
  }

  /** Partial update — url, token, priority, enabled, description. */
  update(
    name: string,
    patch: Partial<Pick<KbProvider, 'url' | 'authorization_token' | 'priority' | 'enabled' | 'description'>>
  ): RedactedProvider {
    const provider = this.providers.find(p => p.name === name);
    if (!provider) throw new Error(`provider "${name}" not found`);
    const merged = { ...provider, ...patch, name: provider.name, type: provider.type };
    const invalid = validateProvider(merged);
    if (invalid) throw new Error(invalid);
    Object.assign(provider, patch);
    if (patch.authorization_token === '') delete provider.authorization_token;
    this.save();
    return redactProvider(provider);
  }

  remove(name: string): void {
    const before = this.providers.length;
    this.providers = this.providers.filter(p => p.name !== name);
    if (this.providers.length === before) throw new Error(`provider "${name}" not found`);
    this.save();
  }

  private nextPriority(): number {
    return this.providers.reduce((max, p) => Math.max(max, p.priority), -1) + 1;
  }
}

let registry: KbProviderRegistry | null = null;

/** Process-wide registry, file next to .env (mcp-plugins.json pattern). */
export function getKbProviderRegistry(): KbProviderRegistry {
  if (!registry) {
    registry = new KbProviderRegistry(resolve(process.env.KB_PROVIDERS_PATH ?? 'kb-providers.json'));
  }
  return registry;
}

export interface ProviderAnswer {
  answer: string;
  provider: string;
}

/**
 * Ask enabled providers in priority order; first usable answer wins. Provider
 * failures are logged and skipped — a flaky 3rd-party KB must never take the
 * voice brain down. Fetch is injectable for tests.
 */
export async function queryProviders(
  providers: KbProvider[],
  question: string,
  deps: { fetchFn?: typeof fetch; timeoutMs?: number } = {}
): Promise<ProviderAnswer | null> {
  const fetchFn = deps.fetchFn ?? fetch;
  const timeoutMs = deps.timeoutMs ?? 8_000;
  for (const p of providers) {
    try {
      const resp = await fetchFn(p.url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(p.authorization_token ? { Authorization: `Bearer ${p.authorization_token}` } : {}),
        },
        body: JSON.stringify({ question }),
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const data = (await resp.json()) as { answer?: unknown };
      const answer = typeof data.answer === 'string' ? data.answer.trim() : '';
      if (answer) return { answer, provider: p.name };
    } catch (err) {
      console.error(`[kb-providers] "${p.name}" failed:`, err instanceof Error ? err.message : err);
    }
  }
  return null;
}
