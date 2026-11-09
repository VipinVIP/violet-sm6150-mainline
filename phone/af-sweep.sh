#!/bin/sh
# Rear VCM (DW9800-class, i2c-3 @0x0c) focus sweep: one raw frame per lens position.
# Usage: af-sweep.sh [exposure] [gain]   -> /var/tmp/af/pos<N>.raw
mkdir -p /var/tmp/af; rm -f /var/tmp/af/*
i2cset -y 3 0x0c 0x02 0x00   # release power-down
for pos in 0 100 200 300 400 500 600 700 800 900 1023; do
	i2cset -y 3 0x0c 0x03 $((pos>>8)) 0x04 $((pos&255)) i 2>/dev/null || { i2cset -y 3 0x0c 0x03 $((pos>>8)); i2cset -y 3 0x0c 0x04 $((pos&255)); }
	sleep 0.4
	sh /var/tmp/cap.sh ${1:-1500} ${2:-256} >/dev/null 2>&1
	mv /var/tmp/f.raw /var/tmp/af/pos$pos.raw
done
ls -l /var/tmp/af
