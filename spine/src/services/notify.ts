/**
 * notifyStaff — tell a host that a visitor has arrived, over their chosen channel.
 *
 * notify_channel convention: "prefix:value" —
 *   slack:U0ABC123 · whatsapp:+919812345678 · email:john@xboom.in
 * Uses Node 18+ built-in fetch (no deps). Email is log-only for now.
 *
 * Never throws for a missing/unknown channel — the visit is already logged; we
 * just warn and return. Real send failures DO throw so the caller can 500.
 */

export interface NotifyTarget {
  full_name: string;
  notify_channel?: string | null;
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
    await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: message }),
    });
    return;
  }

  if (type === 'whatsapp') {
    const key = process.env.INTERAKT_API_KEY;
    if (!key) return void console.warn('[notify] INTERAKT_API_KEY not set — whatsapp skipped');
    // Simple text send. Interakt may require an approved template for first contact;
    // upgrade to a template message later if so.
    await fetch('https://api.interakt.ai/v1/public/message/', {
      method: 'POST',
      headers: { Authorization: `Basic ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ fullPhoneNumber: value, type: 'Text', data: { message } }),
    });
    return;
  }

  if (type === 'email') {
    // TODO: wire SMTP in Phase 3. Log-only for now.
    console.info('[notify_email]', JSON.stringify({ to: value, message }));
    return;
  }

  console.warn(`[notify] unknown channel type "${type}" for ${staff.full_name} — visit logged, not notified`);
}
