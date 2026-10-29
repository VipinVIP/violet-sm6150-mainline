#!/bin/sh
# phrog-logged.sh - run the phrog greeter session with its output captured.
#
# phrog-greetd-session pipes everything to `logger`, and no syslogd runs on this
# image, so a greeter failure is completely silent (2026-10-24: greetd reported
# "greeter exited without creating a session" and nothing else).
#
# Use it in place of the session command, either by hand:
#     sudo -n -u greetd env XDG_RUNTIME_DIR=/run/user/108 /usr/local/bin/phrog-logged
# or by pointing greetd at it:
#     [default_session]
#     command = "/usr/local/bin/phrog-logged"
#     user = "greetd"
#
# Then: tail -n 80 /tmp/phrog-session.log  (and /tmp/phoc.log for the compositor)
# Log per-kernel so a mainline boot cannot be overwritten by the next r10 boot.
LOG="/tmp/phrog-session-$(uname -r).log"
ln -sf "$LOG" /tmp/phrog-session.log 2>/dev/null
exec >"$LOG" 2>&1
echo "=== phrog-logged $(date) kernel=$(uname -r) uid=$(id -u) tty=$(tty 2>/dev/null) ==="
echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset} XDG_SESSION_ID=${XDG_SESSION_ID:-unset} XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unset}"
echo "--- cgroup (elogind tracks sessions by cgroup) ---"
cat /proc/self/cgroup 2>&1
echo "--- loginctl self: the session libseat must take control of ---"
loginctl session-status ${XDG_SESSION_ID:-} 2>&1 | head -10
echo "--- sessions ---"
loginctl list-sessions --no-pager 2>&1 | head -6
echo "--- seat0 ---"
loginctl seat-status seat0 2>&1 | head -4
echo "--- vt ---"
ls -l /dev/tty0 /dev/tty7 2>&1
printf "active vt: "; cat /sys/class/tty/tty0/active 2>&1
echo "--- /run/user/108 ---"
ls -ld /run/user/108 2>&1
echo "--- dri ---"
ls -l /dev/dri/ 2>&1 | head -4
cat /sys/class/drm/card*-DSI-1/status /sys/class/drm/card*-DSI-1/dpms 2>&1

# phoc writes its own failures (seat, DRM master, renderer) before phrog ever starts
exec /usr/libexec/phrog-greetd-session
