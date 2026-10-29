#!/usr/bin/env bash
# Ask the human for hands on the phone, audibly — with a cue that says WHICH case.
#
# The user does not see desktop notifications and misses chat while away, so every
# request for hands plays a distinct motif (see ./cue.sh) and then polls for the
# expected transport, so the caller just waits.
#
# Usage:
#   ./need-hands.sh fastboot [seconds]   hold Power+Vol-Down ~10 s, then plug USB   (cue: fastboot)
#   ./need-hands.sh power    [seconds]   hold Power ~15 s, then plug USB            (cue: power)
#   ./need-hands.sh net      [seconds]   power on, wait for the NCM gadget          (cue: net)
#   ./need-hands.sh usb      [seconds]   any Qualcomm/ADB/fastboot device           (cue: net)
#
# Exit 0 as soon as the target appears (and plays the "ok" cue over it, so the human
# hears that their action worked); 1 on timeout, with the cue repeated.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WHAT=${1:-fastboot}
LIMIT=${2:-60}   # keep short: the user can see the phone screen, long polls are noise

probe() {
	case $WHAT in
	fastboot) timeout 6 fastboot devices 2>/dev/null | grep -q . ;;
	net) ip -br link 2>/dev/null | grep -q 'enp0s20' ;;
	usb|power) lsusb 2>/dev/null | grep -qiE 'qualcomm|05c6|18d1' \
			|| timeout 6 fastboot devices 2>/dev/null | grep -q . ;;
	*) return 1 ;;   # unknown target must NOT report success
	esac
}

case $WHAT in
	fastboot) CUE=fastboot; MSG="phone needed in FASTBOOT: hold Power+Vol-Down ~10 s, then plug USB" ;;
	power)    CUE=power;    MSG="phone is not answering: hold Power ~15 s, then plug USB" ;;
	net)      CUE=net;      MSG="phone needed on USB networking: power it on / reseat the cable" ;;
	usb)      CUE=net;      MSG="phone needed on the USB bus: plug it in" ;;
	*) echo "unknown target '$WHAT' (fastboot|power|net|usb)"; exit 2 ;;
esac

echo "== $MSG   [cue: $CUE]"
"$HERE/cue.sh" "$CUE" || true
for i in $(seq 1 "$((LIMIT/3))"); do
	if probe; then
		echo "== found after $(((i-1)*3))s"
		"$HERE/cue.sh" ok || true   # tell the human their action landed
		exit 0
	fi
	sleep 3
done
echo "== still nothing after ${LIMIT}s; repeating the cue"
"$HERE/cue.sh" "$CUE" 2 || true
exit 1
