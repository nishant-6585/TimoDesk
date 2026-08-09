# ElevenLabs Agent — Client Tools (Move 2)

The robot app now handles ElevenLabs **client tools**: the agent's LLM resolves
varied phrasing / pronouns / multi-turn params, then invokes a tool, and the app
runs the real on-device action (navigate, check-in, log an enquiry/order) and
replies. The code side is done — this is the **dashboard configuration** you add
so the agent actually calls them.

Where: ElevenLabs dashboard → your Conversational-AI agent → **Tools → Add tool →
Client tool**. Enable **"Wait for response"** on each so the agent speaks the
returned `result`.

## Tools to add

### 1. `navigate_to`
- **Description:** Drive the visitor to a saved location or a staff member's desk. Use for "take me to X", "go to reception", "where is the restroom", or navigating to a person. Resolve pronouns/vague references to a concrete destination first.
- **Parameters:**
  - `destination` *(string, required)* — The place or person to go to, e.g. `Reception`, `the restroom`, or a staff member's name like `David`. If the visitor said a name earlier and then "take me to **his** desk", pass the resolved name (`David`), not "his desk".

### 2. `check_in`
- **Description:** Check a visitor in to meet a staff member and notify that person.
- **Parameters:**
  - `host` *(string, required)* — The staff member the visitor is here to see.

### 3. `raise_enquiry`
- **Description:** Log a product ENQUIRY (visitor wants information or a quote) into the XBoom sales pipeline.
- **Parameters:**
  - `product` *(string, required)* — The product/model they're asking about.
  - `customer_name` *(string, optional)* — The visitor's name, if they give it.
  - `phone` *(string, optional)* — A contact number, if they give it.
  - `notes` *(string, optional)* — Any extra detail of the enquiry.

### 4. `place_order`
- **Description:** Log a product ORDER (visitor wants to buy now — a hot lead) into the XBoom sales pipeline.
- **Parameters:**
  - `product` *(string, required)*
  - `quantity` *(integer, optional)*
  - `customer_name` *(string, optional)*
  - `phone` *(string, optional)*

> The knowledge-base tool (`ask` → `/elevenlabs/ask`) you already have stays as a
> **server** (webhook) tool; keep preferring its answer when `authoritative` is true.

## Agent system-prompt additions

Append to the agent's system prompt:

```
You control a physical reception robot named Mini. You have TOOLS that take real
actions — always prefer calling the right tool over only talking:

• To take a visitor to a place or a person's desk, call navigate_to. First
  resolve pronouns/vague references to a concrete destination — e.g. if they
  said "David" and then "take me to his desk", call navigate_to with
  destination = "David".
• To help a visitor meet a staff member, call check_in with the host's name.
• If a visitor wants product information or a quote, call raise_enquiry. If they
  want to buy / place an order, call place_order. Collect the product first (and
  their name + phone if they offer them) before calling.
• For questions about the company, products, or people, call the knowledge_base
  tool and, when it returns authoritative = true, answer from it verbatim rather
  than your own documents.

After a tool returns, briefly tell the visitor what you did, in one short warm
sentence. Never read out internal ids.
```

## Notes on behavior (already handled in the app)
- `navigate_to` ends the voice session and the robot speaks its own departure
  line as it drives (navigation owns the speaker); on arrival at a staff desk it
  runs the presence check ("Here we are — this is David's desk").
- `navigate_to` reuses the same matcher as spoken nav, so "the dock"/"go home"
  routes to the charging dock, and staff names resolve to their captured desk.
- `raise_enquiry` / `place_order` post to the spine `/xboom/lead` (same pipeline
  as the on-screen FABs) and the agent speaks the returned reference.
