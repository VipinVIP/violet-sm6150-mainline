#!/bin/bash
# Real test: flash the mainline image to the boot partition and observe.
#
# Why flash rather than `fastboot boot`: measured on this device, `fastboot boot`
# does NOT boot the supplied image -- with the vendor kernel, our kernel, the
# vendor DTB or our DTB it always ended up running the FLASHED partition
# (uname stayed 4.14, model stayed the vendor's).  So it is a fancy reboot, not a
# test.  Only a flash actually exercises the image.
#
# Safety: ABL validates the boot image before handing off, and the observed
# failure mode for a rejected image is "the device stays in fastboot" -- which is
# fully recoverable (fastboot flash boot images-r9/boot-r9.img).  r9's boot.img
# and the raw partition are both backed up in ~/violet-mainline/device-backup/.
set -uo pipefail
W=$HOME/violet-mainline
R9=$HOME/violet-pmos/images-r9/boot-r9.img
MAIN=$W/boot-mainline.img

fastboot devices 2>/dev/null | grep -q . || { echo "not in fastboot"; exit 1; }

echo "=== flashing the MAINLINE image to boot (r9 image kept for revert) ==="
fastboot flash boot "$MAIN" 2>&1 | tail -4
echo "=== rebooting ==="
fastboot reboot 2>&1 | tail -2

echo "=== observing for 90 s: does anything come up? ==="
for i in $(seq 1 9); do
  sleep 10
  if fastboot devices 2>/dev/null | grep -q .; then
    echo "t+$((i*10))s: in FASTBOOT (image refused -> recoverable)"
    echo "  restoring r9 now"
    fastboot flash boot "$R9" 2>&1 | tail -2
    fastboot reboot 2>&1 | tail -1
    exit 0
  fi
  if ip -br link | grep -q enp0s20f0u; then
    echo "t+$((i*10))s: USB came up -> the kernel is running"
    ip -br link | grep enp0s20f0u
    exit 0
  fi
  echo "t+$((i*10))s: nothing yet"
done
echo "=== final: no fastboot and no USB -> the device is hung or mid-boot ==="
lsusb | grep -viE 'root hub|hub' | tail -3
