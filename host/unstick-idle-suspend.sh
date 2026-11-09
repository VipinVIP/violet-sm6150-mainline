#!/usr/bin/env bash
# unstick-idle-suspend.sh - grab the phone in any window where ssh answers and undo the
# 60 s idle-suspend setting that keeps putting it back to sleep.
#
# Why: sleep-inactive-{battery,ac}-type were set to 'suspend' with a 60 s timeout for the
# suspend test.  The value lives in the user's dconf and survives reboots, and the phone has
# no remote wake source (gadget UDC is down while suspended, no WoWLAN), so every boot
# suspends ~60 s in - before sshd is even listening - and then sits there until a human
# presses power.  This script watches both transports and fires the fix the moment one
# answers, so all the human has to do is keep the phone awake for a minute.
#
# Also installs the guarded violet-udc-repair (the build on the phone still has the version
# that can unbind dwc3 during shutdown).
#
# Usage: unstick-idle-suspend.sh [rounds]   (default 400 rounds x 3 s ~= 20 min)
set -uo pipefail
ROUNDS=${1:-400}
ROOT=/home/vipi/violet-mainline
SSHOPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3
         -o LogLevel=ERROR -o ControlPath=none)
FIX='
B=$(sudo -n sh -c "tr \"\\0\" \"\\n\" < /proc/$(pgrep -x phosh | head -1)/environ" 2>/dev/null | grep DBUS_SESSION_BUS_ADDRESS | cut -d= -f2-)
export DBUS_SESSION_BUS_ADDRESS="$B" XDG_RUNTIME_DIR=/run/user/10000 HOME=/home/user
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type nothing
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
echo "STUCK-FIXED battery=$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type) ac=$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type)"'

for i in $(seq 1 "$ROUNDS"); do
	# --- USB
	for c in /sys/class/net/enp0s20f0u*; do
		[ -e "$c" ] || continue
		ifc=$(basename "$c")
		sudo -n nmcli dev set "$ifc" managed no >/dev/null 2>&1
		sudo -n ip addr replace 172.16.42.2/16 dev "$ifc" >/dev/null 2>&1
		sudo -n ip link set "$ifc" up >/dev/null 2>&1
		if out=$(timeout 20 ssh "${SSHOPTS[@]}" user@172.16.42.1 "$FIX" 2>&1); then
			echo "== $(date +%T) fixed over USB: $out"
			timeout 30 ssh "${SSHOPTS[@]}" user@172.16.42.1 \
				'sudo -n tee /usr/local/bin/violet-udc-repair.sh >/dev/null' \
				< "$ROOT/phone/violet-udc-repair.sh" >/dev/null 2>&1 && echo "   guarded udc-repair installed"
			exit 0
		fi
	done
	# --- WiFi
	if ping -c1 -W1 <lan-ip> >/dev/null 2>&1; then
		if out=$(timeout 20 ssh "${SSHOPTS[@]}" user@<lan-ip> "$FIX" 2>&1); then
			echo "== $(date +%T) fixed over WiFi: $out"
			timeout 30 ssh "${SSHOPTS[@]}" user@<lan-ip> \
				'sudo -n tee /usr/local/bin/violet-udc-repair.sh >/dev/null' \
				< "$ROOT/phone/violet-udc-repair.sh" >/dev/null 2>&1 && echo "   guarded udc-repair installed"
			exit 0
		fi
	fi
	sleep 3
done
echo "== no shell in $((ROUNDS * 3)) s - phone still asleep"
exit 1
