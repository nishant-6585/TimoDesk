#!/bin/bash
# robot_bringup.sh — post-reboot bring-up in the ORDER that gives BOTH a working
# mic (voice) AND a working chassis (navigation/joystick) at the same time.
#
# THE ROOT PROBLEM this solves:
#   • The USB mic (/dev/snd/pcmC1D0c) is exclusive-open. com.csjbot.robotsdk.ten's
#     AIUI/CAE audio engine grabs it whenever robotsdk runs → our app is "deaf".
#   • The chassis is driven through our app's AIDL binder to robotsdk. If robotsdk
#     is (re)started AFTER our app, that binder dies → DeadObjectException → the
#     robot won't drive. And killing robotsdk to free the mic WEDGES the chassis.
#
# THE FIX (Option B, 2026-07-31): robotsdk hosts its mic-grabbing AIUI as a
#   SEPARATE service — com.csjbot.asragent.aiui_soft.AiuiMixedService — in the same
#   process as the chassis service. `am stopservice` on JUST that service RELEASES
#   the mic while chassis + SLAM keep running. So: start robotsdk (chassis), stop
#   its AiuiMixedService (free mic), start our app — our app then grabs + holds the
#   free mic with NO race. This retired the old kill-robotsdk reclaim hack. The
#   permanent fix belongs with the vendor (docs/VENDOR_MIC_AUDIO.md); this is the
#   reliable local workaround until then.
#
# Usage: ./scripts/robot_bringup.sh [robot_ip]   (default 192.168.1.27)

set -uo pipefail
IP="${1:-192.168.1.27}"
PORT=5555
ADB="adb -s ${IP}:${PORT}"
APP=com.xboom.robot.mini
SDK=com.csjbot.robotsdk.ten
ASR=com.csjbot.asragent

say() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

say "1/6  Connect adb to ${IP}:${PORT}"
adb connect "${IP}:${PORT}" >/dev/null 2>&1
$ADB wait-for-device || { echo "adb not reachable — is the robot on the network?"; exit 1; }

say "2/6  Start the vendor SDK service FIRST (chassis needs it running before our app binds)"
$ADB shell "am start -n ${SDK}/com.csjbot.robotsdk.InfomationActivity" >/dev/null 2>&1
sleep 6
$ADB shell "am startservice -n ${SDK}/com.csjbot.robotsdk.service.RobotSdkService" >/dev/null 2>&1
sleep 4

say "3/6  Option B — FREE THE MIC: stop robotsdk's own AIUI wake-word engine"
# robotsdk.ten hosts com.csjbot.asragent.aiui_soft.AiuiMixedService (the CAE/AIUI
# that exclusive-grabs /dev/snd/pcmC1D0c) in the SAME process as the chassis
# service. Stopping JUST that service releases the mic for OUR app while chassis +
# SLAM (RobotSdkService) keep running — verified 2026-07-31. This replaces the old
# "start asragent + kill-robotsdk reclaim" dance, which was a race that wedged the
# chassis. The vendor forwarding path is broken on this unit (empty result:"") —
# see docs/VENDOR_MIC_AUDIO.md. Re-run this stop if robotsdk ever restarts the
# service (the verify step below flags it).
$ADB shell "am stopservice ${SDK}/com.csjbot.asragent.aiui_soft.AiuiMixedService" >/dev/null 2>&1
sleep 2
FREED=$($ADB shell "su 0 sh -c 'for p in /proc/[0-9]*; do ls -l \$p/fd 2>/dev/null | grep -q pcmC1D0c && cat \$p/cmdline; done'" 2>/dev/null | tr -d '\0')
echo "  mic after stop: ${FREED:-<FREE>}   (want: <FREE> or com.xboom.robot.mini)"

say "4/6  Start the Mikee app (binds a FRESH chassis binder to the running SDK; grabs the now-FREE mic)"
$ADB shell "am force-stop ${APP}" >/dev/null 2>&1
sleep 2
$ADB shell "am start -n ${APP}/.MainActivity" >/dev/null 2>&1
# wait for the app to come alive (camera/gaze loop)
for i in $(seq 1 40); do
  $ADB logcat -d 2>/dev/null | grep -aq "GazeDiag" && break
  sleep 2
done
sleep 3

say "5/6  Open a voice session so the app grabs + HOLDS the mic"
# Tap the Talk FAB (bottom-right of the face box, ~84px). Retry a few times —
# a session start triggers startAudioRecognize which opens pcmC1D0c; our app
# then never releases it. Landscape 1920x1080 → FAB centre ≈ 1846,968.
for t in 1 2 3; do
  $ADB shell "input tap 1846 968" >/dev/null 2>&1
  sleep 3
done

say "6/6  Verify BOTH subsystems"
HOLDER=$($ADB shell "su 0 sh -c 'for p in /proc/[0-9]*; do ls -l \$p/fd 2>/dev/null | grep -q pcmC1D0c && cat \$p/cmdline; done'" 2>/dev/null | tr -d '\0')
APPPID=$($ADB shell pidof "$APP" 2>/dev/null | tr -d '\r')
DEADOBJ=$($ADB logcat -d -T 400 2>/dev/null | grep -a " ${APPPID} " | grep -ac DeadObjectException)
NAVI=$($ADB logcat -d -T 800 2>/dev/null | grep -aoE 'naviReady":(true|false)' | tail -1)

echo
echo "  mic holder     : ${HOLDER:-<none>}   (want: ${APP})"
echo "  chassis binder : DeadObjectException count = ${DEADOBJ}   (want: 0)"
echo "  nav ready      : ${NAVI:-<unknown>}"
echo

MIC_OK=0; CH_OK=0
[[ "$HOLDER" == *"$APP"* ]] && MIC_OK=1
[[ "$DEADOBJ" == "0" ]] && CH_OK=1

if [[ $MIC_OK == 1 && $CH_OK == 1 ]]; then
  echo -e "\033[1;32m✓ BOTH mic and chassis healthy. Do NOT restart robotsdk from here.\033[0m"
elif [[ $CH_OK == 1 && $MIC_OK == 0 ]]; then
  echo -e "\033[1;33m⚠ Chassis OK but our app doesn't hold the mic yet (holder above).\n"
  echo -e "  • If holder is com.csjbot.robotsdk.ten → robotsdk restarted its AIUI: re-run step 3\n"
  echo -e "    (am stopservice ${SDK}/com.csjbot.asragent.aiui_soft.AiuiMixedService) to free it.\n"
  echo -e "  • If holder is <none>/FREE → the auto Talk-tap missed (portrait screen): TAP TALK on the\n"
  echo -e "    robot so a session opens and the app grabs the free mic. NEVER kill robotsdk.\033[0m"
else
  echo -e "\033[1;31m✗ Chassis binder wedged (DeadObject>0). robotsdk was (re)started after the app."
  echo -e "  Re-run this whole script so the app binds a fresh SDK connection.\033[0m"
fi

echo
echo "For POINT navigation (not needed for joystick teleop): open Alpha Map →"
echo "load the map → Relocate at the map origin → verify the dot tracks a 1m drive →"
echo "close Alpha Map FULLY (it steals SDK callbacks if left open)."
