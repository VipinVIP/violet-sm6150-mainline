#!/bin/sh
# modem-crash-probe — start the modem once and persist everything to disk.
#
# The modem's fatal error takes the USB gadget down with it, and a manual power
# cycle loses anything still sitting in the page cache.  So every sample is
# appended AND synced, and dmesg is snapshotted every second: whatever happened
# in the final second before the system stops writing ends up on disk.

LOG=/var/log/modem-crash.log
DMESG_SNAP=/var/log/modem-crash-dmesg.log
RPROC=/sys/class/remoteproc/remoteproc1

say() {
	echo "$*" >> "$LOG"
	sync
}

echo "=== $(date) probe start ===" > "$LOG"
say "kernel: $(uname -r)"
say "recovery before: $(cat $RPROC/recovery 2>/dev/null)"

# One crash = one datapoint, instead of a restart loop hammering AOSS.
if [ -w "$RPROC/recovery" ]; then
	echo disabled > "$RPROC/recovery"
	say "recovery disabled"
fi

dmesg -C
: > "$DMESG_SNAP"
sync
say "starting modem"
echo start > "$RPROC/state"

i=0
while [ $i -lt 150 ]; do
	sleep 1
	st=$(cat "$RPROC/state" 2>/dev/null)
	dmesg >> "$DMESG_SNAP"
	sync
	say "$(date +%H:%M:%S) state=$st last=$(dmesg | tail -1 | cut -c1-110)"
	case "$st" in
	crashed|offline) say "state left running"; break ;;
	esac
	i=$((i + 1))
done

say "--- qrtr ---"
qrtr-lookup >> "$LOG" 2>&1
say "--- crash-relevant dmesg ---"
dmesg | grep -aiE "modem|mpss|crash|fatal|q6v5|smmu|iommu|timeout|AFE|qrtr|glink" >> "$LOG" 2>&1
say "=== probe end ==="
sync
