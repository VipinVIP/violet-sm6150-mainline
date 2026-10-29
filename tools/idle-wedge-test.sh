#!/bin/bash
# idle-wedge-test.sh - run one phrog/phoc boot while watching which CPU stops.
#
# Tests the 2026-10-24 finding from the ramoops ring: five RCU stall episodes all
# report "these CPUs still haven't responded to the NMI: 7" with one grace period
# (g=49361) never completing, and the kernel advertises
#   cpuidle PSCI: Initialized CPU PM domain topology using OSI mode
# with idle states inherited from talos.dtsi (EVK values; violet's board DTS has no
# psci/idle override at all).  Hypothesis: CPU7 enters a PSCI OSI idle state it never
# comes back from, which starves RCU and then wedges whatever holds a lock it owns.
#
# Usage: idle-wedge-test.sh [variant] [phrog|phoc]      (default: baseline phrog)
#
#   baseline        current tree, current cmdline       (repro)
#   cpuidle-off     EXTRA_CMDLINE=cpuidle.off=1        (no cpuidle at all)
#   teo             EXTRA_CMDLINE=cpuidle.governor=teo (different state selection)
#   maxcpus7        EXTRA_CMDLINE=maxcpus=7            (CPU7 excluded entirely)
#   no-idle-dtb     violet-sm6150-noidle.dtb           (no PSCI idle states, WFI only)
#   no-a76-idle-dtb violet-sm6150-noa76idle.dtb        (only the two A76 lose idle)
#
# Every variant is a cmdline or DTB change: no kernel rebuild.
#
# Instrumentation notes (learned the hard way 2026-10-24):
#  * kexec-test.sh BLOCKS until the phone answers again, so it runs in the background
#    here and we grab mainline ourselves the moment it answers (~10 s after kexec).
#  * kexec-test.sh arms the APSS watchdog to 'ext' (~32 s, 0xfffff ticks at 32 kHz) as
#    a crash fallback and mainline has no driver to pet it - left alone every run
#    "hangs" at 32 s and comes back on r10, which looks exactly like the wedge.
#    We disable it (EN=0) from inside mainline as soon as ssh answers; the armed
#    watchdog remains as recovery for a hang in that first ~15 s window.
#  * pmOS's initramfs silences the console after switch_root, so the persistent ring
#    goes quiet at ~10 s; we raise console_loglevel back to 8 from userspace so the
#    ring keeps the interesting part.
#
# Expected read, in order of strength:
#   maxcpus7 / no-idle-dtb / cpuidle-off survive 5+ min -> the wedge is PSCI idle, not DRM
#   only maxcpus7 survives                             -> CPU7 specifically
#   only no-a76-idle-dtb survives                      -> the A76 per-core states
#   nothing survives                                   -> back to DRM/compositor theories
set -uo pipefail
VARIANT=${1:-baseline}
MODE=${2:-phrog}
VM=$HOME/violet-mainline
DTS=$VM/kernel/linux-7.2.10/arch/arm64/boot/dts/qcom

case "$VARIANT" in
	baseline)        EXTRA="" ;                                DTB_SRC="" ; KEEP_WDT=${KEEP_WDT:-1} ;;
	cpuidle-off)     EXTRA="cpuidle.off=1" ;                   DTB_SRC="" ;;
	teo)             EXTRA="cpuidle.governor=teo" ;            DTB_SRC="" ;;
	maxcpus7)        EXTRA="maxcpus=7" ;                       DTB_SRC="" ;;
	no-idle-dtb)     EXTRA="" ;        DTB_SRC=$DTS/violet-sm6150-noidle.dtb ;;
	no-a76-idle-dtb) EXTRA="" ;        DTB_SRC=$DTS/violet-sm6150-noa76idle.dtb ;;
	nodeepcluster)   EXTRA="" ;        DTB_SRC=$DTS/violet-sm6150-nodeepcluster.dtb ;;
	*) echo "unknown variant '$VARIANT'"; sed -n '13,20p' "$0"; exit 1 ;;
esac

if [ -n "$DTB_SRC" ] && [ ! -f "$DTB_SRC" ]; then
	echo "missing $DTB_SRC - rebuild with:"
	echo "  cd $VM/kernel/linux-7.2.10 && make ARCH=arm64 LLVM=1 qcom/$(basename "$DTB_SRC" .dtb).dtb"
	exit 1
fi

O="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=4"
ifaces() { ip -br link | awk '/^enp0s20f0u|^usb[0-9]/{print $1}'; }
addr()  { for I in $(ifaces); do ping -c1 -W1 ff02::1%$I >/dev/null 2>&1
	     A=$(ip neigh show dev $I | awk '/fe80/{print $1; exit}'); [ -n "$A" ] && { echo "$A $I"; return 0; }; done; return 1; }
relver() { set -- $(addr) 2>/dev/null || return 1; [ $# -ge 2 ] || return 1; ssh $O "user@$1%$2" 'uname -r' 2>/dev/null; }
rssh() { local t a i; t=$(addr) || return 1; a=${t%% *}; i=${t##* }; ssh $O "user@$a%$i" "$@"; }
rscp() { local t a i; t=$(addr) || return 1; a=${t%% *}; i=${t##* }; scp -q $O "$1" "user@[$a%$i]:$2"; }

echo "=== variant=$VARIANT mode=$MODE extra='$EXTRA' dtb=${DTB_SRC:-tree default}"
[ -n "$DTB_SRC" ] && export DTB_SRC
# WDT=off: kexec-test.sh's default 'ext' arms the APSS watchdog to bark at ~32 s and bite
# at ~32.7 s.  Mainline has no driver to handle or pet it, so the bark storms IRQs and the
# eMMC controller dies (measured 2026-10-24: mmc0 cmd-interrupt timeout at 33.27 s), which
# looks exactly like the wedge under test.  Cost: a real hang now needs a manual power-hold.
WDT=${WDT:-off} EXTRA_CMDLINE="$EXTRA" $VM/kexec-test.sh "idle-$VARIANT" > "$VM/idle-$VARIANT-kexec.log" 2>&1 &
KJPID=$!

# --- grab mainline the moment it answers, before the reboot can take it away
echo "=== waiting for mainline to answer"
REL=""
for i in $(seq 1 60); do
	sleep 2
	R=$(relver)
	case "$R" in 7.*) REL=$R; break ;; esac
done
if [ -z "$REL" ]; then
	echo "!! mainline never answered (died before userspace). kexec log:"
	tail -5 "$VM/idle-$VARIANT-kexec.log"
	wait $KJPID 2>/dev/null
	exit 2
fi
echo "=== mainline up: $REL"
set -- $(addr); A=$1; I=$2; S="user@$A%$I"

rscp "$VM/wdt-disable.py" /tmp/wdt2.py
rscp "$VM/tools/cpu-wedge-watch.sh" /tmp/cpu-wedge-watch.sh
if [ "${KEEP_WDT:-0}" = 1 ]; then
	WDTRUN='echo "watchdog LEFT ARMED (bites ~32s: auto-recovery, but caps observation at 32s)"'
else
	WDTRUN='sudo -n python3 /tmp/wdt2.py off 2>&1 | tail -1'
fi
rssh "chmod +x /tmp/cpu-wedge-watch.sh; $WDTRUN
	echo 8 | sudo -n tee /proc/sys/kernel/printk >/dev/null
	printf 'cpuidle-lines=%s online=%s\n' \"\$(sudo -n dmesg | grep -c cpuidle)\" \"\$(cat /sys/devices/system/cpu/online)\""

rssh 'nohup /tmp/cpu-wedge-watch.sh 900 /tmp/wedge.log >/dev/null 2>&1 & sleep 1; echo "watcher=$(pgrep -f cpu-wedge-watch | head -1)"'

# --- start the session
case "$MODE" in
phrog) rssh 'sudo -n rc-service greetd restart >/dev/null 2>&1; sleep 3; echo "greetd ok phoc=$(pidof phoc) phrog=$(pidof phrog)"' ;;
phoc)  rssh 'sudo -n cp /etc/conf.d/greetd /etc/conf.d/greetd.orig
	sudo -n sed -i "s#^cfgfile=.*#cfgfile=\"/etc/phrog/greetd-phoconly.toml\"#" /etc/conf.d/greetd; sync
	sudo -n rc-service greetd restart >/dev/null 2>&1; sleep 6
	sudo -n cp /etc/conf.d/greetd.orig /etc/conf.d/greetd; sync
	echo "phoc=$(pidof phoc)"' ;;
*) echo "mode must be phrog or phoc"; exit 1 ;;
esac

# verify a session exists; greetd crashes silently on mainline and a "survival" with
# no phoc/phrog is meaningless (2026-10-24: two runs were thrown away for exactly this)
if ! rssh 'pgrep -x phoc >/dev/null'; then
	echo "!! greetd produced no phoc; falling back to the greeter session directly"
	rssh 'nohup /usr/libexec/phrog-greetd-session > /tmp/greeter.log 2>&1 & sleep 6; echo "direct: phoc=$(pidof phoc) phrog=$(pidof phrog)"'
fi
rssh 'echo "session: phoc=$(pidof phoc) phrog=$(pidof phrog)"; pgrep -x phoc >/dev/null || { echo "!! SESSION DID NOT START - run invalid"; sudo -n rc-service greetd status 2>&1 | head -2; tail -5 /tmp/greeter.log 2>/dev/null; }' 

# --- watch for up to 6 min; a dead ssh stream is a result too
echo "=== watching (a dropped stream = the hang)"
timeout 360 rssh 'tail -f /tmp/wedge.log' || echo "(ssh stream ended)"

echo "=== post-run"
sleep 30
R=$(relver)
case "$R" in
	7.*) echo "SURVIVED: still on mainline"
	     rssh 'echo "wedged-lines=$(grep -c WEDGED /tmp/wedge.log)"; tail -4 /tmp/wedge.log
		echo "stalls=$(sudo -n dmesg | grep -c "detected stalls")"' ;;
	*)   echo "DIED: back on ${R:-nothing} - reading its ring" ;;
esac
wait $KJPID 2>/dev/null
L=$(ls -t $VM/kexec-idle-$VARIANT-console.txt 2>/dev/null | head -1)
echo "=== pstore: $L stalls=$(grep -ac 'detected st' "$L" 2>/dev/null) nmi-fails=$(grep -ac "haven.t responded" "$L" 2>/dev/null)"
grep -a "haven.t responded\|detected st" "$L" 2>/dev/null | tail -4
