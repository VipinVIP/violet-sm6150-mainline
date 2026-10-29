#!/bin/sh
# qrtr-probe3 — WHY does the modem's IPCRTR data stop inside glink?
#
# seq2/seq3 measured: on the modem edge glink completes VERSION/OPEN/OPEN_ACK/INTENT and the
# modem's 52-byte QRTR packet arrives as TX_DATA, yet qrtr_endpoint_post() is never entered for
# it (101/101 samples are the ADSP, sn=5). In qcom_glink_rx_data() there are exactly three
# ways to lose it:
#   1. idr_find(&glink->rcids, rcid) fails   -> dev_dbg "Data on non-existing channel"   (silent)
#   2. idr_find(&channel->liids, liid) fails -> dev_err "invalid intent id received"     (visible, absent)
#   3. channel->ept.cb == NULL               -> NO message at all                       (silent)
# So: turn on dynamic debug (makes 1 visible), kprobe the rpmsg callback (2 vs 3: if rx_data
# ran but the callback never did, it is 3), and dump the rpmsg device list while the modem is up.
#
# ONE modem start only: after 3-4 starts in a boot the SoC resets itself.
LOG=/var/log/probe3.log
T=/sys/kernel/debug/tracing
[ -d "$T/events" ] || T=/sys/kernel/tracing
RPROC=/sys/class/remoteproc/remoteproc1
say() { echo "$*" >> "$LOG"; sync; }

echo "=== $(date) probe3 (kernel $(uname -r)) ===" > "$LOG"
mount -t debugfs none /sys/kernel/debug 2>/dev/null

# ---- dynamic debug: the silent glink/rpmsg paths ---------------------------
DD=/sys/kernel/debug/dynamic_debug/control
for f in "file drivers/rpmsg/*" "file net/qrtr/*" "file kernel/dma/*"; do
	echo "$f +p" >> $DD 2>/dev/null
done
say "dd enabled files: $(grep -c '=p' $DD 2>/dev/null)"

# ---- kprobes ---------------------------------------------------------------
cd "$T" || exit 0
echo 0 > tracing_on
: > trace
echo > kprobe_events
echo 'p:qrtrrx qrtr_endpoint_post len=%x2:s32 sn=+8(%x1):u32 ty=+4(%x1):u32' >> kprobe_events
echo 'p:smdcb qcom_smd_qrtr_callback len=%x2:s32' >> kprobe_events
echo 'p:rxdata qcom_glink_rx_data' >> kprobe_events
for e in qrtrrx smdcb rxdata; do echo 1 > events/kprobes/$e/enable 2>/dev/null; done
echo 1 > events/qrtr/qrtr_ns_message/enable 2>/dev/null
echo 1 > events/qcom_glink/enable 2>/dev/null
say "ns_event=$(cat events/qrtr/qrtr_ns_message/enable 2>/dev/null) glink_event=$(cat events/qcom_glink/enable 2>/dev/null)"
echo 32768 > buffer_size_kb
echo 1 > tracing_on
say "probes=$(cat kprobe_events | tr '\n' '|')"

# ---- rpmsg/QRTR device inventory, before ------------------------------------
inv() {
	echo "--- $1: rpmsg devices ---"
	for d in /sys/bus/rpmsg/devices/*; do
		[ -e "$d" ] || continue
		n=$(basename "$d")
		drv=$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)
		chn=$(cat "$d/name" 2>/dev/null)
		echo "  $n  name=$chn driver=${drv:-NONE}"
	done
	echo "--- $1: /dev/rpmsg* and ctrl ---"
	ls -l /dev/rpmsg* 2>/dev/null | sed 's/^/  /'
	echo "--- $1: rpmsg-ctrl ---"
	for c in /sys/class/rpmsg-ctrl/*; do [ -e "$c" ] && echo "  $(basename $(dirname $c))/$(basename $c)"; done
	ls -l /dev/rpmsg_ctrl* 2>/dev/null | sed 's/^/  /'
	echo "--- $1: glink channels (debugfs) ---"
	cat /sys/kernel/debug/rpmsg*/ 2>/dev/null | head -5
}
inv before >> "$LOG"

# ---- one modem start -------------------------------------------------------
rc-service rmtfs status >/dev/null 2>&1 || rc-service rmtfs start >/dev/null 2>&1
say "rmtfs=$(pgrep -a rmtfs|head -1) tqftp=$(pgrep tqftpserv|head -1)"
echo disabled > $RPROC/recovery 2>/dev/null
dmesg -C
say "START (state=$(cat $RPROC/state))"
echo start > $RPROC/state

i=0
while [ $i -lt 45 ]; do
	sleep 1
	st=$(cat $RPROC/state 2>/dev/null)
	[ $((i % 10)) -eq 0 ] && say "t=${i}s state=$st rpmsg_devs=$(ls /sys/bus/rpmsg/devices/ 2>/dev/null | wc -l)"
	case "$st" in crashed|offline) say "LEFT RUNNING t=${i}s"; break ;; esac
	i=$((i+1))
done
echo 0 > tracing_on
inv during >> "$LOG"

# ---- what the kernel said --------------------------------------------------
say "--- dmesg: glink / rpmsg / qrtr / modem (dev_dbg included) ---"
dmesg | grep -aiE 'glink|rpmsg|qrtr|modem|non-existing|intent|invalid|channel|ipcrouter|dropping|hello' | tail -120 >> "$LOG"

say "--- counts: rx_data / smd callback / qrtr_endpoint_post ---"
say "qcom_glink_rx_data:      $(grep -ac 'rxdata:' trace)"
say "qcom_smd_qrtr_callback:  $(grep -ac 'smdcb:' trace)"
say "qrtr_endpoint_post:      $(grep -ac 'qrtrrx:' trace)  (by src node: $(grep -a 'qrtrrx:' trace | sed 's/.* sn=/sn=/' | awk '{print $1}' | sort | uniq -c | tr '\n' ' '))"
say "--- smdcb lines ---"
grep -a 'smdcb:' trace | sed 's/.*smdcb: //' | head -30 >> "$LOG"
say "--- qrtrrx lines (all) ---"
grep -a 'qrtrrx:' trace | sed 's/.*qrtrrx: //' | head -30 >> "$LOG"
say "--- ns messages ---"
grep -a 'qrtr_ns_message:' trace | sed 's/.*qrtr_ns_message: //' | sort | uniq -c >> "$LOG"
say "--- qrtr-lookup ---"
qrtr-lookup 2>&1 | head -20 >> "$LOG"
say "=== end ==="
sync
