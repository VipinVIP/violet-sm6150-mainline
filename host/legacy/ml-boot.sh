#!/bin/bash
# r10 -> (load GPU zap via KGSL) -> kexec mainline with display+GPU on one DRM device and the big
# console font -> optionally start bare phoc through the greetd service.
# Usage: ml-boot.sh <tag> [phoc]        extra kernel args via EXTRA_CMDLINE
IF=$(ip -br link | awk '/^enp0s20f0u/{print $1; exit}'); TAG=${1:-ml}
O="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=6"
A=$(ip neigh show dev $IF | awk '/fe80/{print $1; exit}')
ssh $O user@$A%$IF 'uname -r' | grep -q '^4.14' || { echo "phone is not on r10"; exit 1; }
scp -q $O $HOME/violet-pmos/tools/kgsl_open.py "user@[$A%$IF]:/tmp/"
ssh $O user@$A%$IF 'echo 1024 | sudo -n tee /sys/class/backlight/backlight/brightness >/dev/null; sudo -n timeout 30 python3 /tmp/kgsl_open.py | tail -1'
EXTRA_CMDLINE="fbcon=font:TER16x32 ${EXTRA_CMDLINE:-}" timeout 300 $HOME/violet-mainline/kexec-test.sh $TAG 2>&1 | tail -1
A=$(ip neigh show dev $IF | awk '/fe80/{print $1; exit}')
ssh $O user@$A%$IF 'uname -r; echo 1024 | sudo -n tee /sys/class/backlight/backlight/brightness >/dev/null'
if [ "${2:-}" = phoc ]; then
	ssh $O user@$A%$IF 'sudo -n cp /etc/conf.d/greetd /etc/conf.d/greetd.orig
		sudo -n sed -i "s#^cfgfile=.*#cfgfile=\"/etc/phrog/greetd-phoconly.toml\"#" /etc/conf.d/greetd; sync
		sudo -n rc-service greetd restart >/dev/null 2>&1; sleep 6
		sudo -n cp /etc/conf.d/greetd.orig /etc/conf.d/greetd; sync
		sudo -n -u greetd env XDG_RUNTIME_DIR=/run/user/108 dbus-daemon --session --fork --print-address=1 > /tmp/bus.addr
		echo "phoc=$(pidof phoc)"'
fi
