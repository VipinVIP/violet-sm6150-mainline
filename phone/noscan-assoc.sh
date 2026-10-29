#!/bin/sh
# Associate without any scan beforehand: ap_scan=2 + fixed BSSID/frequency, dummy PSK (no real credentials).
nmcli device set wlan0 managed no 2>/dev/null
for p in $(pgrep -x wpa_supplicant); do kill $p; done; sleep 1
cat > /tmp/ns.conf <<EOC
ctrl_interface=/tmp/wpa_ns
ap_scan=2
p2p_disabled=1
network={
  ssid="<home-ap-ssid>"
  bssid=<ap-bssid>
  frequency=2417
  psk="dummy-not-the-real-password"
  disabled=1
}
EOC
echo 0x12 > /sys/module/ath10k_core/parameters/debug_mask
ip link set wlan0 down; ip link set wlan0 up; sleep 2
dmesg -C
wpa_supplicant -i wlan0 -D nl80211 -c /tmp/ns.conf -dd > /tmp/ns.log 2>&1 &
sleep 3
wpa_cli -p /tmp/wpa_ns -i wlan0 select_network 0
sleep 8
grep -E "SME:|Authenticat|MLME command|CTRL-EVENT" /tmp/ns.log | tail -6 | cut -c1-160
echo "--- driver"
dmesg | grep -E "scan event|start scan|mac vdev . start|vdev-start|failed to start" | head -8 | cut -c14-170
for q in $(pgrep -x wpa_supplicant); do kill $q; done
