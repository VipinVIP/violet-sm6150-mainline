#!/bin/sh
# glissando-launch (hardened) — session keyboard launcher.
#
# WHY THIS DIFFERS FROM THE UPSTREAM packaging/device/glissando-launch:
# sm.puri.OSK0 is listed in phosh.session's RequiredComponents, so if this
# component exits, gnome-session kills the whole session and shows
# "Oh no! Something has gone wrong / Please log out and try again".
# Upstream only falls back to the system keyboard on a *non-zero* exit; a clean
# exit (which is what happens when another input method already holds the seat:
# "lost sm.puri.OSK0") leaves the required component dead and takes the session
# down with it. Here every exit path that glissando can take ends in a working
# keyboard, so the component only dies when the session itself does.
PREFIX="${GLISSANDO_PREFIX:-$HOME/.local/opt/glissando}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/glissando"
mkdir -p "$STATE"

fallback() {
	echo "glissando-launch: falling back to the system keyboard ($1)" >&2
	for osk in /usr/bin/phosh-osk-stevia /usr/bin/squeekboard; do
		[ -x "$osk" ] && exec "$osk" --allow-replacement
	done
	echo "glissando-launch: no system keyboard found, staying alive idle" >&2
	while :; do sleep 3600; done
}

# Crash bookkeeping: 3 failures inside 5 minutes means glissando is not viable
# in this environment, so stop trying and use the system keyboard.
now=$(date +%s)
recent=0
if [ -f "$STATE/crashes" ]; then
	for t in $(cat "$STATE/crashes"); do
		[ $((now - t)) -lt 300 ] && recent=$((recent + 1))
	done
fi
[ "$recent" -ge 3 ] && fallback "3 crashes in 5 minutes"
[ -x "$PREFIX/bin/glissando" ] || fallback "glissando binary missing"

export GLISSANDO_DATA_DIR="$PREFIX/share/glissando"
start=$(date +%s)
"$PREFIX/bin/glissando" --allow-replacement
rc=$?
end=$(date +%s)

# Exiting cleanly is NOT success here: it means the seat was taken by another
# input method, i.e. there is no keyboard of ours on screen. Any exit from a
# required component has to end in a fallback keyboard.
{
	[ -f "$STATE/crashes" ] && tail -n 5 "$STATE/crashes"
	echo "$now"
} > "$STATE/crashes.new" 2>/dev/null
mv "$STATE/crashes.new" "$STATE/crashes" 2>/dev/null

fallback "glissando exited rc=$rc after $((end - start))s"
