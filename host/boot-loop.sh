#!/bin/bash
# Reboot the phone N times and log a health line after each boot.
# Usage: host/boot-loop.sh N label out.log
N=${1:-5}; LABEL=${2:-loop}; OUT=${3:-/tmp/boot-loop.log}
for i in $(seq 1 "$N"); do
	T=$(cat /tmp/claude-1000/phone_ip)
	timeout 10 ssh -o ConnectTimeout=5 user@"$T" 'sudo reboot' </dev/null >/dev/null 2>&1
	sleep 40
	host/boot-check.sh 190 "$LABEL-$i" >> "$OUT" 2>&1
done
echo DONE >> "$OUT"
