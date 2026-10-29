#!/bin/sh
# kill-stale-session-procs.sh — reap daemons left behind by dead Phosh sessions.
#
# WHY THIS EXISTS:
# When a Phosh session dies abruptly (gm-session failure, phoc kill, kernel
# hiccup) its children are not always reaped: gnome-keyring-daemon, goa-daemon,
# feedbackd, evolution-source-registry, and even the session dbus-daemon keep
# running on the DEAD session bus. The damage is not just wasted RAM:
#   gnome-keyring-daemon --start --foreground --components=secrets
# prints "discover_other_daemon: 1" and EXITS when it finds the stale one,
# because the stale daemon holds $XDG_RUNTIME_DIR/keyring/control. The new
# session's D-Bus activation of org.freedesktop.secrets then never completes,
# anything touching secrets blocks for the full 120 s activation timeout, and
# gnome-session declares the session failed -> "Oh no! Something has gone wrong".
#
# The discriminator is the bus address: a process inherited from a previous
# session carries that session's DBUS_SESSION_BUS_ADDRESS. Anything whose bus
# differs from the current one, or whose bus socket no longer exists, is an
# orphan. Processes without the variable at all are left alone (too risky).
#
# Usage: kill-stale-session-procs.sh [--dry-run]

DRY=0
[ "$1" = "--dry-run" ] && DRY=1

# Current session bus: from our own environment, else from the compositor.
CUR="${DBUS_SESSION_BUS_ADDRESS:-}"
if [ -z "$CUR" ]; then
	for p in $(pgrep -x phoc 2>/dev/null); do
		CUR=$(tr '\0' '\n' < /proc/$p/environ 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
		[ -n "$CUR" ] && break
	done
fi
[ -n "$CUR" ] || { echo "no session bus found, refusing to kill anything" >&2; exit 1; }

me=$$
killed=0
for p in $(ls /proc | grep -E '^[0-9]+$'); do
	[ "$p" = "$me" ] && continue
	# only our own user's processes
	[ "$(awk '/^Uid:/{print $2}' /proc/$p/status 2>/dev/null)" = "$(id -u)" ] || continue
	b=$(tr '\0' '\n' < /proc/$p/environ 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
	[ -n "$b" ] || continue
	[ "$b" = "$CUR" ] && continue
	cmd=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | cut -c1-60)
	[ -n "$cmd" ] || continue
	if [ "$DRY" = 1 ]; then
		echo "would kill $p  $cmd"
	else
		kill -TERM "$p" 2>/dev/null && { echo "killed $p  $cmd"; killed=$((killed + 1)); }
	fi
done

if [ "$DRY" = 0 ]; then
	sleep 1
	# anything still ignoring SIGTERM from a dead session is not coming back
	for p in $(ls /proc | grep -E '^[0-9]+$'); do
		[ "$p" = "$me" ] && continue
		b=$(tr '\0' '\n' < /proc/$p/environ 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
		[ -n "$b" ] && [ "$b" != "$CUR" ] && kill -KILL "$p" 2>/dev/null
	done
	echo "reaped $killed stale process(es)"
fi
