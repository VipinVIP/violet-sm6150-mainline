#!/bin/sh
# Enable the WLAN firmware's debug log and trigger a failing station vdev start (dummy PSK), then show the dbglog records.
nmcli device set wlan0 managed no 2>/dev/null
for p in $(pgrep -x wpa_supplicant); do kill $p; done; sleep 1
mount -t debugfs none /sys/kernel/debug 2>/dev/null
D=/sys/kernel/debug/ieee80211/phy0/ath10k
cat > /tmp/dummy.conf <<EOC
ctrl_interface=/tmp/wpa_dummy
p2p_disabled=1
network={
  ssid="<home-ap-ssid>"
  psk="dummy-not-the-real-password"
  scan_ssid=1
}
EOC
ip link set wlan0 down; ip link set wlan0 up; sleep 2
echo "ffffffffffffffff 0" > $D/fw_dbglog; cat $D/fw_dbglog
dmesg -C
wpa_supplicant -i wlan0 -D nl80211 -c /tmp/dummy.conf -dd > /tmp/w.log 2>&1 &
sleep 14
for q in $(pgrep -x wpa_supplicant); do kill $q; done
dmesg | grep -E "violet dbglog|vdev-start" | cut -c14-200 > /tmp/dbglog.txt
wc -l /tmp/dbglog.txt
grep -n -E "11ba18be|11ba0afe|vdev-start" /tmp/dbglog.txt | head -20
