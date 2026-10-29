#!/bin/sh
# glissando-launch-system — the keyboard for sessions that are NOT the user's:
# the phrog greeter / phosh lock screen, which run as the `greetd` user inside a
# bwrap sandbox that only exposes /usr (so ~/.local is invisible there).
#
# Same contract as the hardened per-user launcher: sm.puri.OSK0 is a
# RequiredComponent of phosh.session, so this process must never exit while the
# session lives — every failure path ends in the system keyboard instead.
PREFIX=/usr/local/libexec/glissando
# The greeter's HOME is a tmpfs (/tmp-home); fall back to /tmp when the XDG
# state dir is not writable, so crash bookkeeping never aborts the launcher.
STATE="${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/glissando"
mkdir -p "$STATE" 2>/dev/null || STATE=/tmp/glissando-state
mkdir -p "$STATE" 2>/dev/null

fallback() {
	echo "glissando-launch-system: falling back to the system keyboard ($1)" >&2
	for osk in /usr/bin/phosh-osk-stevia /usr/bin/squeekboard; do
		[ -x "$osk" ] && exec "$osk" --allow-replacement
	done
	echo "glissando-launch-system: no system keyboard, idling" >&2
	while :; do sleep 3600; done
}

now=$(date +%s)
recent=0
if [ -f "$STATE/crashes" ]; then
	for t in $(cat "$STATE/crashes"); do
		[ $((now - t)) -lt 300 ] && recent=$((recent + 1))
	done
fi
[ "$recent" -ge 3 ] && fallback "3 crashes in 5 minutes"
[ -x "$PREFIX/bin/glissando" ] || fallback "glissando binary missing"
[ -d "$PREFIX/share/glissando/layouts" ] || fallback "layouts missing"

export GLISSANDO_DATA_DIR="$PREFIX/share/glissando"
start=$(date +%s)
"$PREFIX/bin/glissando" --allow-replacement
rc=$?

{
	[ -f "$STATE/crashes" ] && tail -n 5 "$STATE/crashes"
	echo "$now"
} > "$STATE/crashes.new" 2>/dev/null
mv "$STATE/crashes.new" "$STATE/crashes" 2>/dev/null

fallback "glissando exited rc=$rc after $(( $(date +%s) - start ))s"
