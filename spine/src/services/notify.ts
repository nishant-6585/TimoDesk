/**
 * Outbound staff notification over their chosen channel.
 *
 * notify_channel convention: "prefix:value" —
 *   slack:U0ABC123 · whatsapp:+919812345678 · email:john@xboom.in
 * Uses Node 18+ built-in fetch (no deps) for all three channels.
 *
 * Never throws for a missing/unknown channel, or for a channel whose provider
 * env is unset — the triggering event is already logged; we just warn and
 * return. But a CONFIGURED send that the provider rejects (non-2xx) DOES throw,
 * so the caller can decide (e.g. /visit 500s and the operator informs the host
 * manually).
 *
 * `sendToChannel` is the transport; `notifyStaff` is the visitor-arrival
 * message on top of it. Other senders (handoff, intrusion) compose their own
 * message and reuse the same transport rather than duplicating fetch logic.
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

export interface ChannelMessage {
  /** Body text — used by all three channels. */
  message: string;
  /** Email subject line; ignored by slack/whatsapp. */
  subject: string;
  /** Label for log lines when a channel is unroutable. */
  label?: string;
}

/**
 * Send one message over a "prefix:value" channel string. Returns true when the
 * message was actually handed to a provider, false when it was skipped
 * (unroutable channel, or the provider's env isn't configured).
 */
export async function sendToChannel(
  channel: string | null | undefined,
  { message, subject, label = 'notify' }: ChannelMessage
): Promise<boolean> {
  const raw = channel ?? '';
  const sep = raw.indexOf(':');
  if (sep < 0) {
    console.warn(`[notify] ${label}: no/invalid notify_channel ("${raw}") — event logged, not notified`);
    return false;
  }
  const type = raw.slice(0, sep).toLowerCase();
  const value = raw.slice(sep + 1).trim();

  if (type === 'slack') {
    const url = process.env.SLACK_WEBHOOK_URL;
    if (!url) {
      console.warn('[notify] SLACK_WEBHOOK_URL not set — slack skipped');
      return false;
    }
    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: message }),
    });
    await assertOk(resp, 'slack');
    return true;
  }

  if (type === 'whatsapp') {
    const key = process.env.INTERAKT_API_KEY;
    if (!key) {
      console.warn('[notify] INTERAKT_API_KEY not set — whatsapp skipped');
      return false;
    }
    // Simple text send. Interakt may require an approved template for first contact;
    // upgrade to a template message later if so.
    const resp = await fetch('https://api.interakt.ai/v1/public/message/', {
      method: 'POST',
      headers: { Authorization: `Basic ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ fullPhoneNumber: value, type: 'Text', data: { message } }),
    });
    await assertOk(resp, 'whatsapp');
    return true;
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
      return false;
    }
    const resp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to: value, subject, text: message }),
    });
    await assertOk(resp, 'email');
    return true;
  }

  console.warn(`[notify] unknown channel type "${type}" for ${label} — event logged, not notified`);
  return false;
}

export async function notifyStaff(staff: NotifyTarget, visitorName: string): Promise<void> {
  await sendToChannel(staff.notify_channel, {
    message: `👋 ${visitorName} is here to see you at the reception.`,
    subject: `${visitorName} is here to see you`,
    label: staff.full_name,
  });
}

/**
 * Fan out an after-hours intrusion alert (F9).
 *
 * Goes to SECURITY_NOTIFY_CHANNEL, falling back to HANDOFF_NOTIFY_CHANNEL so a
 * deployment that configured one contact point still gets woken up. Best-effort:
 * the siren and the capture must not depend on Slack being reachable.
 */
export async function notifyIntrusion(details: {
  waypoint: string | null;
  at: Date;
  captureId: string | null;
}): Promise<boolean> {
  const channel = process.env.SECURITY_NOTIFY_CHANNEL || process.env.HANDOFF_NOTIFY_CHANNEL;
  const where = details.waypoint ? ` near "${details.waypoint}"` : '';
  const evidence = details.captureId
    ? `\nCaptured frame: ${details.captureId} (Gallery → Snapshots)`
    : '\n(no frame captured — camera or storage unavailable)';
  const message =
    `🚨 INTRUSION DETECTED — a person was seen${where} during the after-hours patrol ` +
    `at ${details.at.toLocaleString()}.${evidence}`;

  if (!channel) {
    console.warn('[notify_intrusion] no SECURITY_NOTIFY_CHANNEL/HANDOFF_NOTIFY_CHANNEL — log-only:', message);
    return false;
  }
  try {
    return await sendToChannel(channel, {
      message,
      subject: '🚨 Intrusion detected — after-hours patrol',
      label: 'security',
    });
  } catch (err) {
    console.error('[notify_intrusion] send failed:', err instanceof Error ? err.message : String(err));
    return false;
  }
}

/**
 * Page the front desk when the robot could not answer a visitor and promised a
 * human (blueprint §08: pricing/commitments and out-of-KB questions route to a
 * person). Best-effort by design — a visitor waiting at reception must never
 * see an error because Slack was down, and the robot has already spoken its
 * handoff line by the time this runs.
 *
 * Channel: HANDOFF_NOTIFY_CHANNEL, same "prefix:value" convention as staff.
 * Unset → logged only, which is the correct default for a dev spine.
 */
export async function notifyHandoff(question: string, context: string): Promise<boolean> {
  const channel = process.env.HANDOFF_NOTIFY_CHANNEL;
  if (!channel) {
    console.info('[notify_handoff] HANDOFF_NOTIFY_CHANNEL not set — log-only:', JSON.stringify({ question, context }));
    return false;
  }
  try {
    return await sendToChannel(channel, {
      message:
        `🤖 A visitor asked something I couldn't answer — someone may be waiting at reception.\n` +
        `Question: "${question}"\nReason: ${context}`,
      subject: 'Reception robot needs a human',
      label: 'front-desk handoff',
    });
  } catch (err) {
    // Swallow: the visitor-facing answer already went out.
    console.error('[notify_handoff] send failed:', err instanceof Error ? err.message : String(err));
    return false;
  }
}
