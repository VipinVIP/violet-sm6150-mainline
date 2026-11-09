#!/bin/sh
# Rear IMX586 capture: csiphy0 -> csid0 -> vfe0_rdi0, 4000x3000 10-bit SBGGR->SRGGB.
# Usage: cap.sh [exposure] [gain]
#
# Two traps this script handles (2026-11-04):
#  * the imx586 subdev's mbus code is SRGGB10 (video pixelformat pRAA); setting
#    SBGGR10 makes media_pipeline_start fail link validation -> STREAMON -EPIPE;
#  * a CSID input routes to one CSIPHY only, so the front/aux links must be
#    released first or the rear link comes back "Resource busy".
# media-ctl wants one link per -l call here; a comma-joined list is rejected.
M="media-ctl -d /dev/media0"
$M -l '"msm_csiphy1":1->"msm_csid0":0[0]' >/dev/null 2>&1
$M -l '"msm_csiphy2":1->"msm_csid0":0[0]' >/dev/null 2>&1
$M -l '"msm_csiphy0":1->"msm_csid0":0[1]'
$M -l '"msm_csid0":1->"msm_vfe0_rdi0":0[1]'
F=SRGGB10_1X10/4000x3000
$M -V "\"imx586 3-001a\":0[fmt:$F],\"msm_csiphy0\":0[fmt:$F],\"msm_csiphy0\":1[fmt:$F],\"msm_csid0\":0[fmt:$F],\"msm_csid0\":1[fmt:$F],\"msm_vfe0_rdi0\":0[fmt:$F]"
v4l2-ctl -d /dev/video0 --set-fmt-video=width=4000,height=3000,pixelformat=pRAA
for sd in /dev/v4l-subdev*; do
	v4l2-ctl -d $sd -L 2>/dev/null | grep -q "exposure .*max=3048" && SD=$sd
done
echo SD=$SD
[ -n "$SD" ] && v4l2-ctl -d $SD -c exposure=${1:-800},analogue_gain=${2:-256}
rm -f /var/tmp/f.raw
timeout 15 v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=1 --stream-to=/var/tmp/f.raw
ls -l /var/tmp/f.raw
