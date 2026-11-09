#!/bin/sh
# elogind system-sleep hook for violet.
# 1) hexagonrpcd (approach from pmaports MR 5400, google-sargo): a hexagonrpcd sitting in a FastRPC call while
#    the SoC sleeps makes the ADSP crash on resume (sensor_process / sns_sig_remote_).  Stop it before sleep and
#    start it after.  rc-service stop can hang (daemon blocked in a FastRPC ioctl): bound it, then SIGKILL.
# 2) USB gadget: with no cable attached dwc3_gadget_suspend() cannot soft-disconnect and returns -EAGAIN
#    ("dwc3_qcom_pm_suspend returns -11"), which aborts the whole suspend.  Unbind the UDC around sleep.
SVC=hexagonrpcd-adsp-sensorspd
G=/sys/kernel/config/usb_gadget/usb-signaller-developer/UDC
S=/run/violet-sleep-udc
case "$1" in
pre)
	timeout 5 rc-service "$SVC" stop >/dev/null 2>&1
	pkill -KILL -x hexagonrpcd 2>/dev/null
	[ -w "$G" ] && { cat "$G" > "$S"; echo "" > "$G"; }
	;;
post)
	[ -s "$S" ] && { cat "$S" > "$G"; rm -f "$S"; }
	timeout 20 rc-service "$SVC" zap >/dev/null 2>&1
	timeout 20 rc-service "$SVC" start >/dev/null 2>&1 &
	;;
esac
exit 0
