#!/usr/bin/env bash
# Watch for the phone's USB gadget for up to $1 seconds and, every time it appears,
# grab a state snapshot over a static 172.16.42.2/16 on the gadget interface.
#
# The window is short: the phone reaches userspace, then idles into suspend ~30-45 s later,
# and /etc/elogind/system-sleep/no-hexagonrpcd-on-suspend.sh unbinds the gadget UDC around
# sleep and does not restore it.  So the first successful connection immediately renames
# that hook out of the way (keeping USB alive across suspends) and leaves it in
# /root/sleep-hook-off/ so it can be reinstated by hand.
set -uo pipefail
T=${1:-1800}
OUT=${2:-/home/vipi/violet-mainline/logs/usb-grabs.txt}
SSHOPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3
         -o LogLevel=ERROR)
REMOTE='
echo "== uptime $(cut -d. -f1 /proc/uptime)s  kernel $(uname -r)"
echo "-- power: states=$(cat /sys/power/state 2>/dev/null) pm_wakeup_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
echo "-- netdevs: $(ls /sys/class/net | tr "\n" " ")"
echo "-- remoteproc:"
for d in /sys/class/remoteproc/remoteproc*; do echo "   $d $(cat $d/name 2>/dev/null) $(cat $d/state 2>/dev/null)"; done
echo "-- udc bound=[$(ls /sys/class/udc 2>/dev/null | tr "\n" " ")] gadget_UDC=[$(cat /sys/kernel/config/usb_gadget/*/UDC 2>/dev/null | tr "\n" " ")]"
echo "-- rc-status:"
sudo -n rc-status --all 2>/dev/null | grep -E "violet-modem|rmtfs|tqftpserv|hexagon|greetd|localmount"
echo "-- violet-modem.log:"; tail -6 /var/log/violet-modem.log 2>/dev/null
echo "-- dmesg tail:"; sudo -n dmesg | tail -18
echo "== GRAB-OK"
'
HOLD='
mkdir -p /root/sleep-hook-off
mv /etc/elogind/system-sleep/no-hexagonrpcd-on-suspend.sh /root/sleep-hook-off/ 2>/dev/null
echo "hook-moved: /etc/elogind/system-sleep now [$(ls /etc/elogind/system-sleep/ 2>/dev/null | tr "\n" " ")]"
'
end=$(( $(date +%s) + T ))
mkdir -p "$(dirname "$OUT")"
while [ "$(date +%s)" -lt "$end" ]; do
	ifc=""
	for c in /sys/class/net/enp0s20f0u*; do [ -e "$c" ] && { ifc=$(basename "$c"); break; }; done
	if [ -z "$ifc" ]; then sleep 1; continue; fi
	sudo -n ip addr replace 172.16.42.2/16 dev "$ifc" 2>/dev/null
	sudo -n ip link set "$ifc" up 2>/dev/null
	{
		echo "### $(date +%F_%T) iface=$ifc"
		ok=""
		for a in $(seq 1 15); do
			if out=$(timeout 12 ssh "${SSHOPTS[@]}" "user@172.16.42.1" "$REMOTE" 2>&1); then
				echo "$out"; ok=1; break
			fi
			echo "-- ssh attempt $a failed: $(echo "$out" | tail -2 | tr '\n' ' ')"
			sleep 2
		done
		if [ -n "$ok" ]; then
			echo "### HOLD"; timeout 15 ssh "${SSHOPTS[@]}" "user@172.16.42.1" "$HOLD" 2>&1
		fi
		echo "### $(date +%F_%T) session end"
	} >> "$OUT" 2>&1
	while [ -e "/sys/class/net/$ifc" ]; do sleep 1; done
	echo "### $(date +%F_%T) $ifc gone" >> "$OUT"
done
echo "watcher done"
