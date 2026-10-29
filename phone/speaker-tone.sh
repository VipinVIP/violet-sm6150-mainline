#!/bin/sh
# speaker path: MultiMedia3 -> PRI_MI2S_RX -> TAS2563; prints amp state while playing
P=/sys/module/snd_soc_sm8250/parameters
echo 0 > $P/clk_mode 2>/dev/null; echo 0 > $P/violet_slave 2>/dev/null
for n in $(amixer -c 0 controls | grep "Audio Mixer MultiMedia3'" | grep -v PRI_MI2S_RX | sed 's/numid=\([0-9]*\).*/\1/'); do amixer -c 0 cset numid=$n off >/dev/null 2>&1; done
A=$(amixer -c 0 controls | grep "PRI_MI2S_RX Audio Mixer MultiMedia3'" | sed "s/numid=\([0-9]*\).*/\1/")
amixer -c 0 cset numid=$A on
dmesg -C
(timeout 14 aplay -D hw:0,2 ${1:-/var/tmp/tone440.wav} 2>&1 &)
sleep 2; python3 /tmp/amp-dump.py 2>&1 | tail -3
sleep 6; dmesg | grep -a -E "tas|DSP returned|crash" | tail -5
