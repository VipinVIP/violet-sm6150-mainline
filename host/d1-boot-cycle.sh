#!/bin/bash
# One D1 boot-cycle measurement: reboot the phone, wait for the USB link, then
# record the boot-time DSI signature so the "black panel with backlight" fault
# can be counted across boots instead of guessed from a single sample.
#
# Usage: host/d1-boot-cycle.sh [label]
set -u

PHONE_USB=172.16.42.1
PHONE_WIFI=${PHONE_WIFI:-<lan-ip>}
IF_HINT=enp0s20f0u
label=${1:-cycle}

# The USB NCM link is physically flaky on this cable (enumeration drops out and
# takes the address with it), so probe WiFi first and keep USB as the fallback.
TARGET=""
link_up() {
	local i ifc
	for i in $(seq 1 40); do
		for t in "$PHONE_WIFI" "$PHONE_USB"; do
			ifc=$(ip -br link 2>/dev/null | awk -v h="$IF_HINT" '$1 ~ h {print $1; exit}')
			[ -n "$ifc" ] && sudo -n ip addr add 172.16.42.2/16 dev "$ifc" 2>/dev/null
			if timeout 5 ssh -o ConnectTimeout=4 -o StrictHostKeyChecking=no \
				user@"$t" 'echo UP' 2>/dev/null | grep -q UP; then
				TARGET=$t
				return 0
			fi
		done
		sleep 6
	done
	return 1
}

recover_panel() {
	# A fresh power-on cycle is the known recovery; end every test in a state
	# where the panel is enabled rather than left dark.
	timeout 25 ssh -o ConnectTimeout=6 user@"$TARGET" \
		'sudo -u user env XDG_RUNTIME_DIR=/run/user/10000 WAYLAND_DISPLAY=wayland-0 \
		 wlopm --off "*" >/dev/null 2>&1; sleep 1; \
		 sudo -u user env XDG_RUNTIME_DIR=/run/user/10000 WAYLAND_DISPLAY=wayland-0 \
		 wlopm --on "*" >/dev/null 2>&1' >/dev/null 2>&1
}

echo "=== $label: $(date -Iseconds) ==="
timeout 25 ssh -o ConnectTimeout=8 user@$PHONE_WIFI 'sudo reboot' >/dev/null 2>&1
sleep 20
if ! link_up; then
	echo "  RESULT: phone never came back on WiFi or USB"
	exit 1
fi
sleep 25   # let the session and the probe settle

timeout 30 ssh -o ConnectTimeout=8 user@"$TARGET" '
	u=$(cut -d. -f1 /proc/uptime)
	e=$(sudo dmesg | grep -c dsi_err_worker)
	s=$(sudo dmesg | grep -c "sw reset after FIFO")
	d=$(sudo dmesg | grep -c 0xdddd1019)
	st=$(sudo dmesg | grep -c "link clocks stalled")
	rc=$(sudo dmesg | grep -c "link clocks recovered")
	cs=$(sudo dmesg | grep -oE "DSIREG 0ae94120 [0-9a-f]+" | head -1 | awk "{print \$3}")
	ls=$(sudo dmesg | grep -oE "DSIREG 0ae940a8 [0-9a-f]+" | head -1 | awk "{print \$3}")
	echo "  uptime=${u}s dsi_err=$e sw_reset=$s fifo_0xdddd=$d stalled_msgs=$st recovered_msgs=$rc"
	echo "  clk_status(0x120)=${cs:-no-dump} lane_status(0xa8)=${ls:-no-dump}"
' 2>/dev/null | sed 's/^/ /'

recover_panel
echo "  panel power cycle issued (so the next observation is not left dark)"
