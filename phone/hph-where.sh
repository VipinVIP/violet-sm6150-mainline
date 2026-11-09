#!/bin/sh
# Measured A/B: where does the tone actually come out?
#  1) silence baseline
#  2) 3.5 mm jack only (speaker route OFF)
#  3) speaker only (jack route OFF)
# The phone records itself with its own mic, so the earbud (lying on the phone) is heard
# through the mic.  Codec registers are sampled DURING playback.
set -u
R="/sys/kernel/debug/regmap/sdw:3:0:0217:010a:00:3-wcd937x_csr/registers"
TONE=/var/tmp/hph-tone48.wav
c() { amixer -c 0 -q cset name="$1" "$2" >/dev/null 2>&1 || echo "  FAIL cset: $1"; }
rms() { python3 -c '
import sys, wave, math, struct
w = wave.open(sys.argv[1]); d = w.readframes(w.getnframes())
n = len(d) // 2
if n == 0: print("0"); raise SystemExit
s = struct.unpack("<%dh" % n, d[:n*2])
print("%.0f" % math.sqrt(sum(x*x for x in s) / n))' "$1" 2>/dev/null || echo err; }
regs() { sudo cat "$R" | grep -E "^(3008|3009|30d3|30d6):" | tr '\n' ' '; }

route_jack() {
	c 'PRI_MI2S_RX Audio Mixer MultiMedia3' 0
	c 'RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia3' 1
	c 'RX_MACRO RX0 MUX' AIF1_PB ; c 'RX_MACRO RX1 MUX' AIF1_PB
	c 'RX INT0_1 MIX1 INP0' RX0 ; c 'RX INT1_1 MIX1 INP0' RX1
	c 'RX INT0 DEM MUX' CLSH_DSM_OUT ; c 'RX INT1 DEM MUX' CLSH_DSM_OUT
	c 'RX_COMP1 Switch' 0 ; c 'RX_COMP2 Switch' 0
	c 'HPHL_COMP Switch' 0 ; c 'HPHR_COMP Switch' 0
	c 'RX_RX0 Digital Volume' 110 ; c 'RX_RX1 Digital Volume' 110
	c 'HPHL_RDAC Switch' 1 ; c 'HPHR_RDAC Switch' 1
	c 'HPHL Switch' 1 ; c 'HPHR Switch' 1
	c 'HPHL Volume' 18 ; c 'HPHR Volume' 18
}
route_speaker() {
	c 'RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia3' 0
	c 'PRI_MI2S_RX Audio Mixer MultiMedia3' 1
}

measure() { # $1 label
	rec=/var/tmp/m-$1.wav
	timeout 4 arecord -q -D hw:0,1 -f S16_LE -r 48000 -c 1 "$rec" >/dev/null 2>&1 &
	RP=$!
	sleep 0.4
	timeout 3 aplay -D hw:0,2 "$TONE" >/tmp/ap-$1.log 2>&1 &
	AP=$!
	sleep 1.4
	R2="$(regs)"
	wait $AP 2>/dev/null; wait $RP 2>/dev/null
	printf '%-12s rms=%-6s regs[%s] aplay_err=%s\n' "$1" "$(rms "$rec")" "$R2" "$(grep -ci error /tmp/ap-$1.log)"
}

echo "jack state: jack=$(amixer -c0 cget numid=89 2>/dev/null | tail -1 | tr -d ' ') mbhc=$(amixer -c0 cget numid=24 | tail -1 | tr -d ' ')"
route_jack;    sleep 1; measure jack_only
route_speaker; sleep 1; measure speaker_only
route_jack;    sleep 1; measure jack_again
echo done
