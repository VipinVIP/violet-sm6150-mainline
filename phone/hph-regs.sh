#!/bin/sh
# Dump codec + SoundWire data-port registers DURING playback (and during capture as a
# known-good reference).  Read-only: no mixer change beyond the headphone route.
set -u
CARD=0
RDIR=/sys/kernel/debug/regmap/0-04/registers
RXD=/sys/kernel/debug/soundwire/master-2-0/sdw:2:0:0217:010a:00:4/registers
TXD=/sys/kernel/debug/soundwire/master-3-0/sdw:3:0:0217:010a:00:3/registers

c() { amixer -c $CARD -q cset name="$1" "$2" >/dev/null 2>&1 || echo "FAILED cset: $1"; }

route_hph() {
	c 'PRI_MI2S_RX Audio Mixer MultiMedia3' 0
	c 'RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia3' 1
	c 'RX_MACRO RX0 MUX' AIF1_PB
	c 'RX_MACRO RX1 MUX' AIF1_PB
	c 'RX INT0_1 MIX1 INP0' RX0
	c 'RX INT1_1 MIX1 INP0' RX1
	c 'RX INT0 DEM MUX' CLSH_DSM_OUT
	c 'RX INT1 DEM MUX' CLSH_DSM_OUT
	c 'RX_COMP1 Switch' 0
	c 'RX_COMP2 Switch' 0
	c 'HPHL_COMP Switch' 1
	c 'HPHR_COMP Switch' 1
	c 'HPHL_RDAC Switch' 1
	c 'HPHR_RDAC Switch' 1
	c 'HPHL Switch' 1
	c 'HPHR Switch' 1
	c 'HPHL Volume' 8
	c 'HPHR Volume' 8
	c 'RX_RX0 Digital Volume' 64
	c 'RX_RX1 Digital Volume' 64
}

dp_dump() {
	sed -n '/^DP0$/,/^DP3$/p' "$1" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g'
	echo
}

codec_dump() {
	echo "-- codec analog/digital (ANA_RX_SUPPLIES 3008, ANA_HPH 3009, HPH_CNP_EN 30cb,"
	echo "   HPH_L_EN 30d3, HPH_R_EN 30d6, COMP_CTL_0 3414, CDC_HPH_GAIN 3418?)"
	sudo cat "$RDIR" | grep -E "^(3008|3009|30c8|30cb|30d3|30d6|3414|3423|3426|3443|3446|3456):"
}

echo "=== jack / slave state before"
for d in /sys/bus/soundwire/devices/sdw:*; do echo "  $(basename "$d"): $(cat "$d/status") pm=$(cat "$d/power/runtime_status" 2>/dev/null)"; done
amixer -c $CARD cget name='Headphone Jack' 2>/dev/null | tail -1

echo "=== routing to headphones"
route_hph

echo "=== playing 20 s tone on hw:0,2 in background"
timeout 20 aplay -D hw:$CARD,2 /var/tmp/hph-tone48.wav >/tmp/aplay.log 2>&1 &
sleep 3
echo "=== playback active; slave status"
for d in /sys/bus/soundwire/devices/sdw:*; do echo "  $(basename "$d"): $(cat "$d/status")"; done
echo "=== RX slave DP registers during playback"
dp_dump "$RXD"
echo "=== codec registers during playback"
codec_dump
echo "=== aplay log"; tail -3 /tmp/aplay.log
wait

echo
echo "=== capture reference: 4 s recording from AMIC1"
timeout 4 arecord -D hw:$CARD,0 -f S16_LE -r 48000 -c 1 /var/tmp/ref.wav >/tmp/arec.log 2>&1 &
sleep 2
echo "=== TX slave DP registers during capture"
dp_dump "$TXD"
echo "=== TX slave DP0 (full dump, head)"
head -20 "$TXD" 2>/dev/null | tr '\n' ' '; echo
wait
echo done
