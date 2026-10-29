#!/bin/bash
# r10 -> mainline kexec that does NOT depend on /boot/initramfs (corrupt 2026-10-27): the initramfs is
# extracted from /boot/boot.img on the phone.  Every remote step has a timeout; no unbounded waits.
# Usage: DTB_SRC=<dtb> WDT=ext EXTRA_CMDLINE="..." ./ml-boot2.sh
set -u
IF=$(ip -br link | awk '/^enp0s20f0u/{print $1; exit}')
K=$HOME/violet-mainline/kernel/linux-7.2.10/arch/arm64/boot
DTB_SRC=${DTB_SRC:-$K/dts/qcom/violet-sm6150.dtb}
O="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8"
A=$(ip neigh show dev $IF | awk '/fe80/{print $1; exit}'); S="user@$A%$IF"; SC="user@[$A%$IF]"
timeout 12 ssh $O $S 'uname -r' | grep -q '^4.14' || { echo "phone is not on r10"; exit 1; }
W=$(mktemp -d); cp "$DTB_SRC" $W/main.dtb
fdtput -t s $W/main.dtb /memory device_type memory 2>/dev/null || { fdtput -c $W/main.dtb /memory; fdtput -t s $W/main.dtb /memory device_type memory; }
fdtput -t x $W/main.dtb /memory reg 0 0x80000000 0 0x80000000 1 0 0 0x7dd00000
timeout 120 scp -q $O $K/Image $W/main.dtb $HOME/violet-mainline/tools/kexec $HOME/violet-pmos/tools/kgsl_open.py $HOME/violet-mainline/tools/extract-rd.py "$SC:/tmp/" && scp -q $O $HOME/violet-mainline/wdt-disable.py "$SC:/tmp/wdt.py" || { echo "scp failed"; exit 1; }
timeout 60 ssh $O $S 'echo 1024 | sudo -n tee /sys/class/backlight/backlight/brightness >/dev/null; sudo -n timeout 30 python3 /tmp/kgsl_open.py | tail -1'
CMD="earlycon=msm_geni_serial,0x880000 console=ttyMSM0,115200n8 ignore_loglevel loglevel=8 panic=5 pmos_boot_uuid=24d6dade-23b3-4b77-9ec0-ef87830e7c4f pmos_root_uuid=f3fc5ebc-6673-4b01-b575-91006f5c88de pmos_rootfsopts=defaults fbcon=font:TER16x32 ${EXTRA_CMDLINE:-}"
timeout 60 ssh $O $S "chmod +x /tmp/kexec; python3 /tmp/extract-rd.py && sudo -n sh -c '/tmp/kexec -u; /tmp/kexec -l /tmp/Image --initrd=/tmp/initramfs --dtb=/tmp/main.dtb --command-line=\"$CMD\" 2>&1 | tail -1; cat /sys/kernel/kexec_loaded'" | tail -1 | grep -q '^1$' || { echo "kexec load failed"; exit 1; }
timeout 20 ssh $O $S "sudo -n sh -c 'sync; python3 /tmp/wdt.py ${WDT:-ext} >/dev/null; (setsid nohup sh -c \"sleep 2; /tmp/kexec -e\" >/dev/null 2>&1 &)'"
for i in $(seq 1 30); do
  sleep 6; ping -6 -c1 -W1 ff02::1%$IF >/dev/null 2>&1
  A=$(ip neigh show dev $IF 2>/dev/null | awk '/fe80/{print $1}' | tail -1)
  r=$(timeout 8 ssh $O user@$A%$IF 'uname -r' 2>/dev/null) && echo "$r" | grep -q sm6150 && { echo "MAINLINE $r"; exit 0; }
done
echo "mainline did not answer within 3 min"; exit 1
