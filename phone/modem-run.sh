#!/bin/sh
# runs ON the phone (mainline): quiet display, rmtfs, start modem, sample QRTR every 3 s. Output streams to the laptop.
[ -z "$NOBLANK" ] && rc-service greetd stop >/dev/null 2>&1
[ -n "$STOPMM" ] && rc-service modemmanager stop >/dev/null 2>&1
logread -f 2>/dev/null | grep -vE 'Handover|pulseaudio|pam_unix|sshd' | sed 's/^/LOG: /' &
mount -t tracefs none /sys/kernel/tracing 2>/dev/null
T=/sys/kernel/tracing
echo 0 > $T/tracing_on; echo > $T/trace; echo 32768 > $T/buffer_size_kb
for e in qrtr/qrtr_ns_message qrtr/qrtr_ns_service_announce_new qcom_glink/qcom_glink_cmd_open; do echo 1 > $T/events/$e/enable 2>/dev/null; done
echo 1 > $T/tracing_on
[ -z "$NOBLANK" ] && for k in 1 2 3; do echo 4 > /sys/class/graphics/fb0/blank; sleep 1; done
rc-service rmtfs stop >/dev/null 2>&1
pkill rmtfs 2>/dev/null; sleep 1
/usr/bin/rmtfs -v -o /var/lib/rmtfs > /var/log/rmtfs-v.log 2>&1 &
sleep 2
echo "=== MODEM START ===" > /dev/kmsg
echo start > /sys/class/remoteproc/remoteproc1/state
if [ -n "$SMART" ]; then
	n=0
	while [ $n -lt ${SMART} ]; do
		w=0; got=0
		while [ $w -lt 12 ]; do sleep 1; w=$((w+1)); [ "$(qrtr-lookup 2>/dev/null | awk '$4==0' | wc -l)" -gt 10 ] && { got=1; break; }; done
		echo "SMART attempt $n: services after ${w}s -> $got"
		[ $got = 1 ] && break
		echo stop > /sys/class/remoteproc/remoteproc1/state; sleep 2
		echo start > /sys/class/remoteproc/remoteproc1/state
		n=$((n+1))
	done
fi
i=0
while [ $i -lt ${SAMPLES:-16} ]; do
	sleep 3; i=$((i+1))
	echo "t=$((i*3)) $(cat /sys/class/remoteproc/remoteproc1/state) node0=$(qrtr-lookup 2>/dev/null | awk '$4==0' | wc -l) pdmap=$(qrtr-lookup 2>/dev/null | awk '$1==64' | wc -l) wlfw=$(qrtr-lookup 2>/dev/null | awk '$1==69' | wc -l) wlan=$(ip -br link | grep -c wlan)"
done
echo "=== qrtr_ns trace, non-AP senders ==="
grep -E 'qrtr_ns_message' $T/trace | grep -vE ' from 1:' | head -60
echo "=== lookups by (service) ==="
grep 'new-lookup' $T/trace | awk '{print $NF}' | sort | uniq -c | sort -rn | head
echo '=== rmtfs -v log ==='; tail -40 /var/log/rmtfs-v.log
echo "=== ath10k / wlan dmesg ==="
dmesg | grep -iE 'ath10k|wlan|cfg80211' | grep -v 'Direct firmware load for regulatory' | tail -40
ip -br link
echo "=== wlan0 up + scan ==="
ip link set wlan0 up 2>&1; sleep 3
ip -br link show wlan0
dmesg | tail -15 | grep -iE 'ath10k|wlan|crash' 
iw dev wlan0 scan 2>&1 | grep -E '^BSS|SSID|signal' | head -60
ip -br link show wlan0
