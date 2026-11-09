# Reproducing the build (rewritten 2026-11-09)

Produced on a plain Linux host with `clang`/LLVM and flashed over `fastboot`. `docs/PROGRESS.md` has the
measurements behind each step; `docs/STATUS.md` says what works today.

## What was checked, and what was not

Checked on 2026-11-09 in a clean room (pristine `linux-7.2.10.tar.xz`, sha256 prefix `2feaa70453e9`):

| Step | Result |
|---|---|
| `git apply patches/violet-7.2.10-all.patch` on the pristine tree | applies cleanly (two trailing-whitespace warnings) |
| Resulting source files vs. the tree that was actually flashed | byte-identical (all 72 files compared) |
| `make qcom/violet-sm6150.dtb` with `configs/config-7.2.10-sm6150-2026-11-02` | builds in about 2 s |
| Full `Image` + `modules` build (clang 23.1.4, `-j16`) | exit 0, no warnings logged; `Image` 36 MB reports `Linux version 7.2.10-sm6150`; `imx586`, `dw9800`, `s5k5e8`, `ov13855` `.ko` all define `init_module` |
| Out-of-tree `patches/qg` (`violet-qg.ko`) built against that tree | builds |
| The numbered `patches/00NN-*.patch` applied one after another | **does not work** (see below) |

**Not checked:** flashing a fresh phone from this repo, the firmware extraction recipes, and the userspace setup
(`phone/` scripts, rootfs) end to end. The maintainer's phone was set up incrementally, and a userdata wipe on
2026-11-03 was rebuilt from `host/phone-restore.sh` plus notes, which is the closest thing to a clean install.

> **Two device-specific traps, read first**
> 1. **The `dtbo` partition must stay erased.** ABL then skips the vendor overlay path and takes the single DTB
>    appended to the boot image. Re-flashing `dtbo-vendor.img` re-arms an overlay that refuses this DTB and the
>    phone will not boot mainline. (`fastboot erase dtbo` is one-time; save your own `dtbo` dump first.)
> 2. **Firmware blobs are device-signed and not in this repo.** They must come from your own phone's partitions.

## 1. Prerequisites

- Redmi Note 7 Pro (`violet`), **unlocked bootloader**, stock ABL in place.
- Linux host: `clang`/`lld` (LLVM), `make`, `bc`, `flex`, `bison`, `dtc`, `fdtput`/`fdtget`, `mkbootimg`,
  `fastboot`, `xz`, `git`.
- A restorable baseline on `boot`: the downstream postmarketOS image for violet (`boot-r10.img` / `rootfs-r9.img`).
  Its ramdisk is reused verbatim by the mainline boot image, and its rootfs is what the kernel boots into.
- About 6 GB of free disk for a full build (a RAM-backed `/tmp` is too small).

## 2. Kernel source: use the consolidated patch

```bash
curl -LO https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.10.tar.xz
tar xf linux-7.2.10.tar.xz && cd linux-7.2.10
git apply ../patches/violet-7.2.10-all.patch
```

`patches/violet-7.2.10-all.patch` is the **diff between pristine 7.2.10 and the tree that boots on the phone**
(72 files: the board DTS and camera dtsi, all driver changes, and the new drivers `imx586`, `s5k5e8`, `ov13855`,
`dw9800`, `qcom-lcdb-regulator`, `pinctrl-sm6150-lpass-lpi`, `violet-vbat`). It is the authoritative source.

The numbered patches in `patches/` are the per-feature history, useful for reading and for upstreaming. **Do not
apply them in sequence.** On 2026-11-09 the full old series failed against pristine 7.2.10 (0015, 0021, 0023, 0032 and
0033 did not apply in order; 0043/0044 are not in a format `git apply` accepts). The superseded and diagnostic
patches (0014, 0019-0023, 0026, 0027, 0033, plus 0005) were removed from the repo on 2026-11-09 (they remain in git
history). `patches/README.md` lists what each remaining one does.

The kernel config is `configs/config-7.2.10-sm6150-2026-11-02` (the same as the flashed tree's `.config` apart from
the clang version strings). Earlier dated configs are kept for history.

## 3. Build

```bash
cp ../configs/config-7.2.10-sm6150-2026-11-02 .config
make ARCH=arm64 LLVM=1 olddefconfig          # NOT CROSS_COMPILE=: a wrong toolchain deletes generated headers
make ARCH=arm64 LLVM=1 -j"$(nproc)" Image modules qcom/violet-sm6150.dtb \
     CONFIG_VIDEO_IMX586=m CONFIG_VIDEO_DW9800=m CONFIG_VIDEO_S5K5E8=m CONFIG_VIDEO_OV13855=m
```

The four camera drivers have no Kconfig entries, only `obj-$(CONFIG_...)` lines in `drivers/media/i2c/Makefile`, so
the `CONFIG_VIDEO_*=m` words must be on the make command line, and rebuilding one with `make M=...` needs them too
(without them the object is compiled without `-DMODULE` and fails to load with "Unknown symbol init_module").
Install modules with `make ARCH=arm64 LLVM=1 modules_install INSTALL_MOD_PATH=<rootfs>` (the camera ones land in
`extra/` if you copy them by hand).

The battery gauge and charger driver is an **out-of-tree module**, built against the tree you just built:

```bash
make -C linux-7.2.10 ARCH=arm64 LLVM=1 M=$PWD/../patches/qg modules      # produces violet-qg.ko
```

It binds through the `xiaomi,violet-vbat` compatible in the DTS. It needs the patched `qcom-spmi-adc5` (the
`bat_therm_100k_pu` entry), which is already inside the consolidated patch.

Products: `arch/arm64/boot/Image`, `arch/arm64/boot/dts/qcom/violet-sm6150.dtb`, the module tree.

## 4. Firmware (from your own phone)

Place these under `/lib/firmware/` of the rootfs:

| Blob | Path | Source |
|---|---|---|
| `a630_sqe.fw`, `a612_rgmu.bin` | `qcom/` | linux-firmware |
| `a612_zap.mdt` + `.b00/.b01/.b02` | `qcom/` | **your device** (ROM `a612_zap.elf`, device-signed) |
| `modem.mdt` + `modem.b*` | `qcom/qcs615/` | your phone's `modem` partition |
| `wlanmdsp.mbn`, `bdwlan.*` | `qcom/`, `ath10k/WCN3990/hw1.0/` | `modem` partition (31 `bdwlan.*` files) |
| `adsp.mdt`, `adsp.b*` | `qcom/qcs615/` | your phone's `dsp` partition |
| sensor configs (hexagonrpcd) | `/usr/local/share/violet-sensors` | vendor partitions; `phone/install-sensors.sh` shows the recipe |
| `tas2563_*.bin` | n/a | **not needed**: the amp runs in ROM mode (`no_rca_mode=2`); no violet vendor image ships the regbin |

Camera sensor register tables are not firmware: they are recovered from the vendor `sensormodule.bin` and compiled
into `imx586-vendor-tables.h` (inside the consolidated patch). Extraction recipes that were actually used are in
`docs/PROGRESS.md` (search `debugfs`, `vendor.img`, `rmtfs`, `bdwlan`).

## 5. Boot image

`host/mk-bootimg-clean.sh` needs a ramdisk from a working downstream `boot.img`:

```bash
mkdir -p bootimg-r9 && cd bootimg-r9 && unpack_bootimg --boot_img ../boot-r10.img --out .
```

The script's built-in `CMDLINE` contains the **maintainer's** `pmos_boot_uuid`/`pmos_root_uuid`. Pass your own
(from `blkid` on the `pmOS_boot` and root partitions) in `CMDLINE`, as the script reads `${CMDLINE:-...}`, keeping the
other words: `plymouth.ignore-serial-consoles androidboot.hardware=qcom swiotlb=1 loop.max_part=7 kpti=off`.
There is no `msm.separate_gpu_kms` (booting without it gives one DRM device, card0 with DSI-1 plus renderD128).
The script round-trips the DTB through `dtc -@` (ABL needs `__symbols__`), injects `qcom,msm-id`/`qcom,board-id`,
and runs `mkbootimg` with header v2, 4 KiB pages and the violet geometry (base 0, kernel 0x8000, ramdisk 0x01000000,
tags 0x100, dtb 0x01f00000).

## 6. Flash

```bash
./host/enter-fastboot.sh               # reboots into the bootloader over ssh, no button combo
fastboot erase dtbo                    # once; save your own dump first
fastboot flash boot boot-mainline.img  # only `boot` is ever flashed
fastboot reboot
```

Never touch `userdata`. Keep a backup of `boot` and verify its hash before the first flash.

## 7. Userspace (not clean-room tested)

The base is the downstream pmOS rootfs; everything on top is installed from `phone/` (services, audio setup
`violet-audio-setup`, modem/WiFi `violet-modem.initd`, `install-sensors.sh`, `install-camera.sh`, the suspend hook
`patches/0036-...sh`, sleep-inhibitor `patches/0037-...conf`). `host/phone-backup.sh` and `host/phone-restore.sh`
rebuild a wiped phone from your own backup (`docs/RESTORE.md`). A third-party user will have to follow the
`2026-11-03 18:00` entry in `docs/PROGRESS.md` (the rebuild after a wipe) for the package list and ordering.

## 8. What you should see

- `Linux version 7.2.10-sm6150`; the panel lights; `msm ae01000.display-controller: [drm] Initialized msm`.
- Modem up with 41 QMI services; `wlan0` associates; speaker plays from `hw:0,2`, microphone and headphones work
  (headphones use `hw:0,3`; see `docs/STATUS.md`).
- Three cameras in GNOME Camera; sensors via `iio-sensor-proxy`; suspend and resume; USB-C PD charging.
- Open items and known limits: `docs/STATUS.md` ("Open items").

## 9. Known failure modes

| Symptom | Meaning | Where |
|---|---|---|
| Phone drops to fastboot after flashing | `dtbo` was re-flashed or not erased | trap 1 above |
| Black panel at boot | missing dispcc MDSS_CORE reset / pclk0 parent enable (in the consolidated patch; do not drop it) | `docs/PROGRESS.md` 2026-10-31 |
| `AFE set params failed -110` | ADSP services not built in (`QRTR_SMD`, `RPMSG_QCOM_GLINK_SMEM`, `QCOM_FASTRPC`, `QCOM_PD_MAPPER` must be `=y`) or SMMU context-bank reservation missing | `docs/STATUS.md` |
| No WiFi, `vdev start` rejected | ath10k ordering: BSS peer before station vdev start | `docs/PROGRESS.md` WiFi entries |
| Camera module "Unknown symbol init_module" | built without `CONFIG_VIDEO_*=m` on the make line | section 3 |
| Reboot sometimes freezes | open, intermittent CPU stall | `docs/STATUS.md` |
| `qcom_q6v5_pas ... Handover signaled` flood | modem remoteproc log spam | `docs/CHECKLIST.md` S6 |

## 10. Going back

`fastboot flash boot boot-r10.img && fastboot reboot`. Never re-flash `dtbo-vendor.img` unless you also go back to
the vendor boot image. If the phone wedges, hold Power ~15 s; ABL still enters fastboot with Volume Down.
