#!/usr/bin/env bash
# Flash the instrumented kernel to the `boot` partition ONLY, reboot, and verify
# the G1 telemetry came up.
#
#   ./host/flash-g1.sh            flash boot-mainline.img, reboot, verify
#   ./host/flash-g1.sh --verify   no flash: just check what is running now
#   ./host/flash-g1.sh --wait     wait for the phone to appear, then flash
#
# Hard rules encoded here:
#   * `dtbo` is NEVER written - the erased dtbo is what makes ABL take our DTB.
#   * `boot` is the only partition flashed; recovery path if the kernel does not
#     boot is `fastboot flash boot ~/violet-pmos/images-r9/boot-r10.img`.
#
# The USB NCM link (172.16.42.2/16 on the gadget interface, phone at
# 172.16.42.1/16) is preferred over WiFi: it does not depend on the AP and it is
# the same cable fastboot uses.
set -uo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
IMG=${IMG:-$HERE/boot-mainline.img}
PHONE=${PHONE:-172.16.42.1}
USB_ADDR=172.16.42.2/16
FASTBOOT=${FASTBOOT:-fastboot}
SSH_OPTS=(-o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

usbif() { ls /sys/class/net 2>/dev/null | grep -E '^enp0s20f0u[0-9]+$' | head -1; }

ensure_link() {
	local ifc
	ifc=$(usbif)
	[ -n "$ifc" ] || return 1
	ip -4 addr show dev "$ifc" 2>/dev/null | grep -q '172\.16\.42\.2' \
		|| sudo -n ip addr add "$USB_ADDR" dev "$ifc" 2>/dev/null
	ssh "${SSH_OPTS[@]}" "user@$PHONE" true 2>/dev/null
}

ph() { ssh "${SSH_OPTS[@]}" "user@$PHONE" "$@"; }

wait_boot() {
	local i
	for i in $(seq 1 60); do
		if ensure_link; then echo "phone reachable over USB after ${i}0s"; return 0; fi
		sleep 5
	done
	return 1
}

verify() {
	echo "== running kernel =="
	ph 'uname -r; uptime; cat /sys/class/power_supply/battery/capacity'
	echo "== dmesg size (S6 gate) =="
	ph 'sudo dmesg | wc -l; sudo dmesg | grep -ac "Handover signaled"'
	echo "== boot-time lines that used to rotate away =="
	ph 'sudo dmesg | grep -aE "RGMU GX after GPUSTART|RGMU GPUSTART ack|RGMU hw_init|RGMU boot failed|PCC" | head -12'
	echo "== G1 signature =="
	ph 'sudo dmesg | grep -acE "hangcheck detected|adreno_idle"; sudo dmesg | grep -aE "cp_init: CP_ME_INIT|hangcheck detected|adreno_idle" | tail -6'
	echo "== gpu state =="
	ph 'cat /sys/devices/platform/soc@0/5000000.gpu/power/runtime_status; cat /sys/devices/platform/soc@0/5000000.gpu/power/control'
}

case "${1:-}" in
--verify)
	wait_boot || { echo "phone not reachable"; exit 1; }
	verify
	exit 0
	;;
--wait)
	wait_boot || { echo "phone never appeared"; exit 1; }
	;;
esac

[ -f "$IMG" ] || { echo "FATAL: no image at $IMG"; exit 1; }

if ! timeout 6 "$FASTBOOT" devices 2>/dev/null | grep -q .; then
	echo "== asking the phone for fastboot =="
	ph 'sudo -n /usr/local/bin/reboot-bootloader' 2>/dev/null
	for i in $(seq 1 30); do
		sleep 3
		if timeout 6 "$FASTBOOT" devices 2>/dev/null | grep -q .; then break; fi
	done
fi

timeout 6 "$FASTBOOT" devices 2>/dev/null | grep -q . || { echo "FATAL: phone never entered fastboot (plug the USB cable in?)"; exit 1; }
echo "== fastboot: $("$FASTBOOT" devices | head -1) =="

echo "== flashing boot only (dtbo stays erased) =="
"$FASTBOOT" flash boot "$IMG" || { echo "FATAL: flash failed"; exit 1; }
"$FASTBOOT" reboot

if wait_boot; then
	verify
else
	echo "PHONE DID NOT COME BACK - recovery: fastboot flash boot ~/violet-pmos/images-r9/boot-r10.img"
	exit 1
fi
