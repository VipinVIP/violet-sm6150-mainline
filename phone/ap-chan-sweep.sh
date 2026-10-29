#!/bin/sh
# Start an AP vdev on several 2.4 GHz channels and report whether the firmware accepts each (throwaway SSID/passphrase).
nmcli device set wlan0 managed no 2>/dev/null
for p in $(pgrep -x wpa_supplicant) $(pgrep -x hostapd); do kill $p; done; sleep 2
cat > /tmp/ap.conf <<EOC
interface=wlan0
driver=nl80211
ssid=violet-ap-test
hw_mode=g
channel=6
country_code=IN
ieee80211n=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=violet-throwaway-1234
EOC
echo 0x12 > /sys/module/ath10k_core/parameters/debug_mask
for ch in "$@"; do
	freq=$((2407+5*ch))
	ip link set wlan0 down; iw dev wlan0 set type managed 2>/dev/null; ip link set wlan0 up; sleep 2
	sed "s/^channel=.*/channel=$ch/" /tmp/ap.conf > /tmp/ap_$ch.conf
	dmesg -C
	hostapd /tmp/ap_$ch.conf > /tmp/ap_$ch.log 2>&1 &
	sleep 7
	echo "ch $ch ($freq): AP-ENABLED=$(grep -c AP-ENABLED /tmp/ap_$ch.log) vdev_start_errors=$(dmesg | grep -c vdev-start-response) starts=$(dmesg | grep -c 'mac vdev . start')"
	for p in $(pgrep -x hostapd); do kill $p; done; sleep 2
done
