#!/bin/sh
# modem-pdtest — one clean, self-contained modem test after the PD-mapper fix.
#
# Handles the stop-then-start dance the remoteproc state machine requires (a
# "start" while the modem is still crashed is rejected and leaves it offline,
# which is what made the last attempt a no-op).
#
# Everything is synced per line so the evidence survives the USB gadget dying.

LOG=/var/log/modem-pdtest.log
RPROC=/sys/class/remoteproc/remoteproc1

say() { echo "$*" >> "$LOG"; sync; }

echo "=== $(date) pdtest ===" > "$LOG"
say "kernel=$(uname -r) recovery=$(cat $RPROC/recovery 2>/dev/null) state=$(cat $RPROC/state 2>/dev/null)"

# 0. confirm the live module has the new modem root entry
say "--- pd-mapper table check (expect msm/modem/root_pd / 180 for tms/pdr_enabled) ---"
insmod /var/tmp/pd-trigger.ko 2>/dev/null || true
sleep 4
dmesg | grep -aE "PDM: found|PDM: service" | tail -6 >> "$LOG"
rmmod pd_trigger 2>/dev/null || true

# 1. rmtfs must be serving before the modem starts
rc-service rmtfs status >/dev/null 2>&1 || rc-service rmtfs start >> "$LOG" 2>&1
sleep 1
say "rmtfs pid=$(pidof rmtfs)"

# 2. clean stop first, then start - always
echo stop > "$RPROC/state" 2>/dev/null
i=0
while [ $i -lt 20 ]; do
	sleep 1
	st=$(cat "$RPROC/state" 2>/dev/null)
	[ "$st" = "offline" ] && break
	i=$((i + 1))
done
say "after stop: state=$(cat $RPROC/state 2>/dev/null)"

dmesg -C
say "starting modem"
echo start > "$RPROC/state"
sleep 1
say "start rc=$? state=$(cat $RPROC/state 2>/dev/null)"

# 3. sample for 75 s - past the 40 s watchdog window
i=0
while [ $i -lt 75 ]; do
	sleep 1
	st=$(cat "$RPROC/state" 2>/dev/null)
	svcs=$(qrtr-lookup 2>/dev/null | awk 'NR>1 && $4!=5 && $4!=1 {print $1}' | tr '\n' ',')
	[ $((i % 5)) -eq 0 ] && say "$(date +%H:%M:%S) t=${i}s state=$st modem_svcs=[$svcs]"
	case "$st" in crashed|offline) say "$(date +%H:%M:%S) LEFT RUNNING at t=${i}s"; break ;; esac
	i=$((i + 1))
done

say "--- qrtr ---"
qrtr-lookup >> "$LOG" 2>&1
say "--- pd-mapper / qrtr / crash dmesg ---"
dmesg | grep -aiE "PDM:|PDR:|fatal|crash|modem|wlansvc|wlfw" | tail -20 >> "$LOG"
say "--- rmtfs requests ---"
logread 2>/dev/null | grep -aiE "rmtfs|storage" | tail -8 >> "$LOG"
say "=== end ==="
sync
