#!/bin/sh
# Read LPI gpio24 regs while an AFE stream is running (core clock held up by the active port).
PEEK=${PEEK:-62b58000}
P=/sys/module/snd_soc_sm8250/parameters
echo 0 > $P/clk_mode; echo 0 > $P/violet_slave; echo 3 > /sys/module/q6afe_dai/parameters/violet_hw_vote
A=$(amixer -c 0 controls | grep "QUAT_MI2S_RX Audio Mixer MultiMedia3" | sed "s/numid=\([0-9]*\).*/\1/")
amixer -c 0 cset numid=$A on >/dev/null
(timeout 12 aplay -D hw:0,2 /var/tmp/tone440.wav >/dev/null 2>&1 &)
sleep 3
sync
python3 - $PEEK <<'PY'
import mmap,os,struct
fd=os.open('/dev/mem',os.O_RDONLY|os.O_SYNC)
import sys
for base in [int(a,16) for a in sys.argv[1:]]:
    m=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ,offset=base)
    print(hex(base), hex(struct.unpack('<I',m[0:4])[0]), flush=True)
PY
