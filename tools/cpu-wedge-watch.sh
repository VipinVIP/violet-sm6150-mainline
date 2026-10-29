#!/bin/sh
# cpu-wedge-watch.sh - catch which CPU stops executing before a silent hang.
# Samples the kernel's per-CPU busy-jiffy counters once a second; any CPU whose
# counters stop advancing while the rest move is wedged (that is the signature
# seen in the ramoops RCU stalls: "these CPUs still haven't responded to the NMI: 7").
# Cheap on purpose: /proc/stat only, no mmap, nothing that can hang the bus.
#
#   cpu-wedge-watch.sh [seconds] [outfile]
#
# Sample output:
#   t=  12  ok  cpu0=+100 cpu1=+100 ... cpu7=+100
#   t=  13  WEDGED cpu7 (0 jiffies in 3s)   <-- the moment it died
# Also appends the tail of dmesg once a CPU is seen wedged, and keeps a
# last-known-good marker so the file survives a reset.

SECS=${1:-600}
OUT=${2:-/tmp/cpu-wedge.log}
STALL=3          # seconds of no progress before calling a CPU wedged

sess() { echo "phoc=$(pgrep -cx phoc) phrog=$(pgrep -cx phrog) greetd=$(pgrep -cx greetd)"; }

get() {   # print per-cpu busy jiffies (user+system+softirq), space separated
	awk '/^cpu[0-9]/ {
		s = 0
		for (i = 2; i <= 9; i++) s += $i
		printf "%s ", s
	}' /proc/stat
}

prev=$(get)
printf '# cpu-wedge-watch start %s secs -> %s\n' "$SECS" "$OUT" >> "$OUT"
printf '# cpus: %s kernel: %s\n' "$(grep -c '^processor' /proc/cpuinfo)" "$(uname -r)" >> "$OUT"

t=0
stall=0
while [ "$t" -lt "$SECS" ]; do
	sleep 1
	t=$((t + 1))
	now=$(get)
	set -- $now
	i=0
	wedged=""
	line=""
	for cur in $now; do
		old=$(echo "$prev" | cut -d' ' -f$((i + 1)))
		d=$((cur - old))
		line="$line cpu$i=+$d"
		[ "$d" -eq 0 ] && wedged="$wedged $i"
		i=$((i + 1))
	done
	if [ -n "$wedged" ]; then
		stall=$((stall + 1))
	else
		stall=0
	fi
	if [ "$stall" -ge "$STALL" ]; then
		printf 't=%4d  WEDGED cpus:%s (no progress for %ds)%s %s\n' \
			"$t" "$(echo $wedged | tr ' ' ',')" "$stall" "$line" "$(sess)" >> "$OUT"
		if [ ! -f /tmp/cpu-wedge.CAUGHT ]; then
			{
				printf '=== dmesg tail at wedge ===\n'
				dmesg | tail -40
				printf '=== interrupts ===\n'
				grep -v '^ *[0-9]*: *0 ' /proc/interrupts | head -20
			} >> "$OUT" 2>&1
			: > /tmp/cpu-wedge.CAUGHT
		fi
	else
		printf 't=%4d  ok%s %s\n' "$t" "$line" "$(sess)" >> "$OUT"
	fi
	prev=$now
done
printf '# done\n' >> "$OUT"
