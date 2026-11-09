#!/bin/sh
# seq2 — same capture as 91-qrtr-probe.start but with the kprobe enable paths fixed
# (dynamic kprobe events live under events/kprobes/<name>/enable, not events/<name>/).
# Runs on the live mainline system: no reboot, just a modem stop/start.
LOG=/var/log/seq2.log
T=/sys/kernel/debug/tracing
[ -d "$T/events" ] || T=/sys/kernel/tracing
RPROC=/sys/class/remoteproc/remoteproc1
say() { echo "$*" >> "$LOG"; sync; }

echo "=== $(date) seq2 ===" > "$LOG"
rc-service rmtfs status >/dev/null 2>&1 || rc-service rmtfs start >/dev/null 2>&1
say "rmtfs=$(pgrep -a rmtfs|head -1) tqftp=$(pgrep tqftpserv|head -1)"

cd "$T" || exit 0
echo 0 > tracing_on
: > trace
echo > kprobe_events
# modem -> AP : qrtr_endpoint_post(ep, data, len)      x0=ep x1=data x2=len
echo 'p:qrtrrx qrtr_endpoint_post len=%x2:s32 v=+0(%x1):u32 ty=+4(%x1):u32 sn=+8(%x1):u32 sp=+12(%x1):u32 sz=+20(%x1):u32 dn=+24(%x1):u32 dp=+28(%x1):u32' >> kprobe_events
# AP -> modem : qrtr_node_enqueue(node, skb, type, from, to)   x3=from x4=to
echo 'p:qrtrtx qrtr_node_enqueue ty=%x2:s32 fn=+0(%x3):u32 fp=+4(%x3):u32 dn=+0(%x4):u32 dp=+4(%x4):u32' >> kprobe_events
echo 'r:qrtrsr qrtr_sendmsg rc=$retval:s32' >> kprobe_events
say "probes: $(cat kprobe_events | tr '\n' '|')"
for e in qrtrrx qrtrtx qrtrsr; do echo 1 > events/kprobes/$e/enable 2>/dev/null; done
echo 1 > events/qcom_glink/enable 2>/dev/null
echo 1 > events/qrtr_ns_message/enable 2>/dev/null
say "enabled: rx=$(cat events/kprobes/qrtrrx/enable 2>/dev/null) tx=$(cat events/kprobes/qrtrtx/enable 2>/dev/null) sr=$(cat events/kprobes/qrtrsr/enable 2>/dev/null) glink=$(cat events/qcom_glink/enable 2>/dev/null)"
echo 1 > tracing_on

say "--- stop/start modem ---"
echo stop > $RPROC/state 2>/dev/null
i=0; while [ $i -lt 20 ]; do sleep 1; [ "$(cat $RPROC/state 2>/dev/null)" = offline ] && break; i=$((i+1)); done
say "after stop: $(cat $RPROC/state) t=${i}s"
echo disabled > $RPROC/recovery 2>/dev/null
dmesg -C
echo start > $RPROC/state
i=0
while [ $i -lt 60 ]; do
	sleep 1
	st=$(cat $RPROC/state 2>/dev/null)
	[ $((i % 10)) -eq 0 ] && say "t=${i}s state=$st"
	case "$st" in crashed|offline) say "LEFT RUNNING t=${i}s"; break ;; esac
	i=$((i + 1))
done
echo 0 > tracing_on

say "--- modem->AP: every packet (v=type srcN:port -> dstN:port size) ---"
grep -a 'qrtrrx:' trace | sed 's/.*qrtrrx: //' >> "$LOG"
say "--- AP->modem: every enqueue ---"
grep -a 'qrtrtx:' trace | sed 's/.*qrtrtx: //' >> "$LOG"
say "--- sendmsg results ---"
grep -a 'qrtrsr:' trace | sed 's/.*qrtrsr: //' | sort | uniq -c >> "$LOG"
say "--- ns messages ---"
grep -a 'qrtr_ns_message:' trace | sed 's/.*qrtr_ns_message: //' | sort | uniq -c >> "$LOG"
say "--- glink mpss tail ---"
grep -a 'mpss' trace | sed 's/.*: qcom_glink/glink/' | tail -25 >> "$LOG"
say "--- qrtr-lookup ---"
qrtr-lookup 2>&1 | head -25 >> "$LOG"
say "--- dmesg ---"
dmesg | grep -aiE 'modem|mpss|qrtr|glink|fatal|rmtfs|qcom_smd' | tail -25 >> "$LOG"
say "=== end ==="
sync
