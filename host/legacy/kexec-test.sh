#!/bin/bash
# kexec the mainline kernel from the running downstream r10, then read its console from pstore.
# Needs r10 (CONFIG_KEXEC) on the phone. No flash, no buttons. If the mainline kernel hangs
# rather than panics/resets, hold Power ~15 s to force a reset; ABL then boots r10 again.
# Usage: kexec-test.sh [tag]   -> saves ~/violet-mainline/kexec-<tag>-console.txt
set -uo pipefail
TAG=${1:-run}; IF=$(ip -br link | awk '/^enp0s20f0u/{print $1; exit}')
K=$HOME/violet-mainline/kernel/linux-7.2.10/arch/arm64/boot
W=$(mktemp -d); DTB=$W/main.dtb
# KCONSOLE overrides the serial-console part (default unchanged). KCONSOLE="loglevel=4" = no UART console.
KCONSOLE=${KCONSOLE-"earlycon=msm_geni_serial,0x880000 console=ttyMSM0,115200n8 ignore_loglevel loglevel=8"}
CMD="$KCONSOLE panic=5 pmos_boot_uuid=24d6dade-23b3-4b77-9ec0-ef87830e7c4f pmos_root_uuid=f3fc5ebc-6673-4b01-b575-91006f5c88de pmos_rootfsopts=defaults ${EXTRA_CMDLINE:-}"
# Pick a neighbour that ACTUALLY answers ssh. ping -c1 ff02::1 returns the host's own
# address first, and a dead link-local from an earlier boot lingers in the neigh table,
# so "first fe80 in ip neigh" is routinely a stale entry.
phone() {
	ping -6 -c2 -W2 ff02::1%$IF >/dev/null 2>&1
	for a in $(ip neigh show dev $IF | awk '/fe80/{print $1}'); do
		ip -6 addr show dev $IF | grep -q "$a" && continue
		timeout 6 ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=no \
			-o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "user@$a%$IF" true </dev/null >/dev/null 2>&1 \
			&& { echo "$a"; return; }
	done
}
DTB_SRC=${DTB_SRC:-$K/dts/qcom/violet-sm6150.dtb}
cp "$DTB_SRC" $DTB
# ABL normally supplies RAM; under kexec nothing does, so give the DTB the real 4 GB map
fdtput -t s $DTB /memory device_type memory 2>/dev/null || { fdtput -c $DTB /memory; fdtput -t s $DTB /memory device_type memory; }
fdtput -t x $DTB /memory reg 0 0x80000000 0 0x80000000 1 0 0 0x7dd00000
A=$(phone); [ -n "$A" ] || { echo "phone not found"; exit 1; }; S="user@$A%$IF"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no"
$SSH $S 'uname -r' || exit 1
scp -q -o StrictHostKeyChecking=no $K/Image $DTB "user@[$A%$IF]:/tmp/" || exit 1
$SSH $S 'ls /tmp/kexec >/dev/null' 2>&1 || scp -q $HOME/violet-mainline/tools/kexec "user@[$A%$IF]:/tmp/kexec"
scp -q -o StrictHostKeyChecking=no $HOME/violet-mainline/wdt-disable.py "user@[$A%$IF]:/tmp/wdt.py"
$SSH $S "chmod +x /tmp/kexec; sudo -n sh -c '/tmp/kexec -u; /tmp/kexec -l /tmp/Image --initrd=/boot/initramfs --dtb=/tmp/main.dtb --command-line=\"$CMD\" 2>&1 | tail -1; sync; python3 /tmp/wdt.py ${WDT:-ext}; (sleep 1; /tmp/kexec -e) >/dev/null 2>&1 &'"
echo "kexec launched; waiting for link drop"
until ! ping -c1 -W1 $A%$IF >/dev/null 2>&1; do sleep 1; done
echo "dropped; waiting up to 3 min for the phone to come back (hold Power 15s if it hangs)"
for i in $(seq 1 90); do sleep 2; ip -br a show $IF 2>/dev/null | grep -q 169.254 && break; done
for i in $(seq 1 30); do sleep 3; A=$(phone); [ -n "$A" ] && $SSH user@$A%$IF true 2>/dev/null && break; done
$SSH user@$A%$IF 'uname -r; sudo -n cat /sys/fs/pstore/console-ramoops-0' > $HOME/violet-mainline/logs/kexec/kexec-$TAG-console.txt 2>&1
wc -l $HOME/violet-mainline/logs/kexec/kexec-$TAG-console.txt
