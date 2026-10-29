#!/bin/sh
# seat-test.sh - reproduce the mainline greeter seat failure WITHOUT a reboot.
#
# Why this exists: `rc-service greetd start` runs the init script in the CALLER's
# context, so when invoked from an ssh shell the greeter inherits that ssh session's
# cgroup.  pam_elogind then sees "already in a session" and never creates one on
# seat0, phoc gets a session with no seat, and libseat reports
#   "No backend was able to open a seat" / "Unable to create seat: Function not implemented".
# That is NOT a mainline bug - it is an artefact of testing from ssh.
#
# This script moves itself into a fresh cgroup (so sd_pid_get_session() finds no
# session) before exec'ing greetd, which is the closest thing to a boot-time launch
# we can do without a kexec.  Everything the greeter sees is logged to
# /tmp/phrog-session.log by phrog-logged.sh.
#
# Run:  sudo ./seat-test.sh [seconds]
set -u
DUR=${1:-12}
LOG=/tmp/phrog-session.log
CGF=/etc/phrog/greetd-logged.toml

[ "$(id -u)" = 0 ] || { echo "run me with sudo"; exit 1; }
[ -x /usr/local/bin/phrog-logged.sh ] || { echo "missing /usr/local/bin/phrog-logged.sh"; exit 1; }
[ -f "$CGF" ] || { echo "missing $CGF"; exit 1; }

echo "before: self cgroup=$(cat /proc/self/cgroup)"

# cgroup v2 unified: drop into a fresh LEAF so this process is not inside a session.
if [ -w /sys/fs/cgroup/cgroup.procs ]; then
	mkdir -p /sys/fs/cgroup/greetd-selftest 2>/dev/null
	if echo $$ > /sys/fs/cgroup/greetd-selftest/cgroup.procs 2>/dev/null; then
		echo "moved to: $(cat /proc/self/cgroup)"
	else
		echo "WARN: could not move cgroup; this test will look like the ssh-session case"
	fi
else
	echo "WARN: cgroup v2 not writable; result will be inconclusive"
fi

rm -f "$LOG" /run/greetd.pid
echo "--- running greetd for ${DUR}s ---"
timeout "$DUR" /usr/sbin/greetd -c "$CGF" 2>&1 | tail -5

echo "--- phoc/phrog after run ---"
echo "phoc=$(pidof phoc) phrog=$(pidof phrog)"
echo "--- ${LOG} ---"
[ -f "$LOG" ] && head -24 "$LOG" || echo "(no greeter log - greetd never spawned it)"
echo
echo "VERDICT: 'XDG_SESSION_ID=unset' + a cgroup named after an ssh session (c<N>) = still the"
echo "ssh artefact.  A real 'session-N.scope'/'c<N>' that is NOT yours, plus SEAT in"
echo "loginctl, means PAM created a session and the fault is further down (seat or DRM)."
