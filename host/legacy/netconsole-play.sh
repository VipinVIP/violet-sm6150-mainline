#!/usr/bin/env bash
# Attach netconsole on the phone, then play a tone and capture whatever kills it.
#
# Listener must already be running on the host:
#   socat -u UDP4-RECV:6666,reuseaddr CREATE:~/violet-mainline/netconsole2.log
#
# Why: serial console goes to the phone UART and ramoops is not configured, so a
# crash during playback leaves no trace. netconsole over the USB gadget is the
# only way to see the fault.
#
# Pitfalls baked in (both cost a run):
#  * ssh wants user@fe80::x%iface with NO brackets; only scp needs [..].
#  * never mix '<<EOF' with '</dev/null' - the redirect wins and the remote
#    script body silently disappears, so the step "runs" doing nothing.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
LOG="$HERE/netconsole2.log"
O="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8"

set -- $(cat "$HERE/phone-addr")
A=$1; I=$2
H="user@$A%$I"

echo "== phone: $A%$I =="
K=$(timeout 10 ssh $O -n "$H" 'uname -r' 2>/dev/null)
case "$K" in
	7.*) echo "   mainline $K" ;;
	*)   echo "   NOT mainline (${K:-no answer}) - kexec first"; exit 1 ;;
esac

echo "== gadget addressing =="
ssh $O -T "$H" 'bash -s' <<'EOF'
IF=$(ip -br link | awk '/^usb|^eth|^enp/{print $1; exit}')
echo "   gadget iface: ${IF:-NONE}"
[ -z "$IF" ] && exit 1
sudo -n ip addr add 10.11.12.2/24 dev "$IF" 2>/dev/null
sudo -n ip link set "$IF" up 2>/dev/null
ip -br addr show "$IF" | sed 's/^/   /'
echo "$IF" | sudo -n tee /tmp/gadget_iface >/dev/null
EOF

echo "== netconsole =="
ssh $O -T "$H" 'bash -s' <<'EOF'
C=/sys/kernel/config/netconsole
IF=$(cat /tmp/gadget_iface 2>/dev/null)
[ -z "$IF" ] && { echo "   no iface"; exit 1; }
sudo -n mkdir -p $C/t1 2>/dev/null
cd $C/t1 2>/dev/null || { echo "   no netconsole configfs (CONFIG_NETCONSOLE_DYNAMIC?)"; exit 1; }
echo 10.11.12.1 | sudo -n tee remote_ip   >/dev/null
echo 6666      | sudo -n tee remote_port >/dev/null
echo 10.11.12.2 | sudo -n tee local_ip    >/dev/null 2>&1
echo "$IF"     | sudo -n tee dev_name    >/dev/null
echo 1         | sudo -n tee enabled     >/dev/null 2>&1
echo "   enabled=[$(cat enabled 2>/dev/null)] dev=[$(cat dev_name 2>/dev/null)] remote=[$(cat remote_ip 2>/dev/null):$(cat remote_port 2>/dev/null)]"
EOF

sleep 2
echo "== self-test: one line to /dev/kmsg should reach the host =="
ssh $O -n "$H" 'echo "netconsole-probe-$(date +%s)" | sudo -n tee /dev/kmsg >/dev/null' 2>/dev/null
sleep 3
if grep -qa "netconsole-probe" "$LOG" 2>/dev/null; then
	echo "   OK: capture path works, a crash will be recorded"
else
	echo "   WARNING: probe not in log - panic trace may still be lost"
fi

echo "== playing tone =="
ssh $O -T "$H" 'bash -s' <<'EOF'
N=$(amixer -c 0 controls 2>/dev/null | grep "PRI_MI2S_RX Audio Mixer MultiMedia3" | grep -oE "numid=[0-9]+" | cut -d= -f2 | head -1)
amixer -c 0 cset "numid=$N" 1 >/dev/null 2>&1
amixer -c 0 sset "Amp Gain" 24 >/dev/null 2>&1
echo "   route numid=$N"
echo "   uptime before: $(cut -d. -f1 /proc/uptime)s"
timeout 30 aplay -D hw:0,2 /tmp/tone-voice-band.wav 2>&1 | tail -2 | sed 's/^/   aplay: /'
echo "   aplay rc=$?"
echo "   uptime after: $(cut -d. -f1 /proc/uptime)s"
sudo -n dmesg | grep -iE "no line|fail to prepare|asoc error|q6afe" | tail -3 | cut -c1-120 | sed 's/^/   dmesg: /'
EOF

sleep 3
echo "== captured netconsole =="
if [ -s "$LOG" ]; then
	grep -aiE "panic|Oops|BUG:|Unable to handle|Call trace|q6afe|prepare|WARNING" "$LOG" | tail -25
else
	echo "   (empty)"
fi
