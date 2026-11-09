#!/bin/sh
# hex-stop-measure.sh - measure whether `rc-service hexagonrpcd-adsp-sensorspd stop` returns.
# Runs on the phone. Bounded: the stop is killed after 30 s, then the daemons are SIGKILLed
# so the phone is not left without a sensor daemon.
set -u
SVC=hexagonrpcd-adsp-sensorspd
log=/tmp/hexstop.log
: > "$log"

echo "== pids before: $(pgrep -x hexagonrpcd | tr '\n' ' ')"
for p in $(pgrep -x hexagonrpcd); do
	echo "   $p stat=$(awk '{print $3}' /proc/$p/stat) wchan=$(cat /proc/$p/wchan)"
done

t0=$(date +%s)
( sudo -n rc-service "$SVC" stop > "$log" 2>&1; echo "rc=$?" >> "$log" ) &
supervisor=$!
echo "== stop started (t0=$t0), watching 30 s"

i=0
while [ $i -lt 15 ]; do
	sleep 2
	i=$((i + 1))
	now=$(( $(date +%s) - t0 ))
	alive=$(pgrep -x hexagonrpcd | tr '\n' ' ')
	st=""
	for p in $alive; do st="$st $p:$(awk '{print $3}' /proc/$p/stat)/$(cat /proc/$p/wchan 2>/dev/null)"; done
	echo "   t+${now}s  stop-proc=$(kill -0 $supervisor 2>/dev/null && echo running || echo done)  daemons:${st:- none}"
	kill -0 $supervisor 2>/dev/null || break
done

echo "== stopping the stop (timeout 30 was the bound)"
kill -9 $supervisor 2>/dev/null
sleep 1
echo "== rc-service output:"; cat "$log"

echo "== daemons still alive: $(pgrep -x hexagonrpcd | tr '\n' ' ')"
for p in $(pgrep -x hexagonrpcd); do
	echo "   SIGKILL $p"; sudo -n kill -9 "$p" 2>/dev/null
done
sleep 1
echo "== after SIGKILL: $(pgrep -x hexagonrpcd | tr '\n' ' ')"
echo "== rc-status: $(sudo -n rc-status --all 2>&1 | grep hexagon)"
echo "== restarting"
timeout 20 sudo -n rc-service "$SVC" start; echo "start rc=$?"
sleep 2
echo "== rc-status after start: $(sudo -n rc-status --all 2>&1 | grep hexagon)"
echo "== pids now: $(pgrep -x hexagonrpcd | tr '\n' ' ')"
