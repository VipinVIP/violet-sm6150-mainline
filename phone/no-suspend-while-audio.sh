#!/bin/sh
# no-suspend-while-audio.sh - plan item 4's last criterion: with audio playing the phone
# must NOT suspend even though the idle timer is armed.
#
# Run this as the LOGIN USER (not root): both gsettings (dconf on the session bus) and
# paplay (PulseAudio auth) fail as root - measured 2026-11-02, the first version of this
# script silently tested nothing because of that.  Root is used only for dmesg and the RTC.
# An RTC alarm is armed as a safety net so a wrong answer cannot strand the phone asleep.
set -u
export XDG_RUNTIME_DIR=/run/user/10000 HOME=/home/user
B=$(sudo -n sh -c "tr \"\\0\" \"\\n\" < /proc/\$(pgrep -x phosh | head -1)/environ" 2>/dev/null | grep DBUS_SESSION_BUS_ADDRESS | cut -d= -f2-)
export DBUS_SESSION_BUS_ADDRESS="$B"
LOG=/tmp/no-suspend-while-audio.log
: > "$LOG"
say() { echo "$(date +%T) $*" | tee -a "$LOG"; }
P=org.gnome.settings-daemon.plugins.power

before=$(sudo -n dmesg | grep -c "PM: suspend entry")
say "begin: suspend_entries=$before"

say "arming idle timer (suspend after 60 s idle)"
gsettings set $P sleep-inactive-battery-type suspend
gsettings set $P sleep-inactive-battery-timeout 60
gsettings set $P sleep-inactive-ac-type suspend
gsettings set $P sleep-inactive-ac-timeout 60
say "keys now: $(gsettings get $P sleep-inactive-battery-type) / $(gsettings get $P sleep-inactive-ac-type)"

say "safety net: RTC alarm in 180 s"
echo +180 | sudo -n tee /sys/class/rtc/rtc0/wakealarm >/dev/null

say "playing 190 s through violet_speaker"
pactl set-sink-mute violet_speaker 0 2>/dev/null
pactl set-sink-volume violet_speaker 55% 2>/dev/null
setsid paplay /tmp/longtone.wav </dev/null >/dev/null 2>&1 &
sleep 3
inputs=$(pactl list short sink-inputs 2>/dev/null | wc -l)
say "sink-inputs after 3 s: $inputs (0 means it is NOT playing and this test is void)"
[ "$inputs" = 0 ] && { say "ABORT: no audio stream"; }

i=0
while [ $i -lt 15 ]; do
	sleep 10
	i=$((i + 1))
	now=$(sudo -n dmesg | grep -c "PM: suspend entry")
	ninputs=$(pactl list short sink-inputs 2>/dev/null | wc -l)
	say "t+$((i * 10))s streams=$ninputs suspend_entries=$now"
	[ "$now" != "$before" ] && { say "FAILED: suspended while playing"; break; }
done

now=$(sudo -n dmesg | grep -c "PM: suspend entry")
if [ "${inputs:-0}" != 0 ] && [ "$now" = "$before" ]; then
	say "RESULT: PASSED - audio stream live for 150 s and the phone did not suspend"
else
	say "RESULT: inconclusive (streams=$inputs suspend_delta=$((now - before)))"
fi

pkill -f longtone.wav 2>/dev/null
say "restoring idle timer to nothing"
gsettings set $P sleep-inactive-battery-type nothing
gsettings set $P sleep-inactive-ac-type nothing
echo 0 | sudo -n tee /sys/class/rtc/rtc0/wakealarm >/dev/null 2>&1
say "keys restored: $(gsettings get $P sleep-inactive-battery-type)"
