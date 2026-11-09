#!/usr/bin/env bash
# usb-shell.sh - wait for the phone's NCM gadget, then get one shell command through it.
#
# Why this is fussy:
#  * NetworkManager owns the new interface and immediately reconfigures it with an
#    IPv4 link-local address, which wipes a static 172.16.42.2/16 added behind its back.
#    So: mark the interface unmanaged first, then add the static address.
#  * The gadget can live for only ~40-70 s per appearance (the phone suspends; the elogind
#    hook unbinds the UDC), but sshd on this boot only starts listening ~100 s after
#    power-on. So the retry window after the interface appears must be >= 120 s, and it
#    must keep retrying while the interface is still there (the old version gave up after
#    6 x 17 s and then sat in a "wait for the iface to vanish" loop forever, which is how
#    a boot got stranded).
#  * Primary transport is IPv6 link-local (always present, NM does not remove it);
#    172.16.42.1 is the fallback.
#
# Usage: usb-shell.sh [seconds_to_watch] '<remote command>' [retry_window_s]
#   retry_window_s defaults to 150 (>= 120 is required, see above).
set -uo pipefail
T=${1:-1800}
CMD=${2:-'echo PHONE-ALIVE'}
RETRY=${3:-150}
end=$(( $(date +%s) + T ))
SSHOPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3
         -o LogLevel=ERROR -o BatchMode=yes)

while [ "$(date +%s)" -lt "$end" ]; do
	ifc=""
	for c in /sys/class/net/enp0s20f0u*; do [ -e "$c" ] && { ifc=$(basename "$c"); break; }; done
	[ -z "$ifc" ] && { sleep 0.5; continue; }

	echo "== $(date +%T) $ifc appeared"
	sudo -n nmcli dev set "$ifc" managed no >/dev/null 2>&1
	sudo -n ip addr flush dev "$ifc" 2>/dev/null
	sudo -n ip addr add 172.16.42.2/16 dev "$ifc" 2>/dev/null
	sudo -n ip link set "$ifc" up 2>/dev/null

	# Retry inside a wall-clock window (not a fixed attempt count): sshd may not be
	# listening yet when the interface first appears.
	rend=$(( $(date +%s) + RETRY ))
	n=0
	while [ "$(date +%s)" -lt "$rend" ] && [ "$(date +%s)" -lt "$end" ]; do
		n=$((n+1))
		if [ $((n % 8)) -eq 1 ]; then
			timeout 2 ping -6 -c1 -W1 "ff02::1%$ifc" >/dev/null 2>&1
			peer6=$(ip -6 neigh show dev "$ifc" 2>/dev/null \
				| awk '/REACHABLE|STALE|DELAY/{print $1; exit}')
			echo "   $(date +%T) peer6=${peer6:-none}  v4=$(ip -br addr show "$ifc" | awk '{print $3}')"
		fi
		if [ -n "${peer6:-}" ]; then
			out=$(timeout 15 ssh "${SSHOPTS[@]}" "user@[${peer6}%${ifc}]" "$CMD" 2>&1) && {
				echo "$out"; echo "== OK over ipv6 after ${n} attempt(s)"; exit 0; }
		fi
		out=$(timeout 15 ssh "${SSHOPTS[@]}" "user@172.16.42.1" "$CMD" 2>&1) && {
			echo "$out"; echo "== OK over ipv4 after ${n} attempt(s)"; exit 0; }
		[ $((n % 10)) -eq 1 ] && echo "   attempt $n: $(echo "$out" | tail -1)"
		sleep 2
		[ -e "/sys/class/net/$ifc" ] || { echo "   $(date +%T) iface vanished mid-window"; break; }
	done
	# Interface still there but no shell in this window: re-arm the address and let the
	# outer loop open a fresh window (this is the case that used to hang forever).
	if [ -e "/sys/class/net/$ifc" ]; then
		echo "== $(date +%T) $ifc still up, no shell in ${RETRY}s - re-arming"
		sudo -n ip addr replace 172.16.42.2/16 dev "$ifc" 2>/dev/null
	else
		echo "== $(date +%T) $ifc gone"
	fi
done
echo "== no shell in ${T}s"
exit 1
