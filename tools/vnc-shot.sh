#!/bin/bash
# Screenshot the phone's screen over VNC (wayvnc runs in the user session on 127.0.0.1:5900).
# Usage: tools/vnc-shot.sh [out.png]      (needs the phone on USB-NCM or WiFi; screen on and unlocked)
# A bare capture returns a flat grey 360x780 frame; a mouse move + pause forces a redraw -> real 1080x2340 frame.
set -u
OUT=${1:-/tmp/phone-screen.png}
ENV=${VNC_VENV:-$HOME/.local/share/violet-vncenv}
IF=${IF:-enp0s20f0u4}
[ -x "$ENV/bin/vncdo" ] || { python3 -m venv "$ENV" && "$ENV/bin/pip" install -q vncdotool; }
ping -6 -c1 -W1 ff02::1%$IF >/dev/null 2>&1
A=$(ip -6 neigh show dev $IF 2>/dev/null | awk '/REACHABLE|STALE|DELAY/{print $1; exit}')
if [ -n "$A" ]; then T="user@${A}%${IF}"; else T="user@<phone-ip>"; fi
# restart the tunnel every time (wayvnc is restarted with the session)
pkill -f "ssh -N -L 5901:127.0.0.1:5900" 2>/dev/null
ssh -N -f -L 5901:127.0.0.1:5900 -o ExitOnForwardFailure=yes -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$T" </dev/null >/dev/null 2>&1 || { echo "tunnel failed"; exit 1; }
sleep 2
timeout 90 "$ENV/bin/vncdo" -s 127.0.0.1::5901 move 180 300 pause 3 move 200 320 pause 3 capture "$OUT" && echo "saved $OUT"
