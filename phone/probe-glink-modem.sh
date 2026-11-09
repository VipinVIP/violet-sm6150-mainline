echo "-- glink events mentioning the modem edge:"
sudo -n grep -aE "remote: (mpss|modem)" /sys/kernel/debug/tracing/trace | head -20
echo "-- count: $(sudo -n grep -acE "remote: (mpss|modem)" /sys/kernel/debug/tracing/trace)"
echo "-- glink errors in dmesg:"
sudo -n dmesg | grep -aiE "glink|ch open|ack timeout|intent" | grep -av "Kernel command line" | tail -20
echo "-- rpmsg devices on the modem edge and their drivers:"
for d in /sys/bus/rpmsg/devices/4080000*; do
	printf "   %s -> %s\n" "$(basename "$d")" "$(readlink -f "$d/driver" 2>/dev/null | sed "s|.*/||")"
done
echo "-- qrtr node table (from kernel):"
sudo -n cat /sys/kernel/debug/qrtr/ns/ 2>/dev/null | head
