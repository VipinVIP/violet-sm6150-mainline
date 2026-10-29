#!/bin/bash
# Build a MAINLINE boot.img for violet (Redmi Note 7 Pro).
#
# Strategy: reuse the working r9 initramfs and the working r9 rootfs, and swap in
# only the mainline kernel + the mainline violet DTB.  The baked pmos_root_uuid is
# kept IDENTICAL to the one already on the phone, so only the boot partition has
# to be written -- no 3 GB userdata rewrite per iteration.
#
# Geometry is taken from the working r9 boot.img (and from device-xiaomi-violet's
# deviceinfo): pagesize 4096, header v2, base 0x0, kernel 0x8000,
# ramdisk 0x01000000, tags 0x100, dtb 0x01f00000.
#
# "quiet splash" is deliberately DROPPED: the point of the first flash is to get
# the kernel's own boot log into the ramoops region, and quiet would suppress it.
set -euo pipefail

K=${K:-$HOME/violet-sm6150-mainline/linux-7.2.10}
B=${B:-$HOME/violet-sm6150-mainline/bootimg-r9}
O=${O:-$HOME/violet-sm6150-mainline/boot-mainline.img}

IMG="$K/arch/arm64/boot/Image"
DTB="$K/arch/arm64/boot/dts/qcom/violet-sm6150.dtb"

[ -f "$IMG" ] || { echo "FATAL: no kernel Image at $IMG (build still running?)" >&2; exit 1; }
[ -f "$DTB" ] || { echo "FATAL: no DTB at $DTB" >&2; exit 1; }
[ -f "$B/ramdisk" ] || { echo "FATAL: no r9 ramdisk at $B/ramdisk" >&2; exit 1; }

# r9's cmdline, minus quiet/splash, plus an explicit console so the UART console
# is registered and pstore captures everything the kernel prints.
# UUIDs are per-install: export them from your own phone (`blkid` on pmOS_boot / root).
: "${PMOS_BOOT_UUID:?set PMOS_BOOT_UUID to your pmOS_boot partition UUID}"
: "${PMOS_ROOT_UUID:?set PMOS_ROOT_UUID to your root filesystem UUID}"
CMDLINE="${CMDLINE:-plymouth.ignore-serial-consoles androidboot.hardware=qcom swiotlb=1 loop.max_part=7 kpti=off pmos_boot_uuid=${PMOS_BOOT_UUID} pmos_root_uuid=${PMOS_ROOT_UUID} pmos_rootfsopts=defaults}"

# ---------------------------------------------------------------------------
# Two things ABL needs that mainline's DTB does not provide:
#
# 1. __symbols__.  ABL applies the board's dtbo overlay (selectable via the
#    dtbo partition, matched on qcom,msm-id/board-id) to this DTB, and overlay
#    application resolves targets through __symbols__ -- which dtc only emits
#    with -@.  Mainline's dtbs build does not pass -@ (pmOS/Android DTBs do),
#    so round-trip the DTB through dtc with -@ to add it.
# 2. The board-selection keys qcom,msm-id / qcom,board-id, copied verbatim from
#    the vendor DTB that boots on this device.
#
# Both are vendor/deprecated concerns, so they are injected here rather than
# living in violet-sm6150.dts (which stays clean and upstreamable).
# ---------------------------------------------------------------------------
DTB_ABL=$(mktemp --suffix=.dtb)
cp "$DTB" "$DTB_ABL"

# dtc only emits __symbols__ with -@, and the kernel's dtbs build does not pass it.
# Round-trip through dtc with -@ so ABL can resolve the overlay's targets.
if ! dtc -I dtb -O dtb -@ -o "${DTB_ABL}.sym" "$DTB_ABL" 2>/dev/null; then
  echo "WARN: dtc -@ round-trip failed; __symbols__ will be missing" >&2
else
  mv "${DTB_ABL}.sym" "$DTB_ABL"
fi

fdtput -t x "$DTB_ABL" / qcom,msm-id 0x163 0x0 || { echo "FATAL: fdtput msm-id failed" >&2; exit 1; }
fdtput -t x "$DTB_ABL" / qcom,board-id 0x22 0x0 || { echo "FATAL: fdtput board-id failed" >&2; exit 1; }
echo "dtb prepared for ABL:"
echo "  qcom,msm-id   = $(fdtget "$DTB_ABL" / qcom,msm-id 2>/dev/null)"
echo "  qcom,board-id = $(fdtget "$DTB_ABL" / qcom,board-id 2>/dev/null)"
if [ "$(dtc -I dtb -O dts "$DTB_ABL" 2>/dev/null | grep -c __symbols__)" -gt 0 ]; then
  echo "  __symbols__   = present"
else
  echo "  __symbols__   = MISSING (overlay application will fail)" >&2
fi

mkbootimg \
  --kernel "$IMG" \
  --ramdisk "$B/ramdisk" \
  --dtb "$DTB_ABL" \
  --pagesize 4096 \
  --header_version 2 \
  --base 0x00000000 \
  --kernel_offset 0x00008000 \
  --ramdisk_offset 0x01000000 \
  --second_offset 0x00000000 \
  --tags_offset 0x00000100 \
  --dtb_offset 0x01f00000 \
  --cmdline "$CMDLINE" \
  -o "$O"

echo "built: $O"
echo "  kernel:  $(stat -c%s "$IMG") bytes  (mainline, $(grep -m1 -oE 'VERSION = [0-9]+' "$K/Makefile") )"
echo "  dtb:     $(stat -c%s "$DTB") bytes  (violet-sm6150.dtb)"
echo "  ramdisk: $(stat -c%s "$B/ramdisk") bytes (r9 initramfs)"
echo "  image:   $(stat -c%s "$O") bytes"
