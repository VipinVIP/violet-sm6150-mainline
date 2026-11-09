#!/bin/sh
# serve the ADSP's reverse fastrpc file requests from the dsp partition (needed by the audio PD's module loads)
mkdir -p /mnt/dsp /vendor/lib/rfsa
mountpoint -q /mnt/dsp || mount -o ro /dev/mmcblk0p71 /mnt/dsp
[ -e /vendor/dsp ] || ln -s /mnt/dsp /vendor/dsp
[ -e /vendor/lib/rfsa/adsp ] || ln -s /mnt/dsp /vendor/lib/rfsa/adsp
ls /dev/fastrpc-adsp* 
nohup hexagonrpcd -f /dev/fastrpc-adsp-secure -d adsp -R /mnt/dsp > /var/tmp/hexagonrpcd.log 2>&1 &
sleep 2; cat /var/tmp/hexagonrpcd.log; pgrep -x hexagonrpcd
