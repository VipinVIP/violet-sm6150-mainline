#!/bin/bash
# G1 stress without unlocking: alternate lock-screen swipes (clock <-> keypad)
# so phosh animates, the GPU wakes, renders, and runtime-suspends again.
# Never touches the keypad digits. Prints GPU power counters every 20 rounds.
#
# Usage: host/g1-swipe-stress.sh [rounds] [phone]
set -u
N=${1:-200}
PHONE=${2:-<lan-ip>}

counters() {
	timeout 15 ssh -o ConnectTimeout=6 user@"$PHONE" 'echo "$(date +%T) up=$(cut -d. -f1 /proc/uptime)s resumes=$(sudo dmesg | grep -c "GX after GPUSTART") collapse_fail=$(sudo dmesg | grep -c "did not collapse") gx_fail=$(sudo dmesg | grep -c "GX failed") hang=$(sudo dmesg | grep -c "hangcheck detected")"' </dev/null
}

counters
for i in $(seq 1 "$N"); do
	timeout 15 ssh -o ConnectTimeout=6 user@"$PHONE" \
		'sudo python3 /var/tmp/tap.py 540 2250 540 1000; sleep 1.2; sudo python3 /var/tmp/tap.py 540 600 540 2000' \
		</dev/null >/dev/null 2>&1 || { echo "round $i: phone unreachable"; sleep 20; }
	sleep $((RANDOM % 3))
	[ $((i % 20)) -eq 0 ] && counters
done
counters
