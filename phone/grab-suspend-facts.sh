#!/bin/sh
# Payload run on the phone the moment the USB gadget appears (see host/usb-shell.sh).
#
# Goal for this window, in order:
#  1. Prove or disprove that the USB disconnect is a suspend: the phone's own dmesg
#     records "PM: suspend entry" and the resume, and pm_wakeup_irq names the wake source.
#  2. Stop the phone idling into suspend for the duration of this session, so the cable
#     stops dying every ~70 s.  This is a DEBUGGING change (recorded in docs, reverted at
#     the end of the session) - suspend is one of the things under test.
#  3. Dump the modem/WiFi state, which is plan item 2.
echo "== payload start uptime=$(cut -d. -f1 /proc/uptime)"
echo "-- pm_wakeup_irq: $(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
echo "-- suspend/resume lines in dmesg:"
sudo -n dmesg | grep -aE "PM: suspend|PM: resume|Restarting tasks|dwc3|Freezing" | tail -20
echo "-- last boot time / uptime vs now:"
uptime
echo "-- netdevs: $(ls /sys/class/net | tr '\n' ' ')"
echo "-- remoteproc:"
for d in /sys/class/remoteproc/remoteproc*; do echo "   $(cat $d/name 2>/dev/null) $(cat $d/state 2>/dev/null)"; done
echo "-- violet-modem.log:"
tail -12 /var/log/violet-modem.log 2>/dev/null
echo "-- powermanagement policy before:"
sudo -n -u user env XDG_RUNTIME_DIR=/run/user/10000 \
  gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 2>&1
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 2>&1

# 2. disable idle suspend on the *session* bus (a plain ssh gsettings set goes to another bus
#    and does not persist - lesson recorded 2026-11-02)
PHOC=$(pgrep -x phoc | head -1)
if [ -n "$PHOC" ]; then
	DBUS=$(tr '\0' '\n' < /proc/$PHOC/environ | grep ^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)
	run() { sudo -n -u user env XDG_RUNTIME_DIR=/run/user/10000 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS="$DBUS" "$@"; }
	run gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type "'nothing'"
	run gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'nothing'"
	run gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 0
	echo "-- policy after: $(run gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 2>&1) / $(run gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 2>&1)"
else
	echo "-- no phoc process, cannot reach the session bus"
fi
echo "== payload done"
