#!/bin/sh
# Restart the modem (fresh WLAN firmware boot) and attempt a station vdev start (dummy PSK) as soon as wlan0 exists.
RP=/sys/class/remoteproc/remoteproc1
nmcli device set wlan0 managed no 2>/dev/null
for p in $(pgrep -x wpa_supplicant); do kill $p; done
echo 0x12 > /sys/module/ath10k_core/parameters/debug_mask
cat > /tmp/dummy.conf <<EOC
ctrl_interface=/tmp/wpa_dummy
p2p_disabled=1
network={
  ssid="<home-ap-ssid>"
  psk="dummy-not-the-real-password"
  scan_ssid=1
}
EOC
echo stop > $RP/state; sleep 5
dmesg -C
echo start > $RP/state
w=0; while [ $w -lt 150 ]; do sleep 1; w=$((w+1)); dmesg | grep -q 'qmi fw_version' && break; done
echo "fw ready after ${w}s"
sleep 2
# wait until ath10k has the firmware ready (interface can be brought up)
n=0; while [ $n -lt 30 ]; do sleep 1; n=$((n+1)); ip link set wlan0 up 2>/dev/null && break; done
echo "link up after ${n}s more"
dmesg -C
wpa_supplicant -i wlan0 -D nl80211 -c /tmp/dummy.conf -dd > /tmp/w.log 2>&1 &
sleep 20
for q in $(pgrep -x wpa_supplicant); do kill $q; done
echo "tried_auth=$(grep -c 'SME: Trying to authenticate' /tmp/w.log) vdev_errors=$(dmesg | grep -c 'vdev-start-response reports status error') start_attempts=$(dmesg | grep -c 'mac vdev . start')"
dmesg | grep -E 'mac vdev . start|vdev-start' | head -4 | cut -c14-150
