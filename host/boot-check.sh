#!/bin/bash
# Wait for the phone to reach UPTIME seconds (default 200), then print one health line:
# sound card, SoundWire slaves, modem crashes, WiFi, GPU/DSI errors.
# Usage: host/boot-check.sh [uptime_s] [label]
set -u
UP=${1:-200}; LABEL=${2:-boot}
for i in $(seq 1 120); do
	ip -br link 2>/dev/null | grep -q enp0s20 && sudo -n ip addr add 172.16.42.2/16 dev "$(ip -br link | awk '/enp0s20/{print $1;exit}')" 2>/dev/null
	for t in <lan-ip> 172.16.42.1; do
		timeout 5 ssh -o ConnectTimeout=4 user@"$t" "test \$(cut -d. -f1 /proc/uptime) -ge $UP" </dev/null >/dev/null 2>&1 && { T=$t; break 2; }
	done
	sleep 5
done
[ -z "${T:-}" ] && { echo "$LABEL: phone never reached ${UP}s"; exit 1; }
echo "$T" > /tmp/claude-1000/phone_ip
timeout 40 ssh -o ConnectTimeout=6 user@"$T" 'k=$(uname -v | cut -c1-5); c=$(head -1 /proc/asound/cards | cut -c1-12); s=0; for d in /sys/bus/soundwire/devices/sdw:*; do [ "$(cat $d/status 2>/dev/null)" = Attached ] && s=$((s+1)); done; echo "'"$LABEL"': $k up=$(cut -d. -f1 /proc/uptime) card=[$c] sdw_attached=$s modem_crashes=$(sudo dmesg | grep -c "crash detected in modem") afe_err=$(sudo dmesg | grep -c "returned error = 0x16\|AFE failed") wifi=$(ip -br addr show wlan0 2>/dev/null | awk "{print \$2}") gpu_err=$(sudo dmesg | grep -ciE "hangcheck|gpu fault|failing submit|GX failed|RGMU fault") dsi_err=$(sudo dmesg | grep -c dsi_err_worker)"' </dev/null
