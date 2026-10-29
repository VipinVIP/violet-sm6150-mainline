#!/bin/sh
# seq3 — packet-level QRTR capture for the modem edge, with the ftrace ring big enough
# to hold the whole exchange (the seq2 run lost the early AP->modem events to a wrap:
# the qcom_glink edge trace is extremely chatty). Only the two QRTR kprobes are on now.
#
# sockaddr_qrtr = { u16 sq_family; u32 sq_node; u32 sq_port } -> node at +4, port at +8
# (seq2 read +0/+4 and got family=42=AF_QIPCRTR and the node, which is how we know).
LOG=/var/log/seq3.log
T=/sys/kernel/debug/tracing
[ -d "$T/events" ] || T=/sys/kernel/tracing
RPROC=/sys/class/remoteproc/remoteproc1
say() { echo "$*" >> "$LOG"; sync; }

echo "=== $(date) seq3 ===" > "$LOG"
cd "$T" || exit 0
echo 0 > tracing_on
echo 1 > events/qcom_glink/enable 2>/dev/null
echo 0 > events/qcom_glink/enable 2>/dev/null
echo 0 > events/qrtr_ns_message/enable 2>/dev/null
echo 0 > events/qrtr_ns_service_announce_new/enable 2>/dev/null
: > trace
echo > kprobe_events
echo 'p:qrtrrx qrtr_endpoint_post len=%x2:s32 ty=+4(%x1):u32 sn=+8(%x1):u32 sp=+12(%x1):u32 cr=+16(%x1):u32 sz=+20(%x1):u32 dn=+24(%x1):u32 dp=+28(%x1):u32' >> kprobe_events
echo 'p:qrtrtx qrtr_node_enqueue ty=%x2:s32 fn=+4(%x3):u32 fp=+8(%x3):u32 dn=+4(%x4):u32 dp=+8(%x4):u32' >> kprobe_events
echo 'r:qrtrsr qrtr_sendmsg rc=$retval:s32' >> kprobe_events
echo 'p:qrtrpost qrtr_endpoint_post len=%x2:s32' >> kprobe_events
for e in qrtrrx qrtrtx qrtrsr; do echo 1 > events/kprobes/$e/enable 2>/dev/null; done
echo 32768 > buffer_size_kb
echo 1 > tracing_on
say "buf=$(cat buffer_size_kb) rx=$(cat events/kprobes/qrtrrx/enable) tx=$(cat events/kprobes/qrtrtx/enable) on=$(cat tracing_on)"

echo stop > $RPROC/state 2>/dev/null
i=0; while [ $i -lt 20 ]; do sleep 1; [ "$(cat $RPROC/state 2>/dev/null)" = offline ] && break; i=$((i+1)); done
echo disabled > $RPROC/recovery 2>/dev/null
dmesg -C
say "START state=$(cat $RPROC/state) t_stop=${i}s"
echo start > $RPROC/state
i=0
while [ $i -lt 55 ]; do
	sleep 1
	st=$(cat $RPROC/state 2>/dev/null)
	case "$st" in crashed|offline) say "LEFT RUNNING t=${i}s"; break ;; esac
	i=$((i+1))
done
echo 0 > tracing_on
say "lost_overruns=$(grep -c OVERRUN trace 2>/dev/null) trace_kb=$(du -k trace | cut -f1)"

say "--- modem->AP: sn!=5 (i.e. not the ADSP) ---"
grep -a 'qrtrrx:' trace | grep -av ' sn=5 ' | sed 's/.*qrtrrx: //' >> "$LOG"
say "--- modem->AP: all ty=2 (hello) or ty=4 (new-server), any node ---"
grep -a 'qrtrrx:' trace | grep -aE ' ty=2 | ty=4 ' | sed 's/.*qrtrrx: //' >> "$LOG"
say "--- counts by src node ---"
grep -a 'qrtrrx:' trace | sed 's/.* sn=/sn=/' | awk '{print $1}' | sort | uniq -c >> "$LOG"
say "--- AP->modem: every enqueue whose destination is not the ADSP (dn!=5) ---"
grep -a 'qrtrtx:' trace | grep -av ' dn=5 ' | sed 's/.*qrtrtx: //' >> "$LOG"
say "--- counts by destination node ---"
grep -a 'qrtrtx:' trace | sed 's/.* dn=/dn=/' | awk '{print $1}' | sort | uniq -c >> "$LOG"
say "--- sendmsg rc histogram ---"
grep -a 'qrtrsr:' trace | sed 's/.*qrtrsr: //' | sort | uniq -c >> "$LOG"
say "--- qrtr-lookup ---"
qrtr-lookup 2>&1 | head -25 >> "$LOG"
say "--- dmesg ---"
dmesg | grep -aiE 'modem|mpss|qrtr|glink|fatal|qcom_smd|invalid' | tail -25 >> "$LOG"
say "=== end ==="
sync
