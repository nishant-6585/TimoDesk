# Quick Debug Checklist: "System Stopped" Issue

## Step 1: Click RESUME Button
Open browser DevTools (F12) and look in the **Console** tab.

**Expected:**
```
[ControlScreen] RESUME button pressed
[ControlScreen] Sending resume intent: {intent: resume}
[SpineService] ======== SENDING INTENT ========
[SpineService] Intent type: resume
```

**If NOT seen:** Resume button didn't register the click. Check Flutter build.

---

## Step 2: Check Spine Terminal Receives Intent
Look in the **terminal where Spine is running** (`npm run dev`).

**Expected:**
```
[Spine WebSocket] ======== MESSAGE RECEIVED ========
[Spine WebSocket] Parsed message type: intent
[Router] ======== INTENT RECEIVED ========
[Router] Intent type: resume
```

**If NOT seen:** WebSocket is disconnected. Check Spine is running on port 4000.

---

## Step 3: Check Interlocks Process Resume
**THE CRITICAL LAYER** - Still in Spine terminal.

**Expected:**
```
[Interlocks] ======== INTERLOCK CHECK START ========
[Interlocks] Intent: resume
[Interlocks] Global STOPPED state: true
[Interlocks] [ALLOW] Intent 'resume' is permitted while stopped
[Interlocks] ======== HANDLE RESUME ========
[Interlocks] Current stopped state BEFORE: true
[Interlocks] SYSTEM RESUMED - isStopped is now FALSE
[Interlocks] New stopped state AFTER: false
```

**If you see this:**
```
[Interlocks] [REJECT] Intent 'resume' is a movement intent...
```
This is **WRONG** — resume should be allowed while stopped. Something else is wrong.

---

## Step 4: Check Browser Receives Resume ACK
Back to browser **Console** tab.

**Expected:**
```
[SpineService] ======== MESSAGE RECEIVED ========
[SpineService] Type: resumed
[SpineService] [RESUME ACK] System resumed - updating UI state to stopped=false
```

**If NOT seen:** Spine didn't send the response back. Check Step 3 logs.

---

## Step 5: Verify UI Updated
In the browser app, check:
- RESUME button changed to EMERGENCY STOP (gray)
- Joystick controls are now **enabled** (not greyed out)

**If NOT updated:** UI state didn't change. The `stopped` variable in Riverpod provider is still `true`.

---

## Step 6: Try a Drive Command
Click the Drive joystick forward.

**Expected in browser console:**
```
[ControlScreen] Drive forward
```

**Expected in Spine terminal:**
```
[Interlocks] ======== INTERLOCK CHECK START ========
[Interlocks] Intent: drive
[Interlocks] Global STOPPED state: false
[Interlocks] System is RUNNING (not stopped)
[Interlocks] ======== INTERLOCK CHECK PASS ========
[Handlers] ======== HANDLE INTENT START ========
[Handlers] Executing drive: forward
[Mock SDK] ======== DRIVE ========
[Mock SDK] Direction: forward
```

**If you see:**
```
[Interlocks] [REJECT] Intent 'drive' is a movement intent and system is stopped
```
This means:
1. Resume button was clicked ✓
2. But the global STOPPED state is still `true` ✗
3. The resume handler ran, but the state change didn't stick

---

## Root Cause Decision Tree

### Symptom: Nothing happens when clicking RESUME

**Check:** Browser console
- [ ] See `[ControlScreen] RESUME button pressed`?
  - [ ] **NO** → Button isn't wired. Check control_screen.dart line ~335
  - [ ] **YES** → Continue

**Check:** Spine terminal
- [ ] See `[Router] Intent type: resume`?
  - [ ] **NO** → WebSocket disconnected. Restart Spine.
  - [ ] **YES** → Continue

- [ ] See `[Interlocks] SYSTEM RESUMED - isStopped is now FALSE`?
  - [ ] **NO** → Handler didn't run. Check for error in Handlers.
  - [ ] **YES** → Continue

**Check:** Browser console again
- [ ] See `[SpineService] [RESUME ACK]`?
  - [ ] **NO** → Spine sent wrong response type
  - [ ] **YES** → Continue

**Check:** UI
- [ ] Button changed to EMERGENCY STOP?
  - [ ] **NO** → UI didn't update, `stopped` state is still true. Bug in spine_service.dart _handleMessage
  - [ ] **YES** → Resume worked!

---

### Symptom: Resume button shows, but Drive still blocked after clicking it

**This is the main bug.** 

The flow reaches step 3 and 4, but Step 6 shows `Global STOPPED state: false` then immediately a new drive attempt shows `Global STOPPED state: true`.

**This means:** The state change in Interlocks is not persistent.

**Likely cause:** Module-level variable reset or shadowing somewhere.

**Check:**
1. In `spine/src/commands/interlocks.ts`, is `isStopped` at the module level (line 18)?
2. Is it being reset anywhere besides `resetState()` (for tests)?
3. Is there a race condition where two handlers are running simultaneously?

Search for ALL occurrences of `isStopped =` in the file:

```bash
grep -n "isStopped =" spine/src/commands/interlocks.ts
```

Expected: 
- Line 18: `let isStopped = false;`
- Line 100: `isStopped = true;` (in handleStop)
- Line 115: `isStopped = false;` (in handleResume)
- Line 133: `isStopped = false;` (in resetState for tests)

If you see more assignments, something is wrong.

---

### Symptom: Move commands blocked but there's no "System stopped" visible

**The issue might be rate limiting, not the STOP state.**

**Check Spine terminal:**
```
[Interlocks] Rate limit for 'drive': 100ms, time since last: 50ms, key: xxx:drive
[Interlocks] [RATE LIMITED] Dropping intent (too soon)
```

This is silently dropped (not an error) because the rate limit is working correctly. Send commands slower (>100ms apart) and retry.

---

## Quick Copy-Paste Commands

**Restart Spine with full logs:**
```bash
cd spine && npm run dev
```

**Watch Spine logs for "System stopped":**
```bash
cd spine && npm run dev 2>&1 | grep -E "STOPPED|RESUME|REJECT"
```

**Watch Flutter build output:**
```bash
cd app && flutter run -d chrome
```

**Check WebSocket connection in browser:**
```javascript
// Paste in browser console
console.log('Spine state:', window.__spine);
```

---

## Files Mentioned in Logs

| Log Prefix | File | What It Does |
|---|---|---|
| `[ControlScreen]` | `app/lib/features/control/screens/control_screen.dart` | Flutter UI button clicks |
| `[SpineService]` | `app/lib/services/spine/spine_service.dart` | WebSocket client, send/receive |
| `[Spine WebSocket]` | `spine/src/server.ts` | WebSocket server |
| `[Router]` | `spine/src/commands/router.ts` | Route intents to handlers |
| `[Interlocks]` | `spine/src/commands/interlocks.ts` | **CRITICAL:** Block/allow intents |
| `[Handlers]` | `spine/src/commands/handlers.ts` | Execute intents |
| `[Mock SDK]` | `spine/src/robot/mock.ts` | Fake robot behavior |

---

## Still Stuck?

1. **Post all logs** (both browser console + terminal) showing the issue
2. **Focus on the expected vs. actual at Step 3** - that's where the bug is
3. **Check the Decision Tree above** for your specific symptom
4. **Run the Quick Commands** and grep for key words to isolate the layer
