#!/bin/sh
# Restore the phone's userspace after userdata was lost. Steps, each separate and explicit:
#   host/phone-restore.sh check [backup.tar.gz]   verify everything needed is on the laptop (changes nothing)
#   host/phone-restore.sh flash                   WIPES userdata: flash the base pmOS rootfs (phone must be in fastboot)
#   host/phone-restore.sh files [backup.tar.gz]   (phone booted on the base rootfs, USB cable in) give it internet over USB,
#                                                 extract the backup over / and reinstall the packages from the saved list
#   host/phone-restore.sh finish                  reboot and print the verification checklist
# The `boot` partition is never touched (it keeps whatever kernel is flashed). dtbo stays erased.
# The default backup is the newest quick-*.tar.gz in device-backup/phone-userspace/ (see host/phone-backup.sh).
set -eu
cd "$(dirname "$0")/.."
BASE=${BASE_ROOTFS:-$HOME/violet-pmos/images-r9/rootfs-r9.img}
IF=enp0s20f0u4
STEP=${1:-check}; shift 2>/dev/null || true
BK=${1:-$(ls -t device-backup/phone-userspace/quick-*.tar.gz 2>/dev/null | head -1)}
SSH="ssh -6 -F /dev/null -T -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8"

addr() { ip -6 neigh show dev $IF 2>/dev/null | awk '/REACHABLE|STALE|DELAY/{print $1; exit}'; }
ph() { A=$(addr); [ -n "$A" ] || { ping -6 -c1 -W1 -I $IF ff02::1 >/dev/null 2>&1; A=$(addr); }; [ -n "$A" ] || { echo "phone not found on $IF" >&2; exit 1; }; $SSH "user@$A%$IF" "$@"; }

need() { [ -e "$1" ] || { echo "MISSING: $1" >&2; exit 1; }; echo "ok: $1"; }

case "$STEP" in
check)
	need "$BASE"
	[ -n "$BK" ] && need "$BK" || { echo "MISSING: no quick backup" >&2; exit 1; }
	tar -tzf "$BK" > /dev/null && echo "backup tar readable: $(tar -tzf "$BK" | wc -l) entries"
	for p in etc/init.d/violet-modem etc/init.d/rmtfs usr/local/bin/violet-audio-setup lib/modules/7.2.10-sm6150/modules.dep \
	         usr/local/lib/libatl-swipe-back.so home/user/atl/NewPipe.apk home/user/.local/opt/glissando/bin/glissando \
	         home/user/atl-master/builddir/android-translation-layer tmp/apk-world.txt etc/NetworkManager/system-connections; do
		tar -tzf "$BK" | grep -q "^$p" && echo "in backup: $p" || echo "NOT in backup: $p"
	done
	echo "boot image on the phone is not touched; current laptop copy: $(ls -la boot-mainline.img 2>/dev/null | awk '{print $5, $6, $7, $8}')"
	;;
flash)
	need "$BASE"
	fastboot devices | grep -q fastboot || { echo "no fastboot device: reboot the phone into the bootloader first" >&2; exit 1; }
	echo "This ERASES the phone's userdata (the whole pmOS rootfs) and writes $BASE."
	printf 'type WIPE-USERDATA to continue: '; read a; [ "$a" = WIPE-USERDATA ] || { echo aborted; exit 1; }
	fastboot flash userdata "$BASE"
	fastboot reboot
	echo "flashed. Wait for the phone to boot (~2 min), then: $0 files"
	;;
files)
	need "$BK"
	echo "== internet for the phone over USB (needs sudo on the laptop) =="
	sudo ip addr replace 172.16.42.2/16 dev $IF
	sudo sysctl -qw net.ipv4.ip_forward=1
	OUT=$(ip route show default | awk '{print $5; exit}')
	sudo iptables -t nat -C POSTROUTING -s 172.16.42.0/24 -o "$OUT" -j MASQUERADE 2>/dev/null || sudo iptables -t nat -A POSTROUTING -s 172.16.42.0/24 -o "$OUT" -j MASQUERADE
	sudo iptables -C FORWARD -i $IF -o "$OUT" -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -i $IF -o "$OUT" -j ACCEPT
	sudo iptables -C FORWARD -i "$OUT" -o $IF -j ACCEPT 2>/dev/null || sudo iptables -I FORWARD -i "$OUT" -o $IF -j ACCEPT
	ph 'sudo -n ip route replace default via 172.16.42.2 dev usb0; printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" | sudo -n tee /etc/resolv.conf >/dev/null; wget -qO- -T 8 http://example.com | head -c 20; echo'
	echo "== extracting the backup over / (as root, ownership preserved) =="
	ph 'sudo -n tar -xzf - -C /' < "$BK"
	echo "== reinstalling the package list =="
	ph 'sudo -n apk update >/dev/null; sudo -n apk add --no-progress $(cat /tmp/apk-world.txt | tr "\n" " ") 2>&1 | tail -5'
	echo "files restored. Next: $0 finish"
	;;
finish)
	ph 'sudo -n sync; sudo -n reboot' || true
	cat <<'CHK'
Phone is rebooting. After ~2 minutes verify (see docs/RESTORE.md for the commands):
  uname -v (boot image), wlan0 + internet, violet_speaker/violet_mic, GPU (phoc GL renderer FD612), sensors (ssccli),
  touch, Glissando running, NewPipe via the launcher, suspend/resume (loginctl suspend with an RTC wake).
CHK
	;;
*) echo "usage: $0 check|flash|files|finish [backup.tar.gz]" >&2; exit 2 ;;
esac
