#!/usr/bin/env bash
# suspend-resume-test.sh - one suspend/resume cycle, measured end to end, user-style.
#
# Plan item 4's verify step, automated: blank/suspend, wake, then check in this order
#   1. the kernel actually entered and left s2idle
#   2. what woke it            (/sys/power/pm_wakeup_irq + the matching /proc/interrupts line)
#   3. USB gadget survived     (UDC state, then a real command over USB)
#   4. ADSP survived           (remoteproc0 state, hexagonrpcd running, sensors)
#   5. WiFi came back
#
# Modes:
#   --loginctl   elogind suspend (what Phosh/us the power button does) -> the sleep hook runs
#   --sysfs      echo mem > /sys/power/state                            -> the hook does NOT run
#   --idle       set sleep-inactive-*=suspend and wait for the idle timer, then you press power
#
# Wake: --alarm S arms an RTC alarm S seconds out (default 20) so the cycle completes without
# a human; --no-alarm waits for the user's power-button press instead (and reports the wake
# source, which is the open question in the plan).
#
# Usage: suspend-resume-test.sh --loginctl|--sysfs|--idle [--no-alarm|--alarm 20]
set -uo pipefail
ROOT=/home/vipi/violet-mainline
MODE=loginctl
ALARM=20
for a in "$@"; do
	case $a in
	--loginctl|--sysfs|--idle) MODE=${a#--} ;;
	--no-alarm) ALARM=0 ;;
	--alarm) ;;
	*) case $a in [0-9]*) ALARM=$a ;; esac ;;
	esac
done
TAG=$(date +%F_%T); OUT=$ROOT/logs/suspend-$MODE-$TAG; mkdir -p "$OUT"
SSHOPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8
         -o LogLevel=ERROR -o ControlPath=none)

say() { echo "== $(date +%T) $*"; }
# The gadget re-enumerates after a resume repair, which recreates the host interface and
# drops its address: re-apply it before every USB ssh, like usb-shell.sh does.
usb_fix() {
	for c in /sys/class/net/enp0s20f0u*; do
		[ -e "$c" ] || continue
		ifc=$(basename "$c")
		sudo -n nmcli dev set "$ifc" managed no >/dev/null 2>&1
		sudo -n ip addr replace 172.16.42.2/16 dev "$ifc" >/dev/null 2>&1
		sudo -n ip link set "$ifc" up >/dev/null 2>&1
		return 0
	done
	return 1
}
usb_up() { usb_fix; }
wifi_up() { ping -c1 -W1 "${PHONE_WIFI:-<lan-ip>}" >/dev/null 2>&1; }
# "Reachable" must mean a shell answers, not just that an interface exists: after a resume
# the gadget re-enumerates with no IPv4 for a second or two, and after a power-button 10 s
# hold the phone reboots (uptime 40 s) - both used to be counted as "back" and produced an
# empty post-capture.
usb_ssh() { usb_fix && timeout 12 ssh "${SSHOPTS[@]}" user@172.16.42.1 'echo ok' >/dev/null 2>&1; }
wifi_ssh() { timeout 15 ssh "${SSHOPTS[@]}" user@<lan-ip> 'echo ok' >/dev/null 2>&1; }
reachable() { usb_ssh || (wifi_up && wifi_ssh); }

# Prefer USB when it is there, fall back to WiFi (the gadget dies on some resumes).
remote() {
	if usb_up && timeout 15 ssh "${SSHOPTS[@]}" user@172.16.42.1 "$1" 2>/dev/null; then return 0; fi
	timeout 20 ssh "${SSHOPTS[@]}" user@<lan-ip> "$1" 2>/dev/null
}

say "mode=$MODE alarm=${ALARM}s artefacts=$OUT"
reachable || { echo "phone not reachable on USB or WiFi - wake it first"; exit 2; }

# ---------------------------------------------------------------- pre
remote 'echo "up=$(cut -d. -f1 /proc/uptime)";
        echo "udc=$(cat /sys/class/udc/a600000.usb/state)";
        echo "adsp=$(cat /sys/class/remoteproc/remoteproc0/state)";
        echo "modem=$(cat /sys/class/remoteproc/remoteproc1/state)";
        echo "hex=$(sudo -n rc-status --all | grep -w hexagonrpcd-adsp-sensorspd | tr -s " ")";
        echo "suspend_entries=$(sudo -n dmesg | grep -c "PM: suspend entry")";
        echo "wake_irq_before=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"' | tee "$OUT/pre.txt"

if [ "$MODE" = idle ]; then
	say "setting sleep-inactive-* = suspend (60 s) through phosh's session bus"
	remote 'B=$(sudo -n sh -c "tr \"\\0\" \"\\n\" < /proc/$(pgrep -x phosh | head -1)/environ" | grep DBUS_SESSION_BUS_ADDRESS | cut -d= -f2-)
	        export DBUS_SESSION_BUS_ADDRESS="$B" XDG_RUNTIME_DIR=/run/user/10000 HOME=/home/user
	        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type suspend
	        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 60
	        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type suspend
	        gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 60
	        echo battery=$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type)' | tee "$OUT/keys.txt"
fi

# ---------------------------------------------------------------- trigger
case $MODE in
sysfs)
	say "suspending via /sys/power/state (sleep hook bypassed on purpose)"
	if [ "$ALARM" -gt 0 ]; then
		remote "sudo -n sh -c 'echo +$ALARM > /sys/class/rtc/rtc0/wakealarm; echo mem > /sys/power/state'" >/dev/null 2>&1 &
	else
		remote "sudo -n sh -c 'echo mem > /sys/power/state'" >/dev/null 2>&1 &
	fi
	;;
*)
	say "suspending via loginctl (elogind -> system-sleep hook)"
	if [ "$ALARM" -gt 0 ]; then
		remote "sudo -n sh -c 'echo +$ALARM > /sys/class/rtc/rtc0/wakealarm; loginctl suspend'" >/dev/null 2>&1 &
	else
		remote "sudo -n sh -c 'loginctl suspend'" >/dev/null 2>&1 &
	fi
	;;
esac

# ---------------------------------------------------------------- watch it go
went_down=0
for i in $(seq 1 40); do
	if ! reachable; then went_down=1; say "down after ~$((i * 3))s (suspended)"; break; fi
	sleep 3
done
if [ $went_down = 0 ]; then
	echo "never suspended within 120 s"
	[ "$MODE" = idle ] && echo "  (idle mode needs the screen off / no input; the phone may not have reached its timer)"
	exit 1
fi
[ "$ALARM" = 0 ] && { say "waiting for you to press POWER (up to 240 s)"; "$ROOT/cue.sh" power; }

# ---------------------------------------------------------------- wait for it to wake
woke=0
for i in $(seq 1 80); do
	if reachable; then woke=1; say "back after ~$((i * 3))s"; break; fi
	sleep 3
done
[ $woke = 0 ] && { echo "did not come back - press POWER once and rerun collection"; exit 3; }
sleep 6   # let the hook's post step finish (it waits up to 3 s, then rebinds)

# ---------------------------------------------------------------- post
sleep 4
remote 'echo "up=$(cut -d. -f1 /proc/uptime)";
        echo "udc=$(cat /sys/class/udc/a600000.usb/state)";
        echo "adsp=$(cat /sys/class/remoteproc/remoteproc0/state)";
        echo "modem=$(cat /sys/class/remoteproc/remoteproc1/state)";
        echo "hex=$(sudo -n rc-status --all | grep -w hexagonrpcd-adsp-sensorspd | tr -s " ")";
        echo "iio=$(sudo -n rc-status --all | grep -w iio-sensor-proxy | tr -s " ")";
        echo "suspend_entries=$(sudo -n dmesg | grep -c "PM: suspend entry")";
        echo "wake_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)";
        irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null); [ -n "$irq" ] && grep -E "^ *$irq:" /proc/interrupts;
        echo "-- suspend window:"; sudo -n dmesg | grep -E "PM: suspend|ep0out|not in L2|sleep-hook|udc-repair|recovering adsp" | tail -12;
        echo "-- wlan: $(ip -br addr show wlan0 2>/dev/null | awk "{print \$3}")"' | tee "$OUT/post.txt"

# ---------------------------------------------------------------- verdict
usb_up && echo "USB iface: present" || echo "USB iface: GONE"
timeout 20 ssh "${SSHOPTS[@]}" user@172.16.42.1 'echo USB-SSH-OK' >/dev/null 2>&1 \
	&& echo "USB shell: OK" || echo "USB shell: FAILED"
grep -q "udc=configured" "$OUT/post.txt" && echo "UDC: configured" || echo "UDC: NOT configured (gadget still broken)"
grep -q "adsp=running" "$OUT/post.txt" && echo "ADSP: running" || echo "ADSP: NOT running (sensors/audio broken)"
grep -q "wake_irq=" "$OUT/post.txt" && grep "wake_irq=" "$OUT/post.txt"
say "artefacts in $OUT"
