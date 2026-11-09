#!/bin/sh
# modem-stop-wedge-test.sh - reproduce the shutdown wedge with one action: stop the modem
# while ath10k (WLAN client of MPSS firmware) is still up.
#
# Evidence from the 2026-11-02 pstore panic (build #183): modem stopped at 923.78 s,
# ath10k still alive, RCU stall reporting CPU1 unresponsive at 944.80 s, soft lockup in
# bpf_prog_free_deferred at 963.5 s, watchdog panic.  So the question is whether the
# modem stop alone wedges a CPU.
#
# Runs on the phone. Writes to ext4 with sync so the last seconds survive a cold reset.
set -u
LOG=/var/log/wedge-harvest.log
: > "$LOG"

say() { echo "$(date +%T) $*" | tee -a "$LOG"; }

say "=== harvest + modem-stop test, uptime $(cut -d. -f1 /proc/uptime)"
say "softlockup_panic=$(cat /proc/sys/kernel/softlockup_panic) watchdog_thresh=$(cat /proc/sys/kernel/watchdog_thresh)"

# 2 s harvester: kernel log tail, so a wedge leaves its last seconds on disk.
harvest() {
	while :; do
		{
			echo "--- $(date +%T) up=$(cut -d. -f1 /proc/uptime)"
			dmesg | tail -6
		} >> "$LOG"
		sync
		sleep 2
	done
}
harvest &
HPID=$!
say "harvester pid $HPID"

rp=""
for d in /sys/class/remoteproc/remoteproc*; do
	[ "$(cat "$d/name" 2>/dev/null)" = "modem" ] && rp=$d
done
say "modem rproc=${rp:-none} state=$(cat "$rp/state" 2>/dev/null)"
say "wlan0=$(ip -br link show wlan0 2>/dev/null | awk '{print $2}') ath10k_ref=$(lsmod | awk '$1=="ath10k_snoc"{print $3}')"

say "STOPPING MODEM NOW (ath10k left running, as at shutdown)"
t0=$(date +%s)
rc-service violet-modem stop >> "$LOG" 2>&1
say "rc-service violet-modem stop returned rc=$? after $(( $(date +%s) - t0 ))s"
say "modem state now: $(cat "$rp/state" 2>/dev/null)"

# Watch for the wedge: is the system still scheduling?  Derived from /proc/uptime, which
# any CPU can answer, plus an RCU/softlockup grep after each 10 s.
i=0
while [ $i -lt 9 ]; do
	sleep 10
	i=$((i + 1))
	u=$(cut -d. -f1 /proc/uptime)
	bad=$(dmesg | grep -cE "rcu: INFO: rcu_preempt detected stalls|soft lockup|stall detected")
	say "t+$((i * 10))s up=$u rcu_or_lockup_lines=$bad modem=$(cat "$rp/state" 2>/dev/null)"
done

say "=== 90 s survived, harvesting stops; last stall lines:"
dmesg | grep -E "rcu:|soft lockup|watchdog" | tail -5 | tee -a "$LOG"
kill "$HPID" 2>/dev/null
say "=== done"
