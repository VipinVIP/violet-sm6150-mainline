#!/bin/sh
# usage: audio-warm2.sh <warm_seconds>: hold the QUAT dummy stream prepared (no data) for N s, then play the tone
N=${1:-20}
P=/sys/module/snd_soc_sm8250/parameters
echo 0 > $P/clk_mode; echo 0 > $P/violet_slave
A=$(amixer -c 0 controls | grep "QUAT_MI2S_RX Audio Mixer MultiMedia3" | sed "s/numid=\([0-9]*\).*/\1/")
amixer -c 0 cset numid=$A on >/dev/null
dmesg -C
echo "== warm-up ${N}s (no data)"
sleep $((N+30)) | aplay -t raw -f S16_LE -r 48000 -c 2 -D hw:0,2 >/dev/null 2>&1 &
sleep $N
for p in $(pgrep -x aplay); do kill $p; done; sleep 2
echo "== play"
timeout 10 aplay -D hw:0,2 /var/tmp/tone440.wav 2>&1 | tail -1
sleep 1
dmesg | grep -a -E "PDM|DSP returned|timeout" | tail -8
echo "writes done: $(dmesg | grep -a -c 'opcode 0x10d99')"
