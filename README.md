# Mainline Linux on the Xiaomi Redmi Note 7 Pro (`violet`)

Running **upstream Linux (7.2.10) natively** on the Redmi Note 7 Pro — not Android, not a
downstream kernel. ABL boots a mainline `boot.img` directly, and userspace is postmarketOS with
Phosh. This repository is the build/flash kit plus the full evidence log: every patch, the kernel
config, the on-device scripts, and a dated record of what was measured, what failed and why.

**Device:** Xiaomi Redmi Note 7 Pro (`violet`), Qualcomm SM6150/QCS615, Adreno 612,
6.3" 2340×1080 NT36672A panel (shenchao variant), 4/6 GB RAM, UFS/eMMC, 4030 mAh.

## Status at a glance

Full matrix with evidence in [`docs/STATUS.md`](docs/STATUS.md).

| Area | State |
|---|---|
| Boot | **Works** — ABL boots the mainline image natively (no kexec, no chainload) |
| Display / DSI / panel | **Works** — 2340×1080, backlight, brightness |
| Touch (NT36672A) | **Works** |
| Storage (eMMC), USB gadget, netconsole | **Works** |
| WiFi (WCN3990 / ath10k) | **Works** — station and AP mode |
| Audio out: ADSP/APR/PCM + TAS2563 speaker amp | **Works** — speaker audible, no RCA firmware needed |
| Modem (MPSS) | **Works** — 41 QMI services, SMS/data path up |
| Android apps (ATL) | **Runs** — simple and real apps; video is blocked by the GPU issue below |
| GPU (freedreno A612 + Turnip) | **Renders, but locks up under load** — `hangcheck detected gpu lockup rb 0`, kills clients |
| Microphone (WCD9375/SoundWire) | **Broken** — codec parked on `MASTER_CLASH_DET` |
| Sensors, camera | **Not started** — behind the Snapdragon Sensor Core, no mainline SSC/CHRE driver |
| Suspend / resume | **Does not work** — only `s2idle`, never comes back; currently masked |

The honest headline: this is a **working daily-driver-shaped port** minus three well-scoped holes —
GPU stability under load, the microphone, and suspend. [`docs/CHECKLIST.md`](docs/CHECKLIST.md)
lists exactly what is left and whether each item needs physical USB access.

## Layout

| Path | What |
|---|---|
| `docs/STATUS.md` | One line per subsystem: works / broken, why, and where the evidence is |
| `docs/CHECKLIST.md` | What remains, with a "needs the USB cable?" column, plus historical measurement tables |
| `docs/PROGRESS.md` | Dated engineering log, newest first — the actual evidence trail |
| `docs/RULED-OUT.md` | Dead ends and the exact experiments that killed them — read before re-testing anything |
| `docs/REPRODUCE.md` | Build and flash walkthrough, firmware notes, expected output, failure modes |
| `patches/` | 17 patches against vanilla 7.2.10, in series order (`patches/README.md` explains each) |
| `dt/violet-sm6150.dts` | The board DTS exactly as flashed — authoritative over the DTS inside patch 0001 |
| `configs/` | Kernel `.config` used to build the shipped image |
| `host/` | Scripts that run on your build machine (boot image, fastboot, ssh helpers); `host/legacy/` = the earlier kexec workflow |
| `phone/` | Scripts and config files that run on the device (audio, modem, WiFi, session, ATL) |
| `tools/` | Probe/debug utilities (registers, DRM, I2C, GPU, ACPI-adjacent pokes) |

## Quick start

```bash
git clone https://github.com/VipinVIP/violet-sm6150-mainline.git
cd violet-sm6150-mainline

# 1. vanilla kernel source
curl -LO https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.10.tar.xz
tar xf linux-7.2.10.tar.xz && cd linux-7.2.10

# 2. patch series, then the authoritative DTS on top
for p in ../patches/0*.patch; do git apply "$p" || echo "FAILED: $p"; done
cp ../dt/violet-sm6150.dts arch/arm64/boot/dts/qcom/violet-sm6150.dts

# 3. configure and build
cp ../configs/config-7.2.10-sm6150-2026-10-27 .config
make ARCH=arm64 LLVM=1 olddefconfig
make ARCH=arm64 LLVM=1 -j"$(nproc)" Image qcom/violet-sm6150.dtb

# 4. boot image + flash (see docs/REPRODUCE.md for firmware and the ramdisk)
cd .. && PMOS_BOOT_UUID=... PMOS_ROOT_UUID=... ./host/mk-bootimg-clean.sh
./host/enter-fastboot.sh && fastboot flash boot boot-mainline.img && fastboot reboot
```

Read [`docs/REPRODUCE.md`](docs/REPRODUCE.md) before flashing anything — there are two
device-specific traps (the `dtbo` partition must stay erased, and the firmware blobs are
device-signed and must come from the phone's own partitions).

## What makes this port work

The non-obvious pieces, all documented in the patch series and the log:

- **Boot:** `dtbo` is deliberately erased, so ABL skips the vendor overlay path and takes our single
  appended DTB. Reflashing `dtbo-vendor.img` re-arms an overlay that refuses our DTB.
- **GPU:** the A612 comes up through its RGMU with the device-signed zap shader; DSI/display needs
  the dispcc GDSC/XO fix and the shenchao panel variant.
- **Audio:** the TAS2563 amplifier runs in ROM mode (no `tas2563RCA1.bin` exists in any vendor image
  for this device), and the WCD9375 needs the hyp-owned SMMU context banks reserved.
- **Modem/WiFi:** watchdogs, `rmtfs -o`, pd-mapper one-entry-per-domain, early glink intents, and for
  ath10k the BSS peer must be created **before** the station vdev starts.

## Hardware support for other devices

Nothing here is violet-only by design where it doesn't have to be: the panel, ath10k, tas2781 and
arm-smmu changes are generic fixes that happened to be found on this phone, and several have upstream
potential. The board DTS and the `qcom,msm-id`/`board-id` injection in `host/mk-bootimg-clean.sh` are
the only truly device-specific parts.

## Not in this repository

Kernel build trees, boot images, firmware blobs, partition dumps and device backups are deliberately
excluded: the blobs are vendor-signed and not redistributable, and the dumps contain device-unique
identifiers (IMEI, MACs, calibration data). [`docs/REPRODUCE.md`](docs/REPRODUCE.md) explains how to
pull them from your own device.

## Credits

postmarketOS (device bring-up conventions, `pmaports`), the Linux `drm/msm`, `ath10k`, `ASoC` and
`arm-smmu-qcom` maintainers, Mesa freedreno/Turnip, Phosh, [glissando](https://github.com/x-vlad-x/glissando)
(on-screen keyboard; upstream PR [#1](https://github.com/x-vlad-x/glissando/pull/1) came out of this port),
and the Android Translation Layer project for the `APK`-on-Linux experiments.

No warranty. Flashing a boot image to a phone can brick it; you are responsible for your own device and
for backing up your own partitions first.
