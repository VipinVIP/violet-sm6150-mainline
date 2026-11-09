#!/bin/sh
set -e
LOG=/var/tmp/lc-build.log
: > $LOG
exec >>$LOG 2>&1
echo "=== start $(date)"
sudo -n apk add meson ninja gcc g++ python3-dev py3-jinja2 py3-yaml py3-ply libdrm-dev gnutls-dev libevent-dev libunwind-dev eudev-dev yaml-dev
mkdir -p /home/user/lc && cd /home/user/lc
[ -f libcamera-v0.7.2.tar.gz ] || wget -q https://gitlab.freedesktop.org/camera/libcamera/-/archive/v0.7.2/libcamera-v0.7.2.tar.gz
ls -l libcamera-v0.7.2.tar.gz
rm -rf libcamera-v0.7.2 output-$(whoami)
tar xf libcamera-v0.7.2.tar.gz
cd libcamera-v0.7.2
meson setup ../output -Dpipelines=simple,virtual -Dv4l2=disabled -Dgstreamer=disabled -Dqcam=disabled -Ddocumentation=disabled -Dpycamera=disabled -Dwerror=false -Dprefix=/usr/local
ninja -C ../output
sudo -n ninja -C ../output install
echo "=== done $(date)"
ls -l /usr/local/lib/libcamera* 2>/dev/null | head -3
