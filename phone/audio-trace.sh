#!/bin/sh
# one traced QUAT dummy-link playback attempt (diagnostic)
mount -t debugfs none /sys/kernel/debug 2>/dev/null
echo "q6asm lines in dyndbg: $(grep -c q6asm /sys/kernel/debug/dynamic_debug/control)"
for f in q6asm.c q6asm-dai.c q6adm.c q6routing.c q6afe.c q6afe-dai.c apr.c q6core.c; do
	echo "file $f +p" > /sys/kernel/debug/dynamic_debug/control
done
dmesg -C
N=$(amixer -c 0 controls | grep "QUAT_MI2S_RX Audio Mixer MultiMedia3" | sed "s/numid=\([0-9]*\).*/\1/")
amixer -c 0 cset numid=$N on | tail -1
timeout 8 aplay -D hw:0,2 /var/tmp/tone440.wav 2>&1 | tail -2
sleep 2
dmesg | grep -v -E "Handover|arm-smmu|callbacks|chan info" | tail -50
