#!/bin/sh
# Record from the WCD937x analog mic through TX macro -> TX_CODEC_DMA_TX_3 ->
# MultiMedia2 (hw:0,1) and print the signal level, so the mic path can be
# verified without anyone listening.
#
# Usage (root): mic-test.sh [adc] [seconds]
#   adc: 1 = AMIC1 -> ADC1 (default), 2 = ADC2 (ADC2 MUX picks AMIC2/AMIC3)
set -u
ADC=${1:-1}
SECS=${2:-3}
OUT=/var/tmp/mic-adc$ADC.wav

amixer -c0 -q cset name='MultiMedia2 Mixer TX_CODEC_DMA_TX_3' 1
amixer -c0 -q cset name='TX_AIF1_CAP Mixer DEC0' 1
amixer -c0 -q cset name='TX DEC0 MUX' SWR_MIC
if [ "$ADC" = 1 ]; then
	amixer -c0 -q cset name='TX SMIC MUX0' ADC0
	amixer -c0 -q cset name='ADC1_MIXER Switch' 1
	amixer -c0 -q cset name='ADC1 Switch' 1
	amixer -c0 -q cset name='ADC1 Volume' 12
else
	amixer -c0 -q cset name='TX SMIC MUX0' ADC1
	amixer -c0 -q cset name='ADC2_MIXER Switch' 1
	amixer -c0 -q cset name='ADC2 Switch' 1
	amixer -c0 -q cset name='ADC2 Volume' 12
fi

arecord -D hw:0,1 -f S16_LE -r 48000 -c 1 -d "$SECS" "$OUT" || exit 1

python3 - "$OUT" <<'EOF'
import sys, wave, struct, math
w = wave.open(sys.argv[1])
n = w.getnframes()
d = struct.unpack('<%dh' % n, w.readframes(n))
skip = d[4800:] or d          # drop the first 100 ms (pop/settling)
rms = math.sqrt(sum(x * x for x in skip) / len(skip))
peak = max(abs(x) for x in skip)
nz = sum(1 for x in skip if x)
print("frames=%d rms=%.1f peak=%d nonzero=%d%%" % (n, rms, peak, 100 * nz // len(skip)))
EOF
