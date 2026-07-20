#!/bin/bash
# find_robot.sh — locate the Timo robot on the LAN and repoint local configs at it.
#
# Discovery order:
#   1. adb (if the robot is adb-connected, its wlan0 IP is authoritative)
#   2. ARP lookup by known MAC after a ping sweep
#   3. Port-signature scan: the robot is the only host with WS ports 8081+8082 open
#
# On success, updates:
#   - spine/.env                 ROBOT_IP=<ip>
#   - app .. settings_provider.dart / spine_service.dart   hardcoded robot IPs
#   - robot pref spine_base_url -> this Mac's IP (debug build, via adb run-as)
#
# Usage: ./scripts/find_robot.sh [--dry-run]

set -euo pipefail

ROBOT_MAC="74:24:ca:9e:83:de"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SUBNET_IF="en0"
DRY_RUN="${1:-}"

mac_ip="$(ipconfig getifaddr "$SUBNET_IF")"
subnet="${mac_ip%.*}"

find_via_adb() {
  adb devices | awk 'NR>1 && $2=="device" {print $1}' | head -1 | while read -r serial; do
    adb -s "$serial" shell "ip addr show wlan0" 2>/dev/null \
      | awk '/inet /{sub(/\/.*/,"",$2); print $2}'
  done
}

ping_sweep() {
  for i in $(seq 1 254); do ping -c1 -W1 "$subnet.$i" >/dev/null 2>&1 & done
  wait
}

find_via_mac() {
  arp -a -i "$SUBNET_IF" | awk -v mac="$ROBOT_MAC" 'index($0, mac) {gsub(/[()]/,"",$2); print $2}'
}

find_via_ports() {
  for ip in $(arp -a -i "$SUBNET_IF" | grep -v incomplete | awk '{gsub(/[()]/,"",$2); print $2}'); do
    [ "$ip" = "$mac_ip" ] && continue
    if nc -z -G 1 "$ip" 8081 2>/dev/null && nc -z -G 1 "$ip" 8082 2>/dev/null; then
      echo "$ip"; return
    fi
  done
}

echo "Mac IP: $mac_ip (subnet $subnet.0/24)"
echo "Looking for robot..."

robot_ip="$(find_via_adb || true)"
[ -n "$robot_ip" ] && echo "  found via adb: $robot_ip"

if [ -z "$robot_ip" ]; then
  ping_sweep
  robot_ip="$(find_via_mac || true)"
  [ -n "$robot_ip" ] && echo "  found via MAC $ROBOT_MAC: $robot_ip"
fi

if [ -z "$robot_ip" ]; then
  robot_ip="$(find_via_ports || true)"
  [ -n "$robot_ip" ] && echo "  found via port signature (8081+8082): $robot_ip"
fi

if [ -z "$robot_ip" ]; then
  echo "✗ Robot not found on $subnet.0/24 — is it powered on and on Wi-Fi?" >&2
  exit 1
fi

echo "✓ Robot at $robot_ip"
[ "$DRY_RUN" = "--dry-run" ] && exit 0

ipv4='[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
sed -i '' -E "s/^ROBOT_IP=.*/ROBOT_IP=$robot_ip/" "$REPO/spine/.env"
sed -i '' -E "s/$ipv4/$robot_ip/g" \
  "$REPO/app/lib/features/settings/providers/settings_provider.dart" \
  "$REPO/app/lib/services/spine/spine_service.dart"
echo "✓ Updated spine/.env + app hardcoded IPs -> $robot_ip"

serial="$(adb devices | awk 'NR>1 && $2=="device" {print $1}' | head -1)"
if [ -n "$serial" ]; then
  prefs="/data/data/com.mikee.robotapp/shared_prefs/FlutterSharedPreferences.xml"
  adb -s "$serial" shell "run-as com.mikee.robotapp sed -i -E \
    's|<string name=\"flutter.spine_base_url\">http://[^<]*</string>|<string name=\"flutter.spine_base_url\">http://$mac_ip:4000</string>|' $prefs" \
    && echo "✓ Robot pref spine_base_url -> http://$mac_ip:4000 (restart the Mikee app on the robot)"
else
  echo "⚠ adb not connected — robot's spine_base_url pref NOT updated (set to http://$mac_ip:4000 in the robot app's settings screen)"
fi

echo "Done. Restart spine (or 'touch spine/src/index.ts' if tsx watch is running) and hot-restart the admin app."
