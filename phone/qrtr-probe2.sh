#!/bin/sh
# qrtr-probe2 — capture the *packets* of the modem's QRTR session, both directions.
#
# Why: the saved glink trace shows the modem's IPCRTR channel opens, intents flow
# both ways, and the modem's HELLO (52 B, src_node 0) reaches our in-kernel name
# service - but nothing else ever arrives from it, and it asserts 40 s later.
# The glink tracepoints carry sizes, not payloads, so install kprobes on
#   qrtr_endpoint_post()  (every modem->AP packet, with the v1 header fields)
#   qrtr_node_enqueue()   (every AP->modem packet: type + destination)
# and keep the whole glink + qrtr_ns trace on disk. No kernel change needed.
#
# Everything is appended and synced so it survives the modem's crash.

LOG=/var/log/modseq.log
T=/sys/kernel/debug/tracing
[ -d "$T" ] || T=/sys/kernel/tracing
RPROC=/sys/class/remoteproc/remoteproc1

say() { echo "$*" >> "$LOG"; sync; }

echo "=== $(date) seq probe (kernel $(uname -r)) ===" > "$LOG"

# ---- 0. services the modem needs -------------------------------------------
rc-service rmtfs status >/dev/null 2>&1 || rc-service rmtfs start >/dev/null 2>&1
sleep 1
say "rmtfs: $(pgrep -a rmtfs | head -1)"
say "tqftpserv: $(pgrep -a tqftpserv | head -1)"
say "pd-mapper: $(pgrep -a pd_mapper | head -1)"
say "modem state: $(cat $RPROC/state 2>/dev/null) recovery=$(cat $RPROC/recovery 2>/dev/null)"

# ---- 1. kprobes: full QRTR header of every packet, both directions ----------
cd "$T" || exit 0
echo 0 > tracing_on 2>/dev/null
: > trace 2>/dev/null
# modem -> AP: qrtr_endpoint_post(ep, data, len)   x0=ep x1=data x2=len
echo 'p:qrtrrx qrtr_endpoint_post len=%x2:s32 ver=+0(%x1):u32 ty=+4(%x1):u32 sn=+8(%x1):u32 sp=+12(%x1):u32 sz=+20(%x1):u32 dn=+24(%x1):u32 dp=+28(%x1):u32' \
	>> kprobe_events 2>>"$LOG"
# AP -> modem: qrtr_node_enqueue(node, skb, type, from, to)  x3=from x4=to
echo 'p:qrtrtx qrtr_node_enqueue ty=%x2:s32 fn=+0(%x3):u32 fp=+4(%x3):u32 dn=+0(%x4):u32 dp=+4(%x4):u32' \
	>> kprobe_events 2>>"$LOG"
# and what came back for it (-ECONNRESET / -ENODEV hide a lot)
echo 'r:qrtrtxr qrtr_sendmsg rc=$retval:s32' >> kprobe_events 2>>"$LOG"

for e in qrtrrx qrtrtx qrtrtxr qcom_glink qrtr_ns_message; do
	echo 1 > "events/$e/enable" 2>/dev/null
done
echo 1 > events/qrtrrx/enable 2>/dev/null
echo 1 > events/qrtrtx/enable 2>/dev/null
echo 1 > events/qrtrtxr/enable 2>/dev/null
say "kprobes: $(wc -l < kprobe_events 2>/dev/null) lines, rx=$(cat events/qrtrrx/enable 2>/dev/null) tx=$(cat events/qrtrtx/enable 2>/dev/null)"
echo 1 > tracing_on

# ---- 2. start the modem and watch it --------------------------------------
say "--- qrtr before ---"
qrtr-lookup 2>&1 | head -20 >> "$LOG"

[ "$(cat $RPROC/state 2>/dev/null)" = "running" ] && { echo stop > $RPROC/state; sleep 2; }
echo disabled > $RPROC/recovery 2>/dev/null
dmesg -C
say "START"
echo start > $RPROC/state

i=0
while [ $i -lt 70 ]; do
	sleep 1
	st=$(cat $RPROC/state 2>/dev/null)
	[ $((i % 5)) -eq 0 ] && say "t=${i}s state=$st rmtfs_reqs=$(grep -c . /var/log/rmtfs.log 2>/dev/null)"
	case "$st" in crashed|offline) say "LEFT RUNNING t=${i}s"; break ;; esac
	i=$((i + 1))
done
echo 0 > tracing_on

# ---- 3. summarise ---------------------------------------------------------
say "--- qrtr after ---"
qrtr-lookup 2>&1 | head -30 >> "$LOG"

say "--- AP->modem (qrtr_node_enqueue) ---"
grep -a qrtrtx: trace | sed 's/.*qrtrtx: //' | sort | uniq -c | sort -rn | head -25 >> "$LOG"

say "--- AP->modem sendmsg results ---"
grep -a qrtrtxr: trace | sed 's/.*qrtrtxr: //' | sort | uniq -c | sort -rn | head >> "$LOG"

say "--- modem->AP headers (qrtr_endpoint_post), all lines ---"
grep -a 'qrtrrx:' trace | sed 's/.*qrtrrx: //' >> "$LOG"

say "--- qrtr ns messages ---"
grep -a 'qrtr_ns_message:' trace | sed 's/.*qrtr_ns_message: //' | sort | uniq -c | sort -rn | head -15 >> "$LOG"

say "--- glink mpss (first 60) ---"
grep -a 'mpss' trace | sed 's/.*: qcom_glink/glink/' | head -60 >> "$LOG"

say "--- dmesg (modem/qrtr/glink) ---"
dmesg | grep -aiE 'modem|mpss|qrtr|glink|rmtfs|fatal|crash' | tail -40 >> "$LOG"
say "=== end ==="
sync
