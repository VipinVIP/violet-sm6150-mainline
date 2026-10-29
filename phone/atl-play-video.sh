#!/bin/sh
# Drive NewPipe playback with no UI interaction: ATL's `-u/--uri` delivers the
# URI as a VIEW intent to the app, so NewPipe opens the video and starts playing.
# Then report whether the GPU hung (hangcheck) - the crash we are chasing.
#
# usage: atl-play-video [URL]   (env GSK_RENDERER selects the GTK renderer)
set -u
APK=${APK:-/home/user/atl/NewPipe.apk}
URL=${1:-${URL:-https://www.youtube.com/watch?v=aqz-KE-bpKQ}}
GSK=${GSK_RENDERER:-vulkan}
LOG=/tmp/np-uri.log
WAIT=${WAIT:-75}

PHOC=$(pgrep -x phoc | head -1)
[ -z "${PHOC:-}" ] && { echo "no phoc" >&2; exit 1; }
DBUSV=$(tr '\0' '\n' < "/proc/$PHOC/environ" | grep ^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)

pkill -f "android-translation-layer $APK" 2>/dev/null
sleep 2

echo "== starting ATL with -u $URL (GSK_RENDERER=$GSK) =="
: > "$LOG"; chmod 666 "$LOG" 2>/dev/null
sudo -n -u user env XDG_RUNTIME_DIR=/run/user/10000 WAYLAND_DISPLAY=wayland-0 \
	DBUS_SESSION_BUS_ADDRESS="$DBUSV" GSK_RENDERER="$GSK" \
	nohup android-translation-layer "$APK" -u "$URL" >"$LOG" 2>&1 &

sleep "$WAIT"

echo "== alive? =="
pgrep -f "android-translation-layer $APK" | head -2
echo "== player/decode lines =="
grep -aiE "MediaCodec|codecName|Decoder |AudioTrack|h264|VideoDetailFragment|PlayerService|SIGSEGV|Fatal signal" "$LOG" | tail -12
echo "== last lines =="
tail -6 "$LOG"
echo "== dmesg gpu =="
dmesg 2>/dev/null | grep -aE "hangcheck|adreno_idle|gpu fault|iova|recover" | tail -6
