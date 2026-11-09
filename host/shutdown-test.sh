#!/usr/bin/env bash
# shutdown-test.sh - capture what OpenRC does during a reboot, from the laptop side.
#
# The plan's item 1 hangs the phone at shutdown, so the evidence has to survive the
# reboot: a live dmesg stream on the laptop (dies with the cable, but shows the last
# kernel messages), plus /var/log/rc.log on the phone (written by OpenRC when
# rc_logger="YES"), read after the next boot.
#
# Usage: shutdown-test.sh <ssh-prefix...>   e.g. shutdown-test.sh /tmp/usbssh
#        (any command that runs "ssh user@phone <cmd>"; a ControlMaster is assumed)
set -uo pipefail
SSH=${1:-/tmp/usbssh}
TAG=$(date +%F_%T)
OUT=/home/vipi/violet-mainline/logs/shutdown-$TAG
mkdir -p "$OUT"

echo "== 1. enable rc_logger"
$SSH 'grep -q ^rc_logger=\"/var/log/rc.log\" /etc/rc.conf || sudo -n sed -i "s|^#\?rc_logger=.*|rc_logger=\\"/var/log/rc.log\\"|" /etc/rc.conf; grep -n "^rc_logger" /etc/rc.conf; sudo -n touch /var/log/rc.log; ls -l /var/log/rc.log' | tee "$OUT/rc-logger.txt"

echo "== 2. start the dmesg stream (dies with the cable; that is expected)"
( $SSH 'sudo -n dmesg -wT' > "$OUT/dmesg-stream.txt" 2>&1 & echo $! > "$OUT/stream.pid" )
sleep 3

echo "== 3. note the pre-reboot state"
$SSH 'echo uptime=$(cut -d. -f1 /proc/uptime); sudo -n dmesg | tail -3; sudo -n rc-status --all | grep -E "violet-modem|rmtfs|tqftpserv|hexagon"' | tee "$OUT/pre.txt"

echo "== 4. reboot"
$SSH 'sudo -n sync; sudo -n reboot' || echo "(ssh died during reboot, expected)"
echo "   local time $(date +%T)  - waiting up to 180 s for the phone to come back"

end=$(( $(date +%s) + 180 ))
back=""
while [ "$(date +%s)" -lt "$end" ]; do
	if timeout 4 ping -c1 -W2 <lan-ip> >/dev/null 2>&1; then back="wifi"; break; fi
	for c in /sys/class/net/enp0s20f0u*; do [ -e "$c" ] && { back="usb $(basename "$c")"; break 2; }; done
	sleep 2
done
echo "   came back via: ${back:-NOTHING within 180 s}" | tee "$OUT/back.txt"

if [ -n "$back" ]; then
	sleep 20
	echo "== 5. collect rc.log and pstore"
	$SSH 'echo uptime=$(cut -d. -f1 /proc/uptime); echo "-- rc.log tail:"; sudo -n tail -60 /var/log/rc.log; echo "-- pstore:"; sudo -n ls -l /sys/fs/pstore/ 2>/dev/null' | tee "$OUT/rc-log.txt"
	$SSH 'sudo -n dmesg | grep -aiE "fatal error|suspend|crash|modem" | tail -20' | tee "$OUT/dmesg-after.txt"
fi
echo "== artefacts in $OUT"
