#!/bin/bash
# Wait for the phone to appear in fastboot (i.e. someone reseated the cable),
# flash the staged D1 image, reboot, then capture the link-clock sequence:
#   - the first power-on after boot (the one that leaves the panel black)
#   - a forced DPMS off/on (what the user's "two power presses" do)
# Writes everything to logs/displayboot-<date>/d1-flash.log.
#
# Usage: host/d1-flash-when-ready.sh [max_wait_s]
set -u

REPO=$HOME/violet-mainline
IMG=$REPO/boot-mainline.img
LOGDIR=$REPO/logs/displayboot-$(date +%F)
LOG=$LOGDIR/d1-flash.log
MAX=${1:-1800}

mkdir -p "$LOGDIR"
say() { echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }

[ -f "$IMG" ] || { say "FATAL: $IMG missing"; exit 1; }
say "waiting for fastboot (image $(stat -c %s "$IMG") bytes, built $(stat -c %y "$IMG"))"

waited=0
while [ "$waited" -lt "$MAX" ]; do
	D=$(timeout 6 fastboot devices 2>/dev/null | head -1)
	if [ -n "$D" ]; then
		say "fastboot appeared: $D"
		timeout 200 fastboot flash boot "$IMG" >>"$LOG" 2>&1
		rc=$?
		say "flash rc=$rc"
		[ "$rc" -ne 0 ] && { say "flash failed, leaving the phone in fastboot"; exit 1; }
		timeout 30 fastboot reboot >>"$LOG" 2>&1
		break
	fi
	sleep 10
	waited=$((waited + 10))
done
[ "$waited" -ge "$MAX" ] && { say "no fastboot after ${MAX}s - giving up"; exit 1; }

# --- wait for the system, then sample the link clocks -------------------------
TARGET=""
for i in $(seq 1 40); do
	for t in 172.16.42.1 <lan-ip>; do
		ifc=$(ip -br link 2>/dev/null | awk '/enp0s20f0u/{print $1; exit}')
		[ -n "$ifc" ] && sudo -n ip addr add 172.16.42.2/16 dev "$ifc" 2>/dev/null
		if timeout 5 ssh -o ConnectTimeout=4 -o StrictHostKeyChecking=no \
			user@"$t" 'echo UP' 2>/dev/null | grep -q UP; then
			TARGET=$t
			break 2
		fi
	done
	sleep 8
done
[ -z "$TARGET" ] && { say "phone never came back after flash"; exit 1; }
say "phone up via $TARGET"

sleep 20   # let phoc start so the first DRM modeset has happened

{
	echo "--- boot-time link clock sequence (first power-on) ---"
	ssh -o ConnectTimeout=8 user@"$TARGET" 'sudo dmesg | grep -E "link clocks|after video enable|DSIDBG enable_video|pll_unlocked|rcg didn|stalled|dsi_err|video done"'
	echo "--- forcing a DPMS off/on (what the two power presses do) ---"
	ssh -o ConnectTimeout=8 user@"$TARGET" 'sudo -u user env XDG_RUNTIME_DIR=/run/user/10000 WAYLAND_DISPLAY=wayland-0 wlopm --off "*"; sleep 2; sudo -u user env XDG_RUNTIME_DIR=/run/user/10000 WAYLAND_DISPLAY=wayland-0 wlopm --on "*"'
	sleep 6
	echo "--- link clock sequence after the power cycle ---"
	ssh -o ConnectTimeout=8 user@"$TARGET" 'sudo dmesg | grep -E "link clocks|after video enable|pll_unlocked"'
	echo "--- counters ---"
	ssh -o ConnectTimeout=8 user@"$TARGET" 'echo "dsi_err=$(sudo dmesg|grep -c dsi_err_worker) sw_reset=$(sudo dmesg|grep -c "sw reset") hangcheck=$(sudo dmesg|grep -c "hangcheck detected")"'
} >>"$LOG" 2>&1

say "capture complete -> $LOG"
