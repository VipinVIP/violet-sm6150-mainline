#!/bin/sh
# G1 repro: repeated GPU power cycles with real GL work.
#
# Why this shape: the field signature (2026-10-29) is `hangcheck detected gpu
# lockup rb 0`, preceded by `adreno_idle: timeout waiting to drain ringbuffer 0
# rptr/wptr = 0/C`, which only a6xx_cp_init()/preempt can emit - i.e. the CP never
# consumed CP_ME_INIT during hw_init, which runs on every GPU resume.  So each
# iteration here is one full runtime-PM cycle: resume -> hw_init -> real command
# stream (surfaceless EGL + glClear + glReadPixels) -> autosuspend.
#
# Runs without a compositor or an unlocked session (EGL_PLATFORM=surfaceless),
# so it does not depend on the lock screen being dismissed.
#
# usage: g1-cycle-test.sh [cycles] [idle_seconds]

N=${1:-15}
IDLE=${2:-8}
PROBE=${PROBE:-/tmp/eglprobe.py}
GPU=/sys/devices/platform/soc@0/5000000.gpu

i=1
echo "start $(date +%T) cycles=$N idle=${IDLE}s"
while [ $i -le $N ]; do
	h0=$(dmesg | grep -c "hangcheck detected")
	s0=$(cat $GPU/power/runtime_status 2>/dev/null)
	t0=$(date +%s)
	out=$(timeout 25 python3 "$PROBE" 2>&1 | tail -1)
	rc=$?
	d=$(( $(date +%s) - t0 ))
	h1=$(dmesg | grep -c "hangcheck detected")
	echo "cycle $i start=$s0 rc=$rc ${d}s hang $h0->$h1 :: $out"
	i=$((i + 1))
	sleep "$IDLE"
done
echo "end $(date +%T)"
dmesg | grep -E "hangcheck detected|adreno_idle|RGMU|gpu fault|hw_init" | tail -15
