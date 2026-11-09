#!/usr/bin/env bash
# reboot-test.sh - one instrumented reboot: capture the OpenRC stop sequence and the last
# kernel seconds, from the laptop side, and get the phone back over USB.
#
# Why it is built this way (measured, not assumed):
#  * The 2026-11-02 pstore panic shows the phone does NOT hang in a service stop: OpenRC's
#    "Stopping ..." never blocks.  A CPU stops answering NMIs ~21 s after the modem stop,
#    then a watchdog panic wedges in "SMP: stopping secondary CPUs".  So the evidence has to
#    cover (a) which service was being stopped, and (b) the last kernel lines before the wedge.
#  * /var/log is on ext4: rc.log and a 2 s kernel harvester that syncs both survive a cold
#    power-off.  pstore survives only a warm reset.
#  * The USB gadget goes away during the reboot, so recovery has to wait >= 120 s for sshd
#    (usb-shell.sh does that).
#
# Usage: reboot-test.sh [<how>]     how = ssh (default) | rc-shutdown | power-menu
set -uo pipefail
HOW=${1:-ssh}
ROOT=/home/vipi/violet-mainline
TAG=$(date +%F_%T)
OUT=$ROOT/logs/reboot-$TAG
mkdir -p "$OUT"
SSH=/tmp/usbssh          # ControlMaster wrapper for user@172.16.42.1 (usb-shell.sh sets it up)
LOG=/var/log/shutdown-harvest.log

say() { echo "== $(date +%T) $*"; }

say "artefacts: $OUT"

# ---------------------------------------------------------------- 1. preconditions
say "1. rc_logger, clean logs, WiFi state"
$SSH "sudo -n sed -i 's|^#\?rc_logger=.*|rc_logger=\"/var/log/rc.log\"|' /etc/rc.conf
      grep -n '^rc_logger' /etc/rc.conf
      sudo -n rm -f /var/log/rc.log $LOG; sudo -n touch /var/log/rc.log $LOG
      echo wlan0=\$(ip -br link show wlan0 2>/dev/null | awk '{print \$2}')
      echo uptime=\$(cut -d. -f1 /proc/uptime)
      echo modem=\$(cat /sys/class/remoteproc/remoteproc1/state)
      echo softlockup_panic=\$(cat /proc/sys/kernel/softlockup_panic)" | tee "$OUT/pre.txt"

# ---------------------------------------------------------------- 2. kernel harvester (phone side)
say "2. 2 s kernel harvester on the phone, synced to ext4"
$SSH "sudo -n sh -c 'setsid sh -c \"while :; do { echo \\\"--- \\\$(date +%T) up=\\\$(cut -d. -f1 /proc/uptime)\\\"; dmesg | tail -25; } >> $LOG; sync; sleep 2; done\" </dev/null >/dev/null 2>&1 &'
      sleep 3; sudo -n tail -3 $LOG" | tee "$OUT/harvester-start.txt"

# ---------------------------------------------------------------- 3. laptop-side live stream
say "3. live dmesg stream on the laptop (dies with the cable, that is expected)"
( timeout 400 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 -o LogLevel=ERROR user@172.16.42.1 'sudo -n dmesg -wT' \
    > "$OUT/dmesg-live.txt" 2>&1 & )
sleep 3

# ---------------------------------------------------------------- 4. reboot
# Optional hands-free reset: qcom_wdt (/dev/watchdog0, 30 s, no MAGICCLOSE) resets the SoC
# if nobody pets it, so arming it just before the reboot means a frozen shutdown recovers
# by itself instead of needing a 10 s power-button hold.  Off by default: it cuts a
# legitimate shutdown short if the shutdown ever takes longer than 30 s.
if [ "${WATCHDOG:-0}" = 1 ]; then
	say "4a. arming /dev/watchdog0 (30 s, no pet)"
	$SSH 'sudo -n sh -c "setsid sh -c \"exec 9>/dev/watchdog0; sleep 600\" </dev/null >/dev/null 2>&1 &"; sleep 1; sudo -n wdctl /dev/watchdog0 | head -4'
fi

case "$HOW" in
  ssh)
	say "4. reboot from a detached shell (ssh)"
	$SSH 'sudo -n sh -c "sync; setsid reboot </dev/null >/dev/null 2>&1 &"' || true ;;
  rc-shutdown)
	say "4. reboot via openrc-shutdown if present"
	$SSH 'sudo -n sh -c "sync; setsid openrc-shutdown -r now </dev/null >/dev/null 2>&1 &"' || true ;;
  power-menu)
	say "4. NOT automated: use Restart in the Phosh power menu now"
	read -r -p "press enter after the phone restarted " _ ;;
  *) echo "unknown how: $HOW"; exit 2 ;;
esac
echo "   laptop time $(date +%T)"

# ---------------------------------------------------------------- 5. wait for it to come back
say "5. waiting up to 200 s for the phone (USB gadget + sshd)"
if "$ROOT/host/usb-shell.sh" 200 'echo BACK; cut -d. -f1 /proc/uptime' 150 | tee "$OUT/back.txt" | tail -3; then
	SAW_USB=yes
else
	SAW_USB=no
fi
grep -q BACK "$OUT/back.txt" && BACK=yes || BACK=no
echo "   back: usb=$SAW_USB ssh=$BACK" | tee -a "$OUT/back.txt"

# ---------------------------------------------------------------- 6. collect
if [ "$BACK" = yes ]; then
	say "6. collecting rc.log, harvester, pstore"
	$SSH "echo uptime=\$(cut -d. -f1 /proc/uptime)
	      echo '-- rc.log (full):'; sudo -n cat /var/log/rc.log
	      echo '-- harvester tail:'; sudo -n tail -80 $LOG
	      echo '-- pstore:'; sudo -n ls -l /sys/fs/pstore/ 2>/dev/null
	      echo '-- wifi:'; ip -br link show wlan0 2>/dev/null; ip -br addr show wlan0 2>/dev/null
	      echo '-- fatal:'; sudo -n dmesg | grep -c 'fatal error'" > "$OUT/after.txt" 2>&1
	say "   wrote $OUT/after.txt ($(wc -l < "$OUT/after.txt") lines)"
else
	say "6. phone did not come back on its own within 200 s - it froze; hold power 10 s and rerun collection"
fi

# ---------------------------------------------------------------- 7. verdict on the stream
if [ -s "$OUT/dmesg-live.txt" ]; then
	say "7. last kernel lines seen on the laptop:"
	grep -aE "rcu:|soft lockup|watchdog|SMP:|Stopping|remoteproc|ath10k" "$OUT/dmesg-live.txt" | tail -12
else
	say "7. no live stream captured (cable went down before any output)"
fi
say "done: $OUT"
