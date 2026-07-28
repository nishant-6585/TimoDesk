# Knowledge Base — setup & demo guide

The KB is the **single grounded brain** for Mikee's answers. One pipeline serves
three front doors:

```
                       ┌────────────────────────────┐
  Admin web app ──────►│                            │
  (Knowledge Base tab) │   spine  POST /ask         │
  Robot chest screen ─►│   FAQ fast-path (pgvector) │──► answer + source
  ("Ask Mikee" Q&A)    │   → Claude RAG over KB     │    (kb | claude | handoff)
  ElevenLabs agent ───►│   → honest human handoff   │
  (voice, via webhook) └────────────────────────────┘
```

## 1. API keys (spine/.env) — required before the demo

| Key | What it enables | Where to get it |
|---|---|---|
| `VOYAGE_API_KEY` | Ingesting + searching KB content (embeddings) | dash.voyageai.com → API keys |
| `ANTHROPIC_API_KEY` | Grounded answers for non-FAQ questions (Claude) | console.anthropic.com → API keys |
| `ELEVENLABS_TOOL_SECRET` | Auth for the voice-agent webhook (any long random string you invent, e.g. `openssl rand -hex 24`) | you generate it |

Add all three to `spine/.env`, then restart the spine (or `touch spine/src/index.ts`
if tsx watch is running). The admin app's **Knowledge Base** tab shows a live
readiness banner (`GET /kb/status`) — all chips green = ready.

## 2. Load content

Either through the admin app (Knowledge Base → **Add knowledge** / **Add web page**)
or curl. Mark curated exact answers as **FAQ** — those are spoken as-is when a
question matches closely (fast, deterministic — ideal for the demo); everything
else goes through Claude with the retrieved chunks as context.

Suggested starter set for the CEO demo: what xboom does, office hours, who to
contact for sales/demos, Wi-Fi for guests, where the restroom/meeting rooms are
(pairs beautifully with "take me to the restroom").

## 3. Ground the VOICE agent (ElevenLabs dashboard, one-time)

ElevenLabs Agents → *Mikee — XBoom Reception* → **Tools** → Add tool → Webhook:

- **Name**: `company_knowledge`
- **Description**: “Answers ANY factual question about xboom, the office, its
  people, products, pricing or policies. ALWAYS call this instead of answering
  from your own knowledge.”
- **Method / URL**: `POST http://<spine-host>:4000/elevenlabs/ask`
  (must be reachable from the internet for ElevenLabs cloud — for an office
  demo use a tunnel, e.g. `ngrok http 4000`, and paste the ngrok URL)
- **Headers**: `x-tool-secret: <ELEVENLABS_TOOL_SECRET>`
- **Body parameter**: `question` (string, required) — “the visitor's question,
  verbatim”.

Then in the agent's system prompt add: “For any factual question about the
company, call `company_knowledge` and answer ONLY from its `answer` field. If it
returns a handoff answer, say it and stop.”

Without this section the robot still converses — but from ElevenLabs' own LLM,
ungrounded (it can invent pricing/specs). With it, voice answers come from OUR
KB — same as the two app screens.

## 4. Demo flow that lands

1. Admin app → Knowledge Base: show the green readiness chips, add a fact live
   (“Add knowledge” → e.g. today's guest Wi-Fi code, mark FAQ).
2. Same screen → “Try a question” → ask it → instant FAQ answer with source chip.
3. Robot chest screen → Services → **Voice Q&A** → tap an example chip — Mikee
   speaks the answer aloud.
4. Walk up to the face screen and ASK THE SAME QUESTION by voice → same answer,
   proving one brain everywhere.
5. Finish with “take me to the restroom” → escort + arrival + auto-listening.
