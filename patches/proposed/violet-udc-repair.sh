#!/bin/sh
# violet-udc-repair.sh - keep the USB gadget alive across suspend on the violet port.
#
# Measured 2026-11-02 on build #183: every s2idle resume leaves dwc3 unable to re-enable its
# control endpoint
#     dwc3-qcom a600000.usb: failed to enable ep0out
# and the UDC then reports "not attached" for the rest of the boot: USB is dead (WiFi keeps
# working).  Re-binding the gadget via configfs does nothing; un- and re-binding the
# dwc3-qcom platform device brings it back within a few seconds with no reboot.
#
# This is a workaround for the dwc3/dwc3-qcom resume bug, not a fix.  It runs as a service
# because the elogind hook only covers elogind-initiated suspends (anything writing
# /sys/power/state directly, e.g. a test or a crash tool, bypasses it).
#
# Logic: only repair on a configured -> not-attached transition.  With no cable attached the
# UDC is "not attached" the whole time and nothing is touched, so there is no rebind churn.
STATE=/sys/class/udc/a600000.usb/state
DRV=/sys/bus/platform/drivers/dwc3-qcom
DEV=a600000.usb
G=/sys/kernel/config/usb_gadget/usb-signaller-developer/UDC
ADSP=/sys/class/remoteproc/remoteproc0
SVC=hexagonrpcd-adsp-sensorspd

# Same transition is the resume signal for the ADSP: if hexagonrpcd was alive during sleep
# (i.e. the suspend did not come through elogind, so the sleep hook never stopped it), the
# ADSP firmware crashes on resume.  Measured 2026-11-02: remoteproc0 -> "crashed", then
# "can't lock rproc adsp: -4" / "Boot failed: -4" so it cannot be restarted from here; it
# needs a reboot.  Log it loudly rather than pretending it is fine.
recover_adsp() {
	st=$(cat "$ADSP/state" 2>/dev/null)
	[ "$st" = "running" ] && return 0
	echo "udc-repair: adsp state=$st after resume, trying start" > /dev/kmsg
	echo start > "$ADSP/state" 2>/dev/null
	sleep 3
	st2=$(cat "$ADSP/state" 2>/dev/null)
	echo "udc-repair: adsp state now=$st2" > /dev/kmsg
	if [ "$st2" = "running" ]; then
		rc-service "$SVC" restart >/dev/null 2>&1
	else
		echo "udc-repair: ADSP WEDGED - sensors/audio need a reboot" > /dev/kmsg
	fi
}

last=$(cat "$STATE" 2>/dev/null)
while :; do
	# Never touch the controller while the system is going down: at shutdown the gadget is
	# stopped, the UDC goes configured -> not attached, and an unbind/bind of dwc3-qcom in
	# the middle of OpenRC's shutdown could hang the kernel.  OpenRC keeps the current
	# runlevel in /run/openrc/softlevel.
	if [ "$(cat /run/openrc/softlevel 2>/dev/null)" = "shutdown" ]; then
		exit 0
	fi
	now=$(cat "$STATE" 2>/dev/null)
	if [ "$now" != "configured" ] && [ "$last" = "configured" ]; then
		# The first rebind often does not stick: it lands while the kernel is still
		# finishing the resume (measured 2026-11-02: service rebound at +0 s and the
		# controller was still "not attached" 3 s later; a second attempt 5 s in worked).
		# Retry a few times before giving up.
		try=0
		while [ $try -lt 4 ]; do
			try=$((try + 1))
			echo "udc-repair: state $last -> $now, re-binding $DEV (attempt $try)" > /dev/kmsg
			echo "$DEV" > "$DRV/unbind" 2>/dev/null
			sleep 1
			echo "$DEV" > "$DRV/bind" 2>/dev/null
			sleep 2
			# configfs keeps the UDC name, but re-assert it if the bind dropped it
			[ -s "$G" ] || { echo "$DEV" > "$G" 2>/dev/null; }
			now=$(cat "$STATE" 2>/dev/null)
			echo "udc-repair: after attempt $try state=$now udc_file=$(cat "$G" 2>/dev/null)" > /dev/kmsg
			[ "$now" = "configured" ] && break
			sleep 1
		done
		recover_adsp
	fi
	last=$now
	sleep 2
done
