#!/bin/bash
# Mainline boot test for violet, driven entirely from the laptop.
#
# Reuses the working r9 rootfs: only the boot image changes, and its baked
# pmos_root_uuid is identical, so no 3 GB userdata write is needed per iteration.
#
# Usage:  run-test.sh boot      # try `fastboot boot boot-mainline.img` (NOTHING flashed)
#         run-test.sh flash     # write boot-mainline.img to the boot partition
#         run-test.sh revert    # write the working r9 boot.img back
#         run-test.sh pstore    # reboot normally and dump the captured kernel log
#
# Recovery at every step: the r9 boot.img is one `flash`/`revert` away and the
# bootloader is never touched.
set -uo pipefail

WORK=$HOME/violet-mainline
R9=$HOME/violet-pmos/images-r9/boot-r9.img
MAIN=$WORK/boot-mainline.img
SSHOPTS="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8"

find_phone() {
  IF=$(ip -br link | awk '/enp0s20f0u/{print $1; exit}')
  [ -n "$IF" ] || { echo "no NCM/RNDIS interface -- phone not in a usable state" >&2; return 1; }
  for a in $(ping -6 -c3 -W2 ff02::1%$IF 2>/dev/null | grep -o 'fe80::[0-9a-f:]*' | sort -u); do
    ip -6 addr show $IF | grep -q "$a" && continue
    if timeout 12 ssh $SSHOPTS "user@$a%$IF" true 2>/dev/null; then echo "$a $IF"; return 0; fi
  done
  echo "phone not answering on $IF" >&2; return 1
}

to_fastboot() {
  read A IF < <(find_phone) || return 1
  echo ">> rebooting $A to bootloader via the reboot(2) syscall (no buttons)"
  timeout 20 ssh $SSHOPTS "user@$A%$IF" 'sync; sudo -n python3 -c "import ctypes; ctypes.CDLL(None).syscall(142, 0xfee1dead, 672274793, 0xA1B2C3D4, b\"bootloader\")"' 2>/dev/null
  for i in $(seq 1 40); do
    if fastboot devices 2>/dev/null | grep -q .; then echo ">> in fastboot"; return 0; fi
    sleep 3
  done
  echo "!! never reached fastboot" >&2; return 1
}

case "${1:-}" in
  boot)
    to_fastboot || exit 1
    fastboot getvar product 2>&1 | head -3
    echo ">> trying 'fastboot boot' (non-destructive -- nothing is written to flash)"
    timeout 120 fastboot boot "$MAIN" 2>&1 | tail -8
    echo ">> if the phone does not come up, it should still have r9 in flash;"
    echo "   power-cycle or re-enter fastboot and run: $0 flash"
    ;;
  flash)
    to_fastboot || exit 1
    echo ">> flashing the MAINLINE kernel to the boot partition only"
    fastboot flash boot "$MAIN" 2>&1 | tail -4
    fastboot reboot 2>&1 | tail -2
    echo ">> waiting for the mainline kernel to try to come up (90 s)"
    sleep 90
    echo ">> if it is unreachable (expected: mainline USB peripheral is WIP),"
    echo "   the boot log is in ramoops -- enter fastboot and run: $0 revert"
    ;;
  revert)
    to_fastboot || exit 1
    echo ">> restoring the working r9 boot image"
    fastboot flash boot "$R9" 2>&1 | tail -4
    fastboot reboot 2>&1 | tail -2
    echo ">> waiting for r9 (about 70 s)"; sleep 75
    find_phone && echo ">> r9 is back"
    ;;
  pstore)
    read A IF < <(find_phone) || exit 1
    echo ">> asking r9 for the ramoops log left by the mainline attempt"
    timeout 60 ssh $SSHOPTS "user@$A%$IF" \
      'sudo -n ls -la /sys/fs/pstore/ 2>&1; for f in /sys/fs/pstore/*; do echo "==== $f"; sudo -n head -c 40000 "$f"; echo; done' 2>&1 | head -250
    ;;
  *)
    echo "usage: $0 {boot|flash|revert|pstore}"; exit 1;;
esac
