#!/bin/sh
# usage: vs-sweep.sh <param> <values...>   sweeps ath10k_core.<param> and counts vdev-start rejections (dummy PSK, no real credentials)
P=$1; shift
nmcli device set wlan0 managed no 2>/dev/null
for p in $(pgrep -x wpa_supplicant); do kill $p; done
sleep 1
cat > /tmp/dummy.conf <<EOC
ctrl_interface=/tmp/wpa_dummy
p2p_disabled=1
network={
  ssid="<home-ap-ssid>"
  psk="dummy-not-the-real-password"
  scan_ssid=1
}
EOC
echo 0x12 > /sys/module/ath10k_core/parameters/debug_mask
for r in "$@"; do
	echo "$r" > /sys/module/ath10k_core/parameters/$P
	ip link set wlan0 down; ip link set wlan0 up; sleep 2
	dmesg -C
	wpa_supplicant -i wlan0 -D nl80211 -c /tmp/dummy.conf -dd > /tmp/w.log 2>&1 &
	w=0; while [ $w -lt 40 ]; do sleep 1; w=$((w+1)); grep -q 'SME: Trying to authenticate' /tmp/w.log && break; done
	sleep 3
	e=$(dmesg | grep -c 'vdev-start-response reports status error')
	f=$(grep -c 'MLME command failed (auth)' /tmp/w.log)
	a=$(grep -cE 'Authentication with .* timed out|RX auth|Authentication response|EVENT_AUTH|nl80211: Event message available' /tmp/w.log)
	echo "$P=$r  waited=${w}s tried_auth=$(grep -c "SME: Trying to authenticate" /tmp/w.log)  vdev_start_errors=$e  auth_cmd_failed=$f  other_auth_events=$a"
	for q in $(pgrep -x wpa_supplicant); do kill $q; done
	sleep 1
done
