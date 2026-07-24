# Mic verification run — after the cached-app-freezer fix (draft 2026-07-22)

**Context:** robot deafness root-caused to Android's cached-app freezer freezing
`com.csjbot.asragent`, which sits mid-pipeline in the vendor audio chain
(`sendAlsaData` → DeadObjectException → no audio/text reaches our listener).
Fix already applied: `settings put global cached_apps_freezer disabled`
(persists; takes effect on boot). Details: memory note `robot-mic-freezer-root-cause`.

## Steps (in order)

1. **Reboot the robot** (main switch off → 15 s → on). Wait **2 full minutes**.
2. Post-boot checklist (the usual ritual):
   - Alpha Map → load map → **Relocate** (position + heading) → verify the dot
     tracks a 1 m drive → **close Alpha Map fully**.
   - Open the **Mikee app** once. Do NOT restart it afterwards.
   - Reconnect adb (new Wireless-debugging port) and tell Claude the `IP:port`.
3. **Claude pre-checks** (before speaking): freezer setting still `disabled`,
   spine online, `get_position` answers, robot app connected to spine,
   speaker volume reset to 12 (resets every reboot).
4. **Claude starts the log capture.**
5. **Speak to the robot**: start a conversation → "Hello Mikee" → wait for the
   reply → "**go to Nishant Desk**" (or any saved point).

## Pass criteria (Claude reads these from the capture)

- `CSJBot mic chunk` lines appear (raw PCM reaching our app — first time since 07-20)
- **No** `DeadObjectException` spam from the vendor service
- ElevenLabs session shows `userSpeaking` / `agentThinking` after you speak
- Voice-nav: robot answers "Please follow me to <point>" and drives; arrival
  announcement plays at the destination
- Bonus: `ASR speechInfo` events with non-empty text (vendor ASR feed — nice to
  have, only used for barge-in)

## If it PASSES
- Commit/push the branch work; update memory; decide whether the vendor kiosk
  app stays enabled (no longer needed for audio once the freezer is off — can
  re-disable it to reclaim the boot screen: `pm disable-user --user 0
  com.csjbot.csjbotscence`, then verify mic still works after one more reboot).

## If it FAILS (still deaf, freezer confirmed off)
- Capture goes into the CSJBot vendor ticket (VENDOR_TICKET_NAV_FAULT.md gets a
  mic section; we already have 5 diagnostic captures).
- Fallback implementation (Claude): run the SDK speech engine
  (`startSpeechService()+startIsr()`) **only during active conversations** —
  sidesteps the CPU-meltdown reason it was removed; restores the June
  known-working in-process path.
