#!/usr/bin/env bash
# Play ONE distinct cue, so the situation is audible without reading chat.
#
#   ./cue.sh ok         test passed / milestone
#   ./cue.sh fail       test failed
#   ./cue.sh fastboot   human must hold Power+Vol-Down
#   ./cue.sh power      human must power-cycle / reseat USB
#   ./cue.sh net        waiting for the phone on USB networking
#   ./cue.sh ask        a decision is waiting for the human
#   ./cue.sh alert [n]  the old generic attention.wav loop (n rounds, default 8)
#
# Sound files come from ./cues/ — spoken lines, regenerate with ./make-cues.py
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WHO=${1:-ask}
ROUNDS=${2:-1}

play_file() {
	local f=$1
	[ -f "$f" ] || { echo "cue.sh: missing $f (run ./make-cues.py)" >&2; return 1; }
	for p in paplay pw-play aplay; do
		if command -v "$p" >/dev/null 2>&1; then
			case $p in
			aplay) aplay -q "$f" 2>/dev/null && return 0 ;;
			*) "$p" "$f" 2>/dev/null && return 0 ;;
			esac
		fi
	done
	echo "cue.sh: no working audio player" >&2
	return 1
}

case $WHO in
alert) for i in $(seq 1 "$ROUNDS"); do play_file "$HERE/attention.wav" || exit 1; sleep 2.5; done ;;
*)     for i in $(seq 1 "$ROUNDS"); do play_file "$HERE/cues/$WHO.wav" || exit 1; sleep 0.6; done ;;
esac
