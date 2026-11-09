#!/bin/sh
# reboot-from-here.sh - arm the harvester + hardware watchdog, then reboot.
# Runs on the phone as root (reachable over WiFi: the gadget is dead after a resume).
# The watchdog is what makes a frozen shutdown recover without a 10 s power-button hold:
# qcom_wdt has no MAGICCLOSE, so once /dev/watchdog0 is open it resets the SoC after 30 s
# unless something pets it.  Nothing does.  A clean shutdown finishes in ~15-20 s.
set -u
LOG=/var/log/shutdown-harvest.log
tail -c 4000 "$LOG" 2>/dev/null > /tmp/harvest-before.txt

# harvester: kernel ring to ext4 every 2 s, synced, so a hard reset keeps the last seconds
setsid sh -c 'while :; do { echo "--- $(date +%T) up=$(cut -d. -f1 /proc/uptime)"; dmesg | tail -25; } >> /var/log/shutdown-harvest.log; sync; sleep 2; done' \
	</dev/null >/dev/null 2>&1 &
echo "harvester started"

# watchdog: hold the fd open, never pet it
setsid sh -c 'exec 9>/dev/watchdog0; sleep 600' </dev/null >/dev/null 2>&1 &
echo "watchdog armed (30 s, no pet) - a clean shutdown must finish before it fires"

echo "rebooting now"
sync
setsid reboot </dev/null >/dev/null 2>&1 &
