/**
 * notifyStaff — tell a host that a visitor has arrived, over their chosen channel.
 *
 * notify_channel convention: "prefix:value" —
 *   slack:U0ABC123 · whatsapp:+919812345678 · email:john@xboom.in
 * Uses Node 18+ built-in fetch (no deps) for all three channels.
 *
 * Never throws for a missing/unknown channel, or for a channel whose provider
 * env is unset — the visit is already logged; we just warn and return. But a
 * CONFIGURED send that the provider rejects (non-2xx) DOES throw, so the caller
 * (/visit) can 500 and the operator knows to inform the host manually.
 */

export interface NotifyTarget {
  full_name: string;
  notify_channel?: string | null;
}

/** Throw with the provider's status + body when a send comes back non-2xx. */
async function assertOk(resp: Response, provider: string): Promise<void> {
  if (resp.ok) return;
  const detail = await resp.text().catch(() => '');
  throw new Error(`${provider} notify failed: ${resp.status} ${detail}`.trim());
}

export async function notifyStaff(staff: NotifyTarget, visitorName: string): Promise<void> {
  const channel = staff.notify_channel ?? '';
  const sep = channel.indexOf(':');
  if (sep < 0) {
    console.warn(`[notify] ${staff.full_name}: no/invalid notify_channel ("${channel}") — visit logged, not notified`);
    return;
  }
  const type = channel.slice(0, sep).toLowerCase();
  const value = channel.slice(sep + 1).trim();
  const message = `👋 ${visitorName} is here to see you at the reception.`;

  if (type === 'slack') {
    const url = process.env.SLACK_WEBHOOK_URL;
    if (!url) return void console.warn('[notify] SLACK_WEBHOOK_URL not set — slack skipped');
    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: message }),
    });
    await assertOk(resp, 'slack');
    return;
  }

  if (type === 'whatsapp') {
    const key = process.env.INTERAKT_API_KEY;
    if (!key) return void console.warn('[notify] INTERAKT_API_KEY not set — whatsapp skipped');
    // Simple text send. Interakt may require an approved template for first contact;
    // upgrade to a template message later if so.
    const resp = await fetch('https://api.interakt.ai/v1/public/message/', {
      method: 'POST',
      headers: { Authorization: `Basic ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ fullPhoneNumber: value, type: 'Text', data: { message } }),
    });
    await assertOk(resp, 'whatsapp');
    return;
  }

  if (type === 'email') {
    // Managed HTTP email (Resend) — fetch-only, consistent with slack/whatsapp,
    // no SMTP dependency to operate. Log-only fallback when unconfigured (dev).
    const apiKey = process.env.RESEND_API_KEY;
    const from = process.env.NOTIFY_EMAIL_FROM;
    if (!apiKey || !from) {
      console.info(
        '[notify_email] RESEND_API_KEY/NOTIFY_EMAIL_FROM not set — log-only:',
        JSON.stringify({ to: value, message })
      );
      return;
    }
    const resp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from,
        to: value,
        subject: `${visitorName} is here to see you`,
        text: message,
      }),
    });
    await assertOk(resp, 'email');
    return;
  }

  console.warn(`[notify] unknown channel type "${type}" for ${staff.full_name} — visit logged, not notified`);
}
