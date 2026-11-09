#!/bin/sh
# Objective headphone test: play a tone into the 3.5 mm route while recording the phone's
# own mic, and report the recorded RMS per configuration.  Put the earbuds next to the
# phone (mic at the bottom edge), volume up on the earbuds' inline control if any.
# Also dumps the key analog codec registers for each config.
set -u
R="/sys/kernel/debug/regmap/sdw:3:0:0217:010a:00:3-wcd937x_csr/registers"
TONE=/var/tmp/hph-tone48.wav

c() { amixer -c 0 -q cset name="$1" "$2" >/dev/null 2>&1 || echo "  FAIL cset: $1"; }
rms() { python3 -c 'import sys,wave,audioop;w=wave.open(sys.argv[1]);d=w.readframes(w.getnframes());print("%.1f"%audioop.rms(d,2) if d else "0.0")' "$1" 2>/dev/null || echo err; }
rec() { timeout 4 arecord -q -D hw:0,1 -f S16_LE -r 48000 -c 1 "$1" >/dev/null 2>&1; }
regs() { sudo cat "$R" | grep -E "^(3008|3009|30d3|30d6|3414):" | tr '\n' ' '; }

base() {
	c 'PRI_MI2S_RX Audio Mixer MultiMedia3' 0
	c 'RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia3' 1
	c 'RX_MACRO RX0 MUX' AIF1_PB
	c 'RX_MACRO RX1 MUX' AIF1_PB
	c 'RX INT0_1 MIX1 INP0' RX0
	c 'RX INT1_1 MIX1 INP0' RX1
	c 'RX INT0 DEM MUX' CLSH_DSM_OUT
	c 'RX INT1 DEM MUX' CLSH_DSM_OUT
	c 'RX_RX0 Digital Volume' 110
	c 'RX_RX1 Digital Volume' 110
	c 'RX_HPH HD2 Mode Switch' 1
	c 'HPHL_RDAC Switch' 1
	c 'HPHR_RDAC Switch' 1
	c 'HPHL Switch' 1
	c 'HPHR Switch' 1
	c 'HPHL Volume' 18
	c 'HPHR Volume' 18
}

run() { # $1 = label, uses $TONE
	printf '%-14s ' "$1"
	rec /var/tmp/bg.wav
	timeout 5 aplay -D hw:0,2 "$TONE" >/dev/null 2>&1 &
	AP=$!
	sleep 1
	rec /var/tmp/sig.wav
	wait $AP 2>/dev/null
	printf 'bg_rms=%-6s sig_rms=%-6s %s\n' "$(rms /var/tmp/bg.wav)" "$(rms /var/tmp/sig.wav)" "$(regs)"
}

base
echo "start: jack=$(amixer -c0 cget numid=89 2>/dev/null | tail -1 | tr -d ' ') mbhc=$(amixer -c0 cget numid=24 | tail -1 | tr -d ' ')"

echo "--- A: vendor class-H, companders ON"
c 'HPHL_COMP Switch' 1; c 'HPHR_COMP Switch' 1; c 'RX_COMP1 Switch' 1; c 'RX_COMP2 Switch' 1
c 'RX HPH Mode' CLS_H_HIFI
run A_compH

echo "--- B: companders OFF"
c 'HPHL_COMP Switch' 0; c 'HPHR_COMP Switch' 0; c 'RX_COMP1 Switch' 0; c 'RX_COMP2 Switch' 0
run B_comp_off

echo "--- C: class-AB, companders OFF"
c 'RX HPH Mode' CLS_AB_HIFI
c 'RX INT0 DEM MUX' NORMAL; c 'RX INT1 DEM MUX' NORMAL
run C_classab

echo "--- D: class-H, 4-channel stream (enables DP2 CLSH + DP3 comp)"
c 'RX HPH Mode' CLS_H_HIFI
c 'RX INT0 DEM MUX' CLSH_DSM_OUT; c 'RX INT1 DEM MUX' CLSH_DSM_OUT
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=440:duration=20" -ar 48000 -ac 4 -af "volume=0.5" /var/tmp/hph-tone4.wav 2>/dev/null
TONE=/var/tmp/hph-tone4.wav
run D_4ch

echo "--- E: speaker control (proves the mic picks up audio at this distance)"
c 'RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia3' 0
c 'PRI_MI2S_RX Audio Mixer MultiMedia3' 1
TONE=/var/tmp/hph-tone48.wav
run E_speaker
echo done
