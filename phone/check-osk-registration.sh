#!/bin/sh
# Ask gnome-session which clients are registered, and with which app id.
# Used to prove that the on-screen keyboard called RegisterClient (Phosh OSK
# requirement #3): without it gnome-session prints
# "Application 'sm.puri.OSK0.desktop' failed to register before timeout" and
# replaces the session with the failure page.
P=$(pgrep -x phoc | head -1)
[ -n "$P" ] || { echo "no phoc running"; exit 1; }
DB=$(tr '\0' '\n' < /proc/$P/environ | grep ^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)
export XDG_RUNTIME_DIR=/run/user/10000
export DBUS_SESSION_BUS_ADDRESS="$DB"

clients=$(gdbus call --session --dest org.gnome.SessionManager \
	--object-path /org/gnome/SessionManager \
	--method org.gnome.SessionManager.GetClients 2>/dev/null |
	grep -o '/org/gnome/SessionManager/Client[0-9]*')

total=0
found=""
for c in $clients; do
	total=$((total + 1))
	id=$(gdbus call --session --dest org.gnome.SessionManager --object-path "$c" \
		--method org.gnome.SessionManager.Client.GetAppId 2>/dev/null |
		sed "s/[(),']//g")
	[ -n "$id" ] && echo "$c -> $id"
	case "$id" in
		*sm.puri.OSK0*) found="$c ($id)" ;;
	esac
done

echo "clients: $total"
if [ -n "$found" ]; then
	echo "RESULT: OSK IS REGISTERED -> $found"
else
	echo "RESULT: OSK NOT REGISTERED"
fi
