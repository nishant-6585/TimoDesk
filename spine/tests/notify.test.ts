/**
 * tests/notify.test.ts — host handoff channels (T4).
 *
 * Covers: channel parsing, the log-only fallbacks (no throw when a provider env
 * is unset), a real configured email send via Resend, and the send-failure
 * contract (a configured channel that the provider rejects THROWS so /visit 500s).
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { notifyStaff } from '../src/services/notify';

const ORIG_ENV = { ...process.env };

function mockFetch(status: number, body = '') {
  const fn = vi.fn(async () => ({ ok: status >= 200 && status < 300, status, text: async () => body }));
  // @ts-expect-error test override of global fetch
  global.fetch = fn;
  return fn;
}

beforeEach(() => {
  delete process.env.SLACK_WEBHOOK_URL;
  delete process.env.INTERAKT_API_KEY;
  delete process.env.RESEND_API_KEY;
  delete process.env.NOTIFY_EMAIL_FROM;
});

afterEach(() => {
  process.env = { ...ORIG_ENV };
  vi.restoreAllMocks();
});

describe('notifyStaff', () => {
  it('does not throw or fetch when notify_channel is missing/invalid', async () => {
    const f = mockFetch(200);
    await expect(notifyStaff({ full_name: 'Jo', notify_channel: null }, 'Ann')).resolves.toBeUndefined();
    await expect(notifyStaff({ full_name: 'Jo', notify_channel: 'garbage' }, 'Ann')).resolves.toBeUndefined();
    expect(f).not.toHaveBeenCalled();
  });

  it('skips (no throw, no fetch) when the channel provider env is unset', async () => {
    const f = mockFetch(200);
    await notifyStaff({ full_name: 'Jo', notify_channel: 'slack:U1' }, 'Ann'); // SLACK_WEBHOOK_URL unset
    await notifyStaff({ full_name: 'Jo', notify_channel: 'whatsapp:+91' }, 'Ann'); // INTERAKT unset
    expect(f).not.toHaveBeenCalled();
  });

  it('email is log-only when Resend env is unset (no fetch, no throw)', async () => {
    const f = mockFetch(200);
    await notifyStaff({ full_name: 'Jo', notify_channel: 'email:a@b.com' }, 'Ann');
    expect(f).not.toHaveBeenCalled();
  });

  it('sends a real email via Resend when configured', async () => {
    process.env.RESEND_API_KEY = 're_test';
    process.env.NOTIFY_EMAIL_FROM = 'Timo <r@xboom.in>';
    const f = mockFetch(200);
    await notifyStaff({ full_name: 'Jo', notify_channel: 'email:host@xboom.in' }, 'Ann');
    expect(f).toHaveBeenCalledTimes(1);
    const [url, opts] = f.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('https://api.resend.com/emails');
    expect((opts.headers as Record<string, string>).Authorization).toBe('Bearer re_test');
    const sent = JSON.parse(opts.body as string);
    expect(sent.to).toBe('host@xboom.in');
    expect(sent.from).toBe('Timo <r@xboom.in>');
    expect(sent.text).toContain('Ann');
  });

  it('throws when a configured send is rejected by the provider', async () => {
    process.env.SLACK_WEBHOOK_URL = 'https://hooks.slack.test/x';
    mockFetch(404, 'no_service');
    await expect(notifyStaff({ full_name: 'Jo', notify_channel: 'slack:U1' }, 'Ann')).rejects.toThrow(
      /slack notify failed: 404 no_service/
    );
  });
});
