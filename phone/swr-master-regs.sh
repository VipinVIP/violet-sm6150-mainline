#!/bin/sh
# Differential dump of the SoundWire MASTER register files:
#   RX master (62ef0000 = master-2-0) during headphone playback   <- suspect
#   TX master (62ed0000 = master-3-0) during mic capture          <- known working control
set -u
RXM=/sys/kernel/debug/soundwire/master-2-0/qualcomm-sdw/qualcomm-registers
TXM=/sys/kernel/debug/soundwire/master-3-0/qualcomm-sdw/qualcomm-registers
c() { amixer -c 0 -q cset name="$1" "$2" >/dev/null 2>&1 || echo "FAILED cset: $1"; }

for f in "$RXM" "$TXM"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done

echo "== idle snapshots"
cat "$RXM" > /tmp/m-rx-idle.txt 2>&1
cat "$TXM" > /tmp/m-tx-idle.txt 2>&1
wc -l /tmp/m-rx-idle.txt /tmp/m-tx-idle.txt | head -2

echo "== TX master during capture (control)"
timeout 6 arecord -D hw:0,0 -f S16_LE -r 48000 -c 1 /var/tmp/ref.wav >/tmp/arec.log 2>&1 &
sleep 2
cat "$TXM" > /tmp/m-tx-play.txt 2>&1
wait

echo "== headphone route + playback"
c 'PRI_MI2S_RX Audio Mixer MultiMedia3' 0
c 'RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia3' 1
c 'RX_MACRO RX0 MUX' AIF1_PB
c 'RX_MACRO RX1 MUX' AIF1_PB
c 'RX INT0_1 MIX1 INP0' RX0
c 'RX INT1_1 MIX1 INP0' RX1
c 'RX INT0 DEM MUX' CLSH_DSM_OUT
c 'RX INT1 DEM MUX' CLSH_DSM_OUT
c 'HPHL_RDAC Switch' 1
c 'HPHR_RDAC Switch' 1
c 'HPHL Switch' 1
c 'HPHR Switch' 1
c 'HPHL_COMP Switch' 1
c 'HPHR_COMP Switch' 1
c 'HPHL Volume' 12
c 'HPHR Volume' 12
c 'RX_RX0 Digital Volume' 64
c 'RX_RX1 Digital Volume' 64
timeout 20 aplay -D hw:0,2 /var/tmp/hph-tone48.wav >/tmp/aplay.log 2>&1 &
sleep 4
echo "slave: $(cat /sys/bus/soundwire/devices/sdw:2:0:0217:010a:00:4/status)"
cat "$RXM" > /tmp/m-rx-play.txt 2>&1
echo "aplay: $(tail -2 /tmp/aplay.log | tr '\n' ' ')"
wait

echo "== dmesg tail"
dmesg | grep -a -iE "swr|soundwire|wcd937x|q6afe|q6routing|xport" | tail -8 | cut -c1-170
echo done
