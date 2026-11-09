#!/bin/sh
# install-shutdown-trace.sh - make every real shutdown log the OpenRC service sequence into
# the kernel log, so a freeze names the stage it died in.
#
# Why: this build's OpenRC (0.63.2) ignores rc_logger (measured: /etc/rc.conf set to
# rc_logger="/var/log/rc.log", restarting a service wrote nothing, file stayed 0 bytes).
# busybox init runs `::shutdown:/sbin/openrc shutdown` from /etc/inittab, so appending
# ">>/dev/kmsg 2>&1" puts every "Stopping <svc>" line into the kernel ring, where
#   * the 2 s ext4 harvester (/var/log/shutdown-harvest.log) copies it before the reset, and
#   * pstore keeps it across a warm reset.
#
# Usage: install-shutdown-trace.sh [--revert]
set -eu
INITTAB=/etc/inittab
BAK=/etc/inittab.bak-hermes

if [ "${1:-}" = "--revert" ]; then
	if [ -f "$BAK" ]; then cp "$BAK" "$INITTAB"; echo "reverted from $BAK"; else echo "no backup"; fi
	grep -n shutdown "$INITTAB"
	exit 0
fi

[ -f "$BAK" ] || cp "$INITTAB" "$BAK"

# Replace only the shutdown line, keep everything else byte-identical.
awk '
/^::shutdown:/ { print "::shutdown:/sbin/openrc shutdown >>/dev/kmsg 2>&1"; next }
{ print }
' "$BAK" > "$INITTAB"

echo "== inittab shutdown line now:"
grep -n shutdown "$INITTAB"
echo "== diff vs backup:"
diff "$BAK" "$INITTAB" || true
