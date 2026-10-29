#!/bin/sh
# modem-qrtr-probe — capture the QRTR control plane while the modem boots.
#
# The modem asserts 40 s after it comes up, and rmtfs logs zero open requests,
# so the suspicion is that the modem never learns where rmtfs lives: our QRTR
# name service only broadcasts new-server announcements to nodes it has been
# told about via HELLO.  This records the control messages and the node table
# every second, synced to disk, so the interaction survives the crash.

LOG=/var/log/modem-qrtr.log
T=/sys/kernel/debug/tracing
RPROC=/sys/class/remoteproc/remoteproc1

say() { echo "$*" >> "$LOG"; sync; }

echo "=== $(date) qrtr probe ===" > "$LOG"
echo disabled > "$RPROC/recovery" 2>/dev/null

echo 1 > $T/events/qrtr_ns_message/enable 2>/dev/null
echo 1 > $T/events/qrtr_ns_service_announce_new/enable 2>/dev/null
echo 1 > $T/events/qcom_glink/enable 2>/dev/null
: > $T/trace

dmesg -C
say "starting modem"
echo start > "$RPROC/state"

i=0
while [ $i -lt 60 ]; do
	sleep 1
	st=$(cat "$RPROC/state" 2>/dev/null)
	# node ids only: cheap enough to run every second
	nodes=$(qrtr-lookup 2>/dev/null | awk 'NR>1{print $4}' | sort -n | tr '\n' ',')
	say "$(date +%H:%M:%S) state=$st nodes=$nodes"
	case "$st" in crashed|offline) say "left running"; break ;; esac
	i=$((i + 1))
done

say "--- qrtr control messages (type/name per event) ---"
grep -a "qrtr_ns_message" $T/trace | sed 's/.*type=/type=/' | sort | uniq -c | head -20 >> "$LOG"
say "--- raw hello/new-server lines ---"
grep -aE "hello|new-server|new-lookup" $T/trace | head -20 >> "$LOG"
say "--- glink mpss traffic (first 20) ---"
grep -a "mpss" $T/trace | head -20 >> "$LOG"
say "--- glink mpss counts ---"
say "mpss lines: $(grep -ac mpss $T/trace 2>/dev/null)"
say "=== end ==="
sync
