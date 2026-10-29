#!/bin/sh
# Launch an Android APK through the Android Translation Layer inside the running
# Phosh session.
#
# Renderer: default is vulkan (upstream behaviour) - GL was measurably slower and
# crashed too, so the GPU hang is the real bug, not the renderer choice. Override
# with ATL_GSK_RENDERER=gl|cairo when isolating a rendering issue.
set -eu

if [ $# -lt 1 ]; then
	echo "usage: $0 <apk> [activity]" >&2
	exit 2
fi

APK="$1"
ACT="${2:-}"

PHOC=$(pgrep -x phoc | head -1)
if [ -z "${PHOC:-}" ]; then
	echo "atl-run: no phoc running (not inside a Phosh session?)" >&2
	exit 1
fi
DBUS=$(tr '\0' '\n' < "/proc/$PHOC/environ" | grep ^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)

exec sudo -n -u user env \
	XDG_RUNTIME_DIR=/run/user/10000 \
	WAYLAND_DISPLAY=wayland-0 \
	DBUS_SESSION_BUS_ADDRESS="$DBUS" \
	GSK_RENDERER="${ATL_GSK_RENDERER:-vulkan}" \
	android-translation-layer "$APK" ${ACT:+-l "$ACT"}
