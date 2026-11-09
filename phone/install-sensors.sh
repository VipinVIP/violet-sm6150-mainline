#!/bin/sh
# Bring up the Snapdragon Sensor Core on violet (mainline), end to end.
#
# Status 2026-10-30: WORKS.  accelerometer, gyroscope, magnetometer, ambient light and proximity all
# return live values, and iio-sensor-proxy exposes them (Phosh auto-rotate / auto-brightness consumers).
#
# What this does, and why each step is needed:
#   1. the ADSP's SNS framework asks its FastRPC config daemon for JSON sensor configs, a registry path
#      and the Android socinfo sysfs attributes; none of those exist on mainline, so they are staged
#   2. the sensors themselves are on the *SSC's* buses (LSM6DS3-C on SPI inst. 2, AK0991x and STK3x3x on
#      I2C inst. 1 at 0x0c/0x47), so an AP-side iio driver cannot reach them - everything goes through SSC
#   3. hexagonrpcd attaches to the sensor protection domain with `-s` on the FastRPC device
#      (/dev/fastrpc-adsp-secure on this port - there is no plain /dev/fastrpc-adsp)
#
# Run as root on the phone.  Idempotent.  Assumes violet-sensors.tar.gz was placed in /tmp.
set -e

ROOT=/usr/local/share/violet-sensors
TARBALL=${1:-/tmp/violet-sensors.tar.gz}

command -v hexagonrpcd >/dev/null || { echo "FATAL: hexagonrpcd not installed (apk add hexagonrpcd hexagonrpcd-openrc hexagonrpcd-udev)"; exit 1; }
[ -f "$TARBALL" ] || { echo "FATAL: no $TARBALL"; exit 1; }
[ -e /dev/fastrpc-adsp-secure ] || { echo "FATAL: /dev/fastrpc-adsp-secure missing - is the ADSP up?"; exit 1; }

# --- 1. staged files the SNS framework asks for -------------------------------------------------
mkdir -p "$ROOT"
tar xzf "$TARBALL" -C "$ROOT"

# Android-only socinfo sysfs, faked from the vendor configs (talos soc_id = 355)
mkdir -p "$ROOT/sys/devices/soc0"
printf MTP > "$ROOT/sys/devices/soc0/hw_platform"
printf 0   > "$ROOT/sys/devices/soc0/platform_subtype"
printf 0   > "$ROOT/sys/devices/soc0/platform_subtype_id"
printf 0   > "$ROOT/sys/devices/soc0/platform_version"
printf 355 > "$ROOT/sys/devices/soc0/soc_id"
printf 0   > "$ROOT/sys/devices/soc0/revision"

# persist stubs: the DSP writes the generated registry here
mkdir -p "$ROOT/mnt/vendor/persist/sensors/registry"
[ -f "$ROOT/mnt/vendor/persist/sensors/registry/sns_reg_version" ] || printf 1 > "$ROOT/mnt/vendor/persist/sensors/registry/sns_reg_version"
touch "$ROOT/mnt/vendor/persist/sensors/registry/file1" "$ROOT/mnt/vendor/persist/sensors/registry/file2"

chown -R fastrpc:fastrpc "$ROOT/sensors/registry" "$ROOT/mnt" "$ROOT/sys"

# --- 2. init script: device override (packaged script hardcodes /dev/fastrpc-adsp) ---------------
INIT=/etc/init.d/hexagonrpcd-adsp-sensorspd
if ! grep -q hexagonrpcd_dev "$INIT"; then
	cp "$INIT" "$INIT.orig"
	sed -i 's|command_args="-f /dev/fastrpc-adsp -d adsp -s"|command_args="-f ${hexagonrpcd_dev:-/dev/fastrpc-adsp-secure} -d adsp -s"|' "$INIT"
fi

printf 'hexagonrpcd_dev=/dev/fastrpc-adsp-secure\nhexagonrpcd_fw_dir=%s\n' "$ROOT" > /etc/conf.d/hexagonrpcd-adsp-sensorspd

# --- 3. start -----------------------------------------------------------------------------------
rc-update add hexagonrpcd-adsp-sensorspd default
rc-service hexagonrpcd-adsp-sensorspd restart
rc-service iio-sensor-proxy restart

# --- 4. orientation: NO mount-matrix rule (retracted 2026-10-30 21:55) ----------------------------
# A udev ACCEL_MOUNT_MATRIX="-1,0,0;0,-1,0;0,0,1" rule was installed earlier today on the theory that
# the vendor .orient (x=-x, y=-y, z=+z) had to be applied by hand.  That was WRONG and it is what made
# the UI render upside down: with the rule, an upright phone reported Gravity Y=-9.93 and
# AccelerometerOrientation='bottom-up'; with the rule removed, the SAME pose and SAME raw accel report
# 'normal'.  So the SSC data is already in the device frame - leave the mount matrix alone.
# If orientation ever looks wrong, verify with:  ssccli --sensor accelerometer  +  monitor-sensor --accel
# BEFORE adding any matrix, and remember the Sensors panel shows stale values after a proxy restart.

sleep 3
echo "--- verification ---"
ssccli --sensor accelerometer 2>/dev/null | head -2 || true
ssccli --sensor light 2>/dev/null | head -2 || true
monitor-sensor --accel 2>&1 | head -4 || true

cat <<'EOF'

Expected: accel ~ (0,0,9.8) m/s^2 when the phone lies flat, "Light changed: N lux", and
"Has accelerometer" from iio-sensor-proxy.

Known cosmetic issue: "Mount matrix provided by firmware is all 0, falling back to identity matrix" -
the vendor configs carry .orient but a zero .placement, so rotation direction may be inverted; fix by
setting the placement/orientation in sensors/config/talos_lsm6ds3c_0.json or a mount matrix in
iio-sensor-proxy.
EOF
