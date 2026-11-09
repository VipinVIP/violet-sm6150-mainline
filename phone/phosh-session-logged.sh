#!/bin/sh
# Session wrapper for greetd's [initial_session].
#
# phosh-session's stdout/stderr used to go to greetd's stdout, i.e. nowhere, so
# every "session crashed" left no trace.  This logs the whole session, records
# the exit status/signal, and turns on core dumps for the session's children.
LOG=/tmp/user-session.log

{
	echo "=== $(date 2>/dev/null) phosh-session start, kernel $(uname -r) ==="
} >> "$LOG" 2>&1

# greetd's original initial_session command was
#   env XDG_CURRENT_DESKTOP=Phosh:GNOME /usr/bin/phosh-session
# and that variable is load-bearing: Phosh's skin, the OSK autostart
# (OnlyShowIn=Phosh) and gnome-session's target all key off it.
export XDG_CURRENT_DESKTOP=Phosh:GNOME
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=phosh

ulimit -c unlimited 2>/dev/null
echo "core_pattern=$(cat /proc/sys/kernel/core_pattern 2>/dev/null) ulimit_c=$(ulimit -c)" >> "$LOG"

/usr/bin/phosh-session >> "$LOG" 2>&1
rc=$?

{
	echo "=== $(date 2>/dev/null) phosh-session EXITED rc=$rc"
	# 128+n => killed by signal n; name it so the log is readable without a table.
	if [ "$rc" -gt 128 ] 2>/dev/null; then
		sig=$((rc - 128))
		case $sig in
			6)  echo "    signal 6 = SIGABRT (assertion/abort)" ;;
			7)  echo "    signal 7 = SIGBUS (bad memory access)" ;;
			9)  echo "    signal 9 = SIGKILL (OOM killer or kill -9)" ;;
			11) echo "    signal 11 = SIGSEGV (segfault)" ;;
			15) echo "    signal 15 = SIGTERM (asked to stop)" ;;
			*)  echo "    signal $sig" ;;
		esac
	fi
	echo "=== last phosh/phoc/osk state: $(ps -eo comm | grep -cE 'phosh|phoc') procs ==="
} >> "$LOG" 2>&1

sync
exit "$rc"
