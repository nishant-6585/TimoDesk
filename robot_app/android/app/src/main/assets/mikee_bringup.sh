#!/system/bin/sh
# mikee_bringup.sh — post-reboot bring-up, run AS ROOT detached from the app
# (BootReceiver copies this from APK assets to /data/local/tmp and nohup-runs it).
#
# Ports the proven adb ritual (2026-08-18..20 hardware sessions) onto the robot:
#   1. Start robotsdk FIRST (chassis binder must exist before our app binds).
#   2. Kill the early app process the BOOT_COMPLETED broadcast spawned (its SDK
#      binder inited in Application.onCreate before robotsdk was up → dead).
#   3. Start the app fresh; wait for the camera server (:8080) — the only reliable
#      "app is really up" signal (pidof lies during Flutter boot).
#   4. Open a voice session (tap the Talk FAB) so the recorder starts retrying.
#   5. If robotsdk's CAE still holds the mic (pcmC1D0c): kill-loop robotsdk until
#      OUR app holds it (verified each round — the Option-B stopservice does NOT
#      release the fd on this unit), then restart robotsdk and bounce the app for
#      a fresh binder. Restart robotsdk ONLY after the app holds the mic, else
#      its CAE re-grabs (2026-08-20 failure mode).
#
# Log: /data/local/tmp/mikee_bringup.log (overwritten each boot).

LOG=/data/local/tmp/mikee_bringup.log
APP=com.xboom.robot.mini
SDK=com.csjbot.robotsdk.ten
MIC_DEV=pcmC1D0c
TAP_X=1846
TAP_Y=968

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"; }

mic_holder() {
  for p in /proc/[0-9]*; do
    if ls -l "$p/fd" 2>/dev/null | grep -q "$MIC_DEV"; then
      tr -d '\0' < "$p/cmdline"
      return
    fi
  done
}

# camera server listens on :8080 = 0x1F90 — presence in /proc/net/tcp* means the
# Flutter app finished booting its Java plugins.
camera_up() { grep -q ":1F90 " /proc/net/tcp /proc/net/tcp6 2>/dev/null; }

start_sdk() {
  am start -n $SDK/com.csjbot.robotsdk.InfomationActivity >/dev/null 2>&1
  sleep 8
  am startservice -n $SDK/com.csjbot.robotsdk.service.RobotSdkService >/dev/null 2>&1
  sleep 6
}

start_app_and_wait() {
  am start -n $APP/.MainActivity >/dev/null 2>&1
  i=0
  while [ $i -lt 30 ]; do
    camera_up && break
    sleep 4
    i=$((i+1))
  done
  sleep 3
}

: > "$LOG"
log "=== bringup start ==="
sleep 5

log "start robotsdk"
start_sdk

APPPID=$(pidof $APP)
if [ -n "$APPPID" ]; then
  log "kill early app process pid=$APPPID (binder pre-dates robotsdk)"
  kill "$APPPID"
  sleep 3
fi

log "start app, wait for camera"
start_app_and_wait
camera_up && log "camera: up" || log "camera: STILL DOWN after wait"

input tap $TAP_X $TAP_Y
sleep 5
H=$(mic_holder)
log "mic holder after first tap: ${H:-FREE}"

case "$H" in
  *"$APP"*) : ;;  # app already holds the mic — done
  *)
    log "reclaim ritual: kill-loop robotsdk until app holds mic"
    input tap $TAP_X $TAP_Y
    sleep 2
    round=1
    while [ $round -le 3 ]; do
      i=0
      while [ $i -lt 10 ]; do
        am force-stop $SDK
        sleep 2
        i=$((i+1))
      done
      H=$(mic_holder)
      log "round $round holder: ${H:-FREE}"
      case "$H" in *"$APP"*) break ;; esac
      input tap $TAP_X $TAP_Y
      sleep 3
      round=$((round+1))
    done
    log "restart robotsdk (app holds mic: ${H:-NO})"
    start_sdk
    log "bounce app for fresh binder"
    APPPID=$(pidof $APP)
    [ -n "$APPPID" ] && kill "$APPPID"
    sleep 5
    start_app_and_wait
    input tap $TAP_X $TAP_Y
    sleep 5
    ;;
esac

H=$(mic_holder)
camera_up && CAM=up || CAM=down
log "FINAL mic=${H:-FREE} app_pid=$(pidof $APP) camera=$CAM"
log "=== bringup done ==="
