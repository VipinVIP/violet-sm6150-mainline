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
# phosh 0.58 (Alpine edge) starts its own OSK — /usr/bin/phosh-osk-stevia — from the
# shell. If it already owns the input seat when we come up, glissando refuses to start
# ("another input method is already running on this seat") and the session ends up on
# stevia. The retry loop below frees the seat before every attempt.
# Try more than once: phosh may (re)start its own OSK at any point during session
# bring-up, and glissando exits immediately if the seat is taken when it starts.
# Three short attempts cover the orderings we have actually observed, and the
# fallback below stays as the last resort so a keyboard always exists.
attempt=0
rc=1
while [ "$attempt" -lt 3 ]; do
	attempt=$((attempt + 1))
	for rival in phosh-osk-stevia squeekboard; do
		if pkill -f "$rival" 2>/dev/null; then
			sleep 1
		fi
	done
	"$PREFIX/bin/glissando" --allow-replacement
	rc=$?
	# 0 means it ran a whole session and exited normally: do not restart it
	[ "$rc" -eq 0 ] && break
	elapsed=$(( $(date +%s) - start ))
	[ "$elapsed" -gt 10 ] && break		# it survived a while then died: real crash, not the race
	echo "glissando-launch-system: attempt $attempt failed after ${elapsed}s (rc=$rc), retrying" >&2
	sleep 2
done

{
	[ -f "$STATE/crashes" ] && tail -n 5 "$STATE/crashes"
	echo "$now"
} > "$STATE/crashes.new" 2>/dev/null
mv "$STATE/crashes.new" "$STATE/crashes" 2>/dev/null

fallback "glissando exited rc=$rc after $(( $(date +%s) - start ))s"
