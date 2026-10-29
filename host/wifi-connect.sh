#!/usr/bin/env bash
# Connect the phone's mainline wlan0 to a WiFi network and prove traffic flows over it.
# You type the SSID and password here; they go to the phone over ssh stdin (never on a command line,
# never logged).  Usage: ./wifi-connect.sh [SSID]
cd "$(dirname "$0")"
S=${1:-}
[ -n "$S" ] || read -rp "SSID: " S
echo "SSID: $S"
read -rsp "Password (empty for an open network): " P; echo
{ printf '%s\n' "$S"; printf '%s\n' "$P"; } | ./rssh 'sudo -n sh -c "
read -r s; read -r p
ip link set wlan0 up
if [ -n \"\$p\" ]; then nmcli device wifi connect \"\$s\" password \"\$p\" ifname wlan0; else nmcli device wifi connect \"\$s\" ifname wlan0; fi
sleep 8
echo; echo == wlan0 ==; ip -br addr show wlan0
iw dev wlan0 link | head -6
GW=\$(ip route show dev wlan0 | awk \"/default/{print \\\$3; exit}\")
echo; echo gateway: \${GW:-none}
[ -n \"\$GW\" ] && ping -I wlan0 -c3 -W2 \$GW
echo; echo == internet via wlan0 ==
ping -I wlan0 -c3 -W3 1.1.1.1
ping -I wlan0 -c2 -W3 example.com
"' 2>&1 | grep -v Warning
