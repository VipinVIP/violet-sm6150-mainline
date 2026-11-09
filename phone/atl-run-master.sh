#!/bin/sh
# Launch an Android APK through the ATL *master* build (built in ~/atl-master, see patches-atl/).
# Differences from atl-run (the packaged ATL):
#   - touch handling fix for NewPipe's player controls (upstream MR !334, not in the Alpine package yet)
#   - ATL_DENSITY=140 so dp/sp sizes match a real phone of this screen (default 160 is ~14% too big)
#   - TextView text size/gravity, compound-drawable icon size and showSoftInput fixes
#   - the edge-swipe-to-back shim (disable with ATL_SWIPE_BACK=0)
# Fallback: ATL_USE_SYSTEM=1 (or a missing build) runs the packaged ATL through /usr/local/bin/atl-run.
#
# Usage: atl-run-master <apk> [activity]
set -eu

if [ $# -lt 1 ]; then
	echo "usage: $0 <apk> [activity]" >&2
	exit 2
fi

BUILD="${ATL_MASTER_DIR:-/home/user/atl-master/builddir}"
if [ "${ATL_USE_SYSTEM:-0}" = 1 ] || [ ! -x "$BUILD/android-translation-layer" ]; then
	exec /usr/local/bin/atl-run "$@"
fi

APK="$1"
ACT="${2:-}"

PHOC=$(pgrep -x phoc | head -1)
if [ -z "${PHOC:-}" ]; then
	echo "atl-run-master: no phoc running (not inside a Phosh session?)" >&2
	exit 1
fi
DBUS=$(tr '\0' '\n' < "/proc/$PHOC/environ" | grep ^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)

PRELOAD=""
if [ "${ATL_SWIPE_BACK:-1}" != 0 ] && [ -f /usr/local/lib/libatl-swipe-back.so ]; then
	PRELOAD=/usr/local/lib/libatl-swipe-back.so
fi

cd "$BUILD"
exec sudo -n -u user env \
	XDG_RUNTIME_DIR=/run/user/10000 \
	WAYLAND_DISPLAY=wayland-0 \
	DBUS_SESSION_BUS_ADDRESS="$DBUS" \
	GSK_RENDERER="${ATL_GSK_RENDERER:-vulkan}" \
	RUN_FROM_BUILDDIR= \
	LD_LIBRARY_PATH="$BUILD" \
	ATL_DENSITY="${ATL_DENSITY:-140}" \
	G_RESOURCE_OVERLAYS=/mobi/phosh/gmobile/devices/display-panels=/usr/local/share/violet-gmobile \
	LD_PRELOAD="$PRELOAD" \
	./android-translation-layer "$APK" ${ACT:+-l "$ACT"}
