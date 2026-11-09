#!/usr/bin/env bash
# Wait for the phone's NCM gadget, put a static IPv4 on it and run a command.
# Static 172.16.42.2/16 beats link-local discovery: the gadget is 172.16.42.1/16 and the
# address survives an address change, so only interface (re)appearance matters.
# Usage: usb-run.sh [timeout_s] '<remote command>'
set -uo pipefail
T=${1:-90}; shift || true
CMD=${1:-'echo hi'}
end=$(( $(date +%s) + T ))
ifc=""
while [ "$(date +%s)" -lt "$end" ]; do
	for c in /sys/class/net/enp0s20f0u*; do
		[ -e "$c" ] || continue
		ifc=$(basename "$c")
		break
	done
	[ -n "$ifc" ] && break
	sleep 0.3
done
if [ -z "$ifc" ]; then
	echo "NO-GADGET after ${T}s"
	exit 1
fi
echo "iface=$ifc"
sudo -n ip addr flush dev "$ifc" 2>/dev/null
sudo -n ip addr add 172.16.42.2/16 dev "$ifc"
sudo -n ip link set "$ifc" up
sleep 0.5
SSHOPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=4
         -o ControlMaster=auto -o ControlPath=/tmp/ssh-mux-usb -o ControlPersist=300)
timeout 25 ssh "${SSHOPTS[@]}" "user@172.16.42.1" "$CMD"
rc=$?
echo "ssh rc=$rc"
exit $rc
