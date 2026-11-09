#!/bin/sh
# Run a client on the phone with WAYLAND_DEBUG=client and keep only the text-input / focus lines on the laptop.
# Usage: tools/wl-debug-run.sh <out.log> <cmd...>   (run in the background; the log is written line by line)
# Used for the OSK investigation (docs/PROGRESS.md 2026-11-07): `zwp_text_input_v3#N.enable()` right after
# `wl_keyboard.enter` means the app asked for the keyboard. busybox grep has no --line-buffered, hence awk.
cd "$(dirname "$0")/.." || exit 1
L=$1; shift
exec ./rssh "export XDG_RUNTIME_DIR=/run/user/10000 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbus-MRv8LQGqQL WAYLAND_DEBUG=client; exec $* 2>&1 | awk '/text_input|zwp_input|enter|leave|focus/{print; fflush()}'" > "$L" 2>&1
