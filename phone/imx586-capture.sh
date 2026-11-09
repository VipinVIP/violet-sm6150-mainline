#!/bin/sh
M="media-ctl -d /dev/media0"
$M -l '"msm_csiphy0":1->"msm_csid0":0[1],"msm_csid0":1->"msm_vfe0_rdi0":0[1]'
F=SBGGR10_1X10/4000x3000
$M -V "\"imx586 3-001a\":0[fmt:$F],\"msm_csiphy0\":0[fmt:$F],\"msm_csiphy0\":1[fmt:$F],\"msm_csid0\":0[fmt:$F],\"msm_csid0\":1[fmt:$F],\"msm_vfe0_rdi0\":0[fmt:$F]"
v4l2-ctl -d /dev/video0 --set-fmt-video=width=4000,height=3000,pixelformat=pBAA
for sd in /dev/v4l-subdev*; do v4l2-ctl -d $sd -l 2>/dev/null | grep -q exposure && SD=$sd; done
echo SD=$SD
[ -n "$SD" ] && v4l2-ctl -d $SD -c exposure=${1:-3000},analogue_gain=${2:-0}
rm -f /tmp/f.raw
timeout 10 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=/tmp/f.raw
ls -l /tmp/f.raw
