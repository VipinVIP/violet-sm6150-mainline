#!/bin/sh
# Verify a headphone playback stream is really RUNNING, then dump codec registers + DAPM.
set -u
R="/sys/kernel/debug/regmap/sdw:3:0:0217:010a:00:3-wcd937x_csr/registers"
c() { amixer -c 0 -q cset name="$1" "$2" >/dev/null 2>&1 || echo "FAILED cset: $1"; }

c 'PRI_MI2S_RX Audio Mixer MultiMedia3' 0
c 'RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia3' 1
c 'RX_MACRO RX0 MUX' AIF1_PB
c 'RX_MACRO RX1 MUX' AIF1_PB
c 'RX INT0_1 MIX1 INP0' RX0
c 'RX INT1_1 MIX1 INP0' RX1
c 'HPHL_RDAC Switch' 1
c 'HPHR_RDAC Switch' 1
c 'HPHL Switch' 1
c 'HPHR Switch' 1
c 'HPHL Volume' 14
c 'HPHR Volume' 14
c 'RX_RX0 Digital Volume' 84
c 'RX_RX1 Digital Volume' 84

cat "$R" > /tmp/c-idle2.txt
echo "idle regs: $(grep -v ': 00$' /tmp/c-idle2.txt | wc -l) nonzero"

setsid timeout 25 aplay -D hw:0,2 /var/tmp/hph-tone48.wav >/tmp/aplay2.log 2>&1 &
AP=$!
i=0
while [ $i -lt 20 ]; do
	st=$(sed -n 's/^state: *//p' /proc/asound/card0/pcm2p/sub0/status 2>/dev/null)
	[ "$st" = "RUNNING" ] && break
	i=$((i+1)); sleep 0.25
done
echo "pcm state: ${st:-unknown} after ${i} polls"
echo "slave: $(cat /sys/bus/soundwire/devices/sdw:2:0:0217:010a:00:4/status 2>/dev/null)"
cat "$R" > /tmp/c-play2.txt
echo "play regs: $(grep -v ': 00$' /tmp/c-play2.txt | wc -l) nonzero"
echo "== registers that changed during playback"
diff /tmp/c-idle2.txt /tmp/c-play2.txt | grep '^[<>]' | head -70
echo "== DAPM"
D=$(dirname "$(dirname "$(ls -d /sys/kernel/debug/asoc/*/dapm 2>/dev/null | head -1)")")
for w in HPHL HPHR HPHL PGA HPHR PGA "WCD AIF Playback" "RX_CODEC_DMA_RX_0 Playback" "RX AIF1 PB"; do
	p=$(ls -d /sys/kernel/debug/asoc/*/dapm/"$w" 2>/dev/null | head -1)
	[ -n "$p" ] && printf '%s: %s\n' "$w" "$(cat "$p" | tr '\n' ' ')"
done
echo "== dmesg"
dmesg | grep -a -iE "swr|soundwire|wcd937x|q6afe|q6asm|xport|ASoC" | tail -8 | cut -c1-180
kill $AP 2>/dev/null
wait 2>/dev/null
echo done
