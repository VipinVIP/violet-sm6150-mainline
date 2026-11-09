#!/bin/sh
# Back up the phone's userspace (everything that lives in userdata / the pmOS rootfs) to the laptop.
#   host/phone-backup.sh quick   config + scripts + firmware + home (a few MB, seconds)  [default]
#   host/phone-backup.sh full    the whole root filesystem (~2-3 GB, minutes)
# Reaches the phone over USB-NCM link-local if present, else WiFi (set PHONE=user@host to override).
# Nothing is written to the phone. Output: device-backup/phone-userspace/<kind>-<date>.tar.gz
set -eu
KIND=${1:-quick}
# paths (relative to /) skipped in the quick backup: personal data, caches, rebuildable crates/sources
QEXC="--exclude=home/user/.cache --exclude=home/user/.local/share/Trash --exclude=home/user/Documents --exclude=home/user/Downloads --exclude=home/user/Music --exclude=home/user/Pictures --exclude=home/user/Videos --exclude=home/user/Projects --exclude=home/user/Public --exclude=home/user/Templates --exclude=home/user/Desktop --exclude=home/user/.local/share/org.gnome.SoundRecorder --exclude=home/user/core --exclude=home/user/glissando --exclude=home/user/.cargo --exclude=home/user/.m2"
OUT=$(dirname "$0")/../device-backup/phone-userspace
mkdir -p "$OUT"
if [ -z "${PHONE:-}" ]; then
	IF=enp0s20f0u4
	A=$(ip -6 neigh show dev $IF 2>/dev/null | awk '/REACHABLE|STALE|DELAY/{print $1; exit}')
	if [ -n "$A" ]; then PHONE="user@$A%$IF"; else PHONE=user@<lan-ip>; fi
fi
SSH="ssh -6 -F /dev/null -T -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8"
case "$PHONE" in *%*) ;; *) SSH="ssh -F /dev/null -T -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8" ;; esac
F="$OUT/$KIND-$(date +%Y%m%d-%H%M).tar.gz"
case "$KIND" in
quick)
	# busybox tar has no --ignore-failed-read: build the list of paths that exist first.
	# apk world + the installed-package list make a clean reinstall possible.
	# Personal files and caches are NOT backed up; compiled things (glissando install, ATL build tree, NewPipe APK) ARE, as they are.
	$SSH "$PHONE" 'sudo -n sh -s' > "$F" <<REMOTE
apk info -v | sort > /tmp/apk-installed.txt; cp /etc/apk/world /tmp/apk-world.txt
L=/tmp/backup-list.txt; : > \$L
for p in tmp/apk-installed.txt tmp/apk-world.txt etc/init.d etc/conf.d etc/local.d etc/runlevels etc/elogind \
  etc/phrog etc/modprobe.d etc/sysctl.d etc/NetworkManager etc/xdg/autostart etc/sleep-inhibitor.conf etc/apk etc/udev/rules.d etc/pam.d \
  etc/fstab etc/hostname usr/local lib/firmware lib/modules/7.2.10-sm6150 var/lib/rmtfs home/user; do [ -e /\$p ] && echo \$p >> \$L; done
exec tar -czf - -C / $QEXC -T \$L
REMOTE
	;;
full)
	# busybox tar has no --one-file-system: list the top-level directories that hold persistent data
	$SSH "$PHONE" 'sudo -n sh -c "L=/tmp/backup-full.txt; : > \$L; for p in bin etc home lib opt root sbin srv usr var; do [ -e /\$p ] && echo \$p >> \$L; done; \
	  tar -czf - -C / --exclude=var/cache/apk --exclude=home/user/.cache --exclude=home/user/glissando/target --exclude=home/user/.cargo -T \$L"' > "$F"
	;;
*) echo "usage: $0 quick|full" >&2; exit 2 ;;
esac
sz=$(stat -c %s "$F")
[ "$sz" -gt 1000 ] || { echo "backup too small ($sz B), something failed: $F" >&2; exit 1; }
tar -tzf "$F" >/dev/null && echo "OK $F ($sz bytes)"
