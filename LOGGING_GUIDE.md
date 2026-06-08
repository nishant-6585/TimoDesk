# Comprehensive Logging Guide for "System Stopped" Debug Tracing

This document explains the detailed logging added to trace the "System stopped" issue across the entire stack.

## Overview

The logging captures the **complete journey** of a resume/stop intent from the Flutter web app through Spine to the MockRobotSDK:

```
Flutter Web App → Spine WebSocket → Router → Interlocks → Handlers → MockRobotSDK
```

## What Logs to Watch

### Layer 1: Flutter Web App (Browser Console)

**File:** `app/lib/features/control/screens/control_screen.dart`

Look for these logs when the RESUME button is clicked:

```
[ControlScreen] RESUME button pressed
[ControlScreen] Sending resume intent: {intent: resume}
```

Or when EMERGENCY STOP is clicked:

```
[ControlScreen] EMERGENCY STOP button pressed
[ControlScreen] Sending stop intent: {intent: stop}
```

**File:** `app/lib/services/spine/spine_service.dart`

After intent is sent, watch for:

```
[SpineService] ======== SENDING INTENT ========
[SpineService] Intent type: resume
[SpineService] Full intent: {intent: resume}
[SpineService] Sending via WebSocket to Spine...
[SpineService] Intent sent, waiting for response...
```

Then watch for the response:

```
[SpineService] ======== MESSAGE RECEIVED ========
[SpineService] Type: resumed
[SpineService] Full payload: {type: resumed}
[SpineService] [RESUME ACK] System resumed - updating UI state to stopped=false
```

### Layer 2: Spine WebSocket Server (Terminal Console)

**File:** `spine/src/server.ts`

When the message arrives at Spine:

```
[Spine WebSocket] ======== MESSAGE RECEIVED ========
[Spine WebSocket] Session: xxx (authenticated: true)
[Spine WebSocket] Raw data: {"type":"intent","intent":{"intent":"resume"}}
[Spine WebSocket] Parsed message type: intent
[Spine WebSocket] Authenticated message, routing to handler...
```

### Layer 3: Router (Terminal Console)

**File:** `spine/src/commands/router.ts`

The router processes the intent:

```
[Router] ======== INTENT RECEIVED ========
[Router] Intent type: resume
[Router] Session ID: xxx
[Router] Full intent payload: {"intent":"resume"}
[Router] Checking safety interlocks...
```

### Layer 4: Interlocks - THE CRITICAL CHECK (Terminal Console)

**File:** `spine/src/commands/interlocks.ts`

**THIS IS WHERE MOVEMENT INTENTS GET REJECTED.** Watch this carefully:

```
[Interlocks] ======== INTERLOCK CHECK START ========
[Interlocks] Intent: drive
[Interlocks] Session: xxx
[Interlocks] Global STOPPED state: true
[Interlocks] System is in STOPPED state
[Interlocks] [REJECT] Intent 'drive' is a movement intent and system is stopped
```

Or for resume (which should be allowed):

```
[Interlocks] ======== INTERLOCK CHECK START ========
[Interlocks] Intent: resume
[Interlocks] Session: xxx
[Interlocks] Global STOPPED state: true
[Interlocks] System is in STOPPED state
[Interlocks] [ALLOW] Intent 'resume' is permitted while stopped
```

When resume is executed, watch for:

```
[Interlocks] ======== HANDLE RESUME ========
[Interlocks] Resume requested by: xxx
[Interlocks] Current stopped state BEFORE: true
[Interlocks] SYSTEM RESUMED - isStopped is now FALSE
[Interlocks] New stopped state AFTER: false
[Interlocks] Logging resume event to Supabase...
[Interlocks] ======== HANDLE RESUME COMPLETE ========
```

### Layer 5: Handlers (Terminal Console)

**File:** `spine/src/commands/handlers.ts`

When the interlock passes, the handler executes:

```
[Handlers] ======== HANDLE INTENT START ========
[Handlers] Intent type: resume
[Handlers] Session: xxx
[Handlers] RESUME intent received - calling handleResume()
[Handlers] handleResume() complete - returning 'resumed' message
[Handlers] ======== HANDLE INTENT COMPLETE ========
```

### Layer 6: MockRobotSDK (Terminal Console)

**File:** `spine/src/robot/mock.ts`

The SDK receives commands:

```
[Mock SDK] ======== STOP DRIVE ========
[Mock SDK] Setting isMoving = false
[Mock SDK] Stop event emitted to all handlers
[Mock SDK] Robot is now idle
```

Or get status:

```
[Mock SDK] ======== GET STATUS ========
[Mock SDK] Current status: {
  online: true,
  battery: 85,
  isMoving: false,
  headLR: 50,
  ...
}
```

## Tracing a Complete Resume Flow

Here's what you should see when clicking RESUME:

### Browser Console:
```
[ControlScreen] RESUME button pressed
[ControlScreen] Sending resume intent: {intent: resume}
[SpineService] ======== SENDING INTENT ========
[SpineService] Intent type: resume
[SpineService] Sending via WebSocket to Spine...

(response comes back)

[SpineService] ======== MESSAGE RECEIVED ========
[SpineService] Type: resumed
[SpineService] [RESUME ACK] System resumed - updating UI state to stopped=false
```

### Terminal (Spine):
```
[Spine WebSocket] ======== MESSAGE RECEIVED ========
[Spine WebSocket] Parsed message type: intent
[Spine WebSocket] Authenticated message, routing to handler...

[Router] ======== INTENT RECEIVED ========
[Router] Intent type: resume
[Router] Checking safety interlocks...

[Interlocks] ======== INTERLOCK CHECK START ========
[Interlocks] Intent: resume
[Interlocks] Global STOPPED state: true
[Interlocks] [ALLOW] Intent 'resume' is permitted while stopped
[Interlocks] ======== INTERLOCK CHECK PASS ========

[Router] [INTERLOCK PASSED] Intent allowed to proceed
[Router] Routing to handler...

[Handlers] ======== HANDLE INTENT START ========
[Handlers] Intent type: resume
[Handlers] RESUME intent received - calling handleResume()
[Interlocks] ======== HANDLE RESUME ========
[Interlocks] Resume requested by: xxx
[Interlocks] Current stopped state BEFORE: true
[Interlocks] SYSTEM RESUMED - isStopped is now FALSE
[Interlocks] New stopped state AFTER: false
[Handlers] handleResume() complete - returning 'resumed' message

[Spine WebSocket] Handler returned response type: resumed
[Spine WebSocket] Sending response to client: {"type":"resumed"}
```

Then when you try to DRIVE:

```
[Interlocks] ======== INTERLOCK CHECK START ========
[Interlocks] Intent: drive
[Interlocks] Global STOPPED state: false
[Interlocks] System is RUNNING (not stopped)
[Interlocks] Checking rate limits...
[Interlocks] ======== INTERLOCK CHECK PASS ========

[Mock SDK] ======== DRIVE ========
[Mock SDK] Direction: forward
```

## Common Issues and Their Signatures

### Issue: "Resume button clicked but nothing happens"

**Look for:**
- Browser: `[ControlScreen] RESUME button pressed` appears?
- Terminal: No `[Router] ======== INTENT RECEIVED ========` for resume?
  - → WebSocket disconnected or not connected
- Terminal: Resume intent arrives but never reaches handlers?
  - → Interlock is blocking it (check interlock logs)

### Issue: "System stopped but move commands still work"

**Look for:**
- Terminal: `[Interlocks] Global STOPPED state: false` when it should be `true`
  - → Stop intent was never received or processed
  - → Check that STOP was sent before the drive commands

### Issue: "Resume accepted but move commands still rejected"

**Look for:**
- Terminal: `[Interlocks] ======== HANDLE RESUME ========` → `New stopped state AFTER: true` (should be false)
  - → Resume handler ran but didn't update the global state
- Terminal: After resume completes, next drive attempt shows `Global STOPPED state: true`
  - → The state change isn't persisting

### Issue: "Interlocks are blocking everything"

**Look for:**
- Terminal: `[Interlocks] [REJECT] Intent 'drive' is a movement intent and system is stopped`
  - This is correct behavior when `Global STOPPED state: true`
  - Send a `resume` intent first
  - Then watch for `New stopped state AFTER: false`
  - Then try drive again

## How to Enable/Disable Logging

All logging is via `console.log()` and `console.error()`:

- **Browser:** Open DevTools (F12) → Console tab
- **Terminal:** Already visible where Spine runs

To reduce noise, comment out specific `console.log()` calls in the files listed above.

## Key State Variable to Watch

**Global STOPPED state** in `spine/src/commands/interlocks.ts`:

```typescript
let isStopped = false;  // This is the single source of truth
```

This is updated by:
1. `handleStop(sessionId)` → sets to `true`
2. `handleResume(sessionId)` → sets to `false`

Every interlock check logs this state. Watch it change:

```
[Interlocks] Global STOPPED state: true   ← After STOP
[Interlocks] Global STOPPED state: false  ← After RESUME
```

If this state doesn't change, the resume handler didn't run properly.

## Expected Log Line Counts

For a single RESUME action:

- Browser: ~5-6 log lines
- Terminal (Spine): ~20-25 log lines

If you see fewer lines, something is failing silently.

## Testing Checklist

1. **Open Flutter web app** → Check: `[SpineService] Connected successfully`
2. **Click EMERGENCY STOP** → Check: `[Interlocks] GLOBAL STOP TRIGGERED`
3. **Check interlocks reject drive** → Check: `[REJECT] Intent 'drive'`
4. **Click RESUME** → Check: `[Interlocks] SYSTEM RESUMED - isStopped is now FALSE`
5. **Click DRIVE** → Check: `[Mock SDK] ======== DRIVE ========`

If any step is missing, dig into that layer's logs.
