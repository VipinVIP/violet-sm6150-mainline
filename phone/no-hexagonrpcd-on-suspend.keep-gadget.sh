#!/bin/sh
# elogind system-sleep hook for violet — VARIANT B: leave the gadget bound.
#
# Why: variant A (patches/0035) unbinds the UDC before sleep and rebinds it in `post`.
# Measured 2026-11-02: with a host attached, the rebind fails
#   dwc3-qcom a600000.usb: failed to enable ep0out
# and the UDC stays "not attached" -> USB is dead until reboot (WiFi keeps working).
# dwc3_gadget_suspend() only returns -EAGAIN when *no cable* is attached (nothing to
# soft-disconnect), so the unbind is unnecessary whenever a host is present.  Keep the
# hexagonrpcd handling (ADSP crash on resume, pmaports MR 5400).
SVC=hexagonrpcd-adsp-sensorspd
G=/sys/kernel/config/usb_gadget/usb-signaller-developer/UDC
S=/run/violet-sleep-udc
STATE=/sys/class/udc/a600000.usb/state
case "$1" in
pre)
	timeout 5 rc-service "$SVC" stop >/dev/null 2>&1
	pkill -KILL -x hexagonrpcd 2>/dev/null
	# Only unbind when nothing is attached: then dwc3_gadget_suspend() has no link to
	# soft-disconnect and returns -EAGAIN, which aborts the whole system suspend.
	st=$(cat "$STATE" 2>/dev/null)
	echo "sleep-hook(pre): udc state=$st" > /dev/kmsg
	if [ "$st" = "not attached" ] && [ -w "$G" ]; then
		cat "$G" > "$S"
		echo "" > "$G"
		echo "sleep-hook(pre): unbound UDC (no host attached)" > /dev/kmsg
	fi
	;;
post)
	if [ -s "$S" ]; then
		cat "$S" > "$G"
		rm -f "$S"
		echo "sleep-hook(post): rebound UDC -> $(cat "$STATE" 2>/dev/null)" > /dev/kmsg
	fi
	timeout 20 rc-service "$SVC" zap >/dev/null 2>&1
	timeout 20 rc-service "$SVC" start >/dev/null 2>&1 &
	;;
esac
exit 0
