#!/bin/sh
# usage: audio-matrix.sh <clk_mode> <slave>   restart ADSP, then one QUAT dummy-link playback attempt
P=/sys/module/snd_soc_sm8250/parameters
echo stop > /sys/class/remoteproc/remoteproc0/state; sleep 3
echo start > /sys/class/remoteproc/remoteproc0/state; sleep 25
echo $1 > $P/clk_mode; echo $2 > $P/violet_slave
dmesg -C
N=$(amixer -c 0 controls | grep "QUAT_MI2S_RX Audio Mixer MultiMedia3" | sed "s/numid=\([0-9]*\).*/\1/")
amixer -c 0 cset numid=$N on >/dev/null
echo "== clk_mode=$1 slave=$2"
timeout 8 aplay -D hw:0,2 /var/tmp/tone440.wav 2>&1 | tail -1
sleep 3
dmesg | grep -v -E "Handover|arm-smmu|callbacks|chan info" | tail -15
