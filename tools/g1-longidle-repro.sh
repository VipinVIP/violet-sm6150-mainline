#!/bin/sh
# G1 repro attempt: long GPU idle (deep RGMU/IFPC state) followed by a burst of real GL work.
#
# Rationale: the field hangs (2026-10-29/30) happened on the *first client submission after hours of
# GPU suspend*, while 40 short resume/suspend cycles (tools/g1-cycle-test.sh) never hung.  So the variable
# under test is the duration of the suspended state, not the number of cycles.
#
# usage: g1-longidle-repro.sh [idle_seconds] [burst_count]

IDLE=${1:-2400}
N=${2:-25}
GPU=/sys/devices/platform/soc@0/5000000.gpu
PROBE=${PROBE:-/tmp/eglprobe.py}

# blank the panel so the compositor stops submitting and the GPU can stay suspended
PHOC=$(pgrep -x phoc | head -1)
if [ -n "$PHOC" ]; then
	DB=$(tr '\0' '\n' < "/proc/$PHOC/environ" | grep ^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)
	sudo -u user env XDG_RUNTIME_DIR=/run/user/10000 DBUS_SESSION_BUS_ADDRESS="$DB" \
		gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver \
		--method org.gnome.ScreenSaver.SetActive true >/dev/null 2>&1 && echo "panel blanked"
fi

s0=$(cat $GPU/power/runtime_suspended_time)
echo "idle start $(date +%T) suspended_time=$s0 sleeping ${IDLE}s"
sleep "$IDLE"
s1=$(cat $GPU/power/runtime_suspended_time)
echo "idle end $(date +%T) suspended_time=$s1 delta=$((s1 - s0))ms control=$(cat $GPU/power/control) status=$(cat $GPU/power/runtime_status)"

h0=$(dmesg | grep -c "hangcheck detected")
i=1
while [ $i -le $N ]; do
	out=$(timeout 20 python3 "$PROBE" 2>&1 | tail -1)
	rc=$?
	echo "burst $i rc=$rc :: $out"
	i=$((i + 1))
	sleep 2
done
h1=$(dmesg | grep -c "hangcheck detected")
echo "hangs $h0 -> $h1"
dmesg | grep -aE "RGMU GX after|RGMU hw_init|cp_init: CP_ME_INIT|hangcheck|adreno_idle" | tail -12
