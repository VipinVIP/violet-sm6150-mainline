#!/bin/sh
# elogind system-sleep hook for violet (variant C — measured 2026-11-02).
#
# 1) hexagonrpcd: a hexagonrpcd inside a FastRPC call while the SoC sleeps makes the ADSP
#    crash on resume (pmaports MR 5400, google-sargo).  Stop it before sleep, start after.
#
# 2) USB gadget: two separate problems, both measured on build #183:
#    a. with *nothing* attached, dwc3_gadget_suspend() has no link to soft-disconnect and
#       returns -EAGAIN, which aborts the whole system suspend -> unbind the UDC in `pre`
#       when the UDC reports "not attached".
#    b. (fixed in the kernel since #185, patches/0039: dwc3-qcom now re-selects the UTMI clock on
#       resume; the old dwc3-qcom unbind/bind repair loop and violet-udc-repair are gone.)
#    Item a. is still a workaround for dwc3_gadget_suspend() with no host attached.
SVC=hexagonrpcd-adsp-sensorspd
G=/sys/kernel/config/usb_gadget/usb-signaller-developer/UDC
DRV=/sys/bus/platform/drivers/dwc3-qcom
DEV=a600000.usb
STATE=/sys/class/udc/$DEV/state
S=/run/violet-sleep-udc

log() { echo "sleep-hook($1): $2" > /dev/kmsg 2>/dev/null; }

case "$1" in
pre)
	timeout 5 rc-service "$SVC" stop >/dev/null 2>&1
	pkill -KILL -x hexagonrpcd 2>/dev/null
	st=$(cat "$STATE" 2>/dev/null)
	log pre "udc state=$st"
	if [ "$st" = "not attached" ] && [ -w "$G" ]; then
		cat "$G" > "$S"
		echo "" > "$G"
		log pre "unbound UDC (nothing attached)"
	fi
	;;
post)
	if [ -s "$S" ]; then
		cat "$S" > "$G"
		rm -f "$S"
	fi
	timeout 20 rc-service "$SVC" zap >/dev/null 2>&1
	timeout 20 rc-service "$SVC" start >/dev/null 2>&1 &
	;;
esac
exit 0
