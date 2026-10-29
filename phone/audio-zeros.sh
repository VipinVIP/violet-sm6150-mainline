#!/bin/sh
P=/sys/module/snd_soc_sm8250/parameters
echo 0 > $P/clk_mode; echo 0 > $P/violet_slave
A=$(amixer -c 0 controls | grep "QUAT_MI2S_RX Audio Mixer MultiMedia3" | sed "s/numid=\([0-9]*\).*/\1/")
amixer -c 0 cset numid=$A on >/dev/null
dmesg -C
echo "== zeros ${1:-20000} bytes"
head -c ${1:-20000} /dev/zero | timeout 10 aplay -t raw -f S16_LE -r 48000 -c 2 -D hw:0,2 2>&1 | tail -1
sleep 1; echo "zeros done; writes: $(dmesg | grep -a -c 'asm write')"
echo "== tone"
timeout 10 aplay -D hw:0,2 /var/tmp/tone440.wav 2>&1 | tail -1
sleep 1
dmesg | grep -a -E "PDM|DSP returned|timeout" | tail -5
echo "writes done events: $(dmesg | grep -a -c 'opcode 0x10d99')"
