#!/bin/sh
M="media-ctl -d /dev/media0"
for p in 0 1 2; do $M -l "\"msm_csiphy$p\":1->\"msm_csid0\":0[0]" >/dev/null 2>&1; done
IDX=$(cam -l 2>/dev/null | grep -i "front camera" | cut -d: -f1 | tr -d " ")
echo "front index $IDX"
rm -f /var/tmp/sys*.bin /var/tmp/pat*.bin
echo "--- A: system libcamera"
timeout 60 cam -c $IDX --capture=8 --file=/var/tmp/sys#.bin >/dev/null 2>&1
python3 /var/tmp/abstats.py "/var/tmp/sys*.bin"
echo "--- B: patched libcamera (/usr/local)"
export LD_LIBRARY_PATH=/usr/local/lib LIBCAMERA_IPA_MODULE_PATH=/usr/local/lib/libcamera/ipa
timeout 60 cam -c $IDX --capture=8 --file=/var/tmp/pat#.bin >/dev/null 2>&1
python3 /var/tmp/abstats.py "/var/tmp/pat*.bin"
