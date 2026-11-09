#!/bin/sh
# Diagnose the gnome-session failure dialog: which session is it in, and what
# does the current session log say?
LOG=/tmp/user-session.log

echo "== failure dialog processes =="
for p in $(pgrep -f gnome-session-failed); do
	ppid=$(awk '/^PPid:/{print $2}' /proc/$p/status 2>/dev/null)
	uid=$(awk '/^Uid:/{print $2}' /proc/$p/status 2>/dev/null)
	start=$(awk '{print $22}' /proc/$p/stat 2>/dev/null)
	echo "pid $p ppid $ppid uid $uid start_ticks $start"
done

echo "== gnome-session-binary processes =="
for p in $(pgrep -f gnome-session-binary); do
	uid=$(awk '/^Uid:/{print $2}' /proc/$p/status 2>/dev/null)
	ppid=$(awk '/^PPid:/{print $2}' /proc/$p/status 2>/dev/null)
	echo "pid $p uid $uid ppid $ppid"
done

echo "== session boundaries in log =="
grep -a '^=== ' "$LOG" | tail -4

echo "== register failures per session =="
awk '/^=== /{sess=$0; n=0} /failed to register before timeout/{n++} /^=== /{if (prev != "" && nprev > 0) print prev" -> "nprev" failure(s)"; prev=sess; nprev=0} {if ($0 ~ /failed to register before timeout/) nprev++} END {if (nprev > 0) print prev" -> "nprev" failure(s)"}' "$LOG"

echo "== current session log: session-relevant lines =="
awk '/=== Wed Oct 28 22:34:46/{f=1} f' "$LOG" |
	grep -aiE "required component|register|Oh no|failed to start|Unrecoverable" |
	grep -aviE "usbguard|telepathy|RealtimeKit|org.gnome.Calls|pipewire" |
	tail -8

echo "== does gnome-session list the OSK now? =="
P=$(pgrep -x phoc | head -1)
if [ -n "$P" ]; then
	DB=$(tr '\0' '\n' < /proc/$P/environ | grep ^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)
	export DBUS_SESSION_BUS_ADDRESS="$DB"
	export XDG_RUNTIME_DIR=/run/user/10000
	clients=$(gdbus call --session --dest org.gnome.SessionManager \
		--object-path /org/gnome/SessionManager \
		--method org.gnome.SessionManager.GetClients 2>/dev/null |
		grep -o '/org/gnome/SessionManager/Client[0-9]*')
	for c in $clients; do
		id=$(gdbus call --session --dest org.gnome.SessionManager --object-path "$c" \
			--method org.gnome.SessionManager.Client.GetAppId 2>/dev/null |
			sed "s/[(),']//g")
		case "$id" in *OSK*) echo "OSK client: $c -> $id" ;; esac
	done
fi
