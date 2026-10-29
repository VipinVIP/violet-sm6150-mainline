# Reproducing the build

Everything here was produced on a plain Linux host with `clang`/LLVM and flashed over `fastboot`.
This page is the shortest accurate path; `docs/PROGRESS.md` has the measurements behind each step.

> **Two device-specific traps, read first**
> 1. **The `dtbo` partition must stay erased.** ABL then skips the vendor overlay path and takes the
>    single DTB appended to the boot image. Re-flashing `dtbo-vendor.img` re-arms an overlay that
>    refuses this DTB and the phone will not boot mainline. (Erasing `dtbo` needs a one-time
>    `fastboot erase dtbo`, and it is reversible only by flashing your own saved `dtbo` dump.)
> 2. **Firmware blobs are device-signed and not in this repo.** `a612_zap.mdt`, `a612_rgmu.bin`,
>    `a630_sqe.fw`, the modem/WiFi blobs and the ADSP firmware must come from your own phone's
>    partitions. They are tied to your device's signature; other phones' copies will not load.

## 1. Prerequisites

- Redmi Note 7 Pro (`violet`) with an **unlocked bootloader** and stock ABL still in place.
- A Linux build host with: `clang`/`lld` (LLVM toolchain), `make`, `bc`, `flex`, `bison`,
  `dtc`, `fdtput`/`fdtget` (device-tree-compiler), `mkbootimg` (Android `mkbootimg` or
  `android-sdk-tools`), `fastboot`, `xz`.
- The phone running *something* on its `boot` partition you can restore — the safest baseline is the
  downstream postmarketOS image for `violet` (`boot-r10.img`), because the ramdisk in it is reused
  verbatim by the mainline boot image.

## 2. Kernel source and patches

```bash
curl -LO https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.10.tar.xz
tar xf linux-7.2.10.tar.xz
cd linux-7.2.10

for p in ../patches/0*.patch; do
    git apply "$p" || { echo "FAILED: $p"; break; }
done
# patch 0001 adds an early DTS plus the Makefile/binding entries; the authoritative
# board DTS is the one in dt/, which is what actually boots:
cp ../dt/violet-sm6150.dts arch/arm64/boot/dts/qcom/violet-sm6150.dts
```

`patches/README.md` says what each patch does and which ones are load-bearing for which subsystem.
Patch 0014 is not shipped: it is superseded by 0015.

## 3. Configure and build

```bash
cp ../configs/config-7.2.10-sm6150-2026-10-27 .config
scripts/config --disable DEBUG_INFO      # optional: much faster builds
make ARCH=arm64 LLVM=1 olddefconfig
make ARCH=arm64 LLVM=1 -j"$(nproc)" Image qcom/violet-sm6150.dtb
```

Product: `arch/arm64/boot/Image` and `arch/arm64/boot/dts/qcom/violet-sm6150.dtb`.

## 4. Firmware (from your own phone)

Place these under `/lib/firmware/` on the rootfs the kernel will boot:

| Blob | Path | Source |
|---|---|---|
| `a630_sqe.fw` | `qcom/a630_sqe.fw` | linux-firmware |
| `a612_rgmu.bin` | `qcom/a612_rgmu.bin` | linux-firmware |
| `a612_zap.mdt` + `.b00/.b01/.b02` | `qcom/` | **your device**, ROM `a612_zap.elf` split/signed by your ABL; the single-file form the kernel requests is the device-signed set |
| modem: `modem.mdt` + `modem.b00..b27` | `qcom/qcs615/` | your phone's `modem` partition |
| `wlanmdsp.mbn`, `bdwlan.*` | `qcom/` + `ath10k/WCN3990/hw1.0/bdwlan.bin` | `modem` partition (31 `bdwlan.*` files), packed with `ath10k-bdencoder` |
| `adsp.mdt`, `adsp.b*` | `qcom/qcs615/` | your phone's `dsp` partition |
| `tas2563_*.bin` | — | **not needed**: the amp runs in ROM mode (`no_rca_mode=2`); no `tas2563RCA1.bin` exists in any violet vendor image |

Extraction recipes that were actually used here are in `docs/PROGRESS.md` (search for `debugfs`,
`vendor.img`, `rmtfs`, `bdwlan`). The short version: pull the partition, then `debugfs -R "ls /firmware"`
or `strings`/`binwalk` to locate the blobs, and keep the file names exactly as the kernel requests them.

## 5. Boot image

`host/mk-bootimg-clean.sh` needs a **ramdisk** from a working downstream `boot.img`
(`host/bootimg-r9/` in the original tree). Unpack one with:

```bash
mkdir -p bootimg-r9 && cd bootimg-r9
unpack_bootimg --boot_img ../boot-r10.img --out .
```

Then build, with the UUIDs of *your* install (get them from the device: `blkid` on the `pmOS_boot` and
root partitions):

```bash
PMOS_BOOT_UUID=<boot-partition-uuid> PMOS_ROOT_UUID=<rootfs-uuid> ./host/mk-bootimg-clean.sh
```

The script: round-trips the DTB through `dtc -@` so `__symbols__` exists (ABL needs it), injects
`qcom,msm-id`/`qcom,board-id`, then `mkbootimg` with 4 KiB pages, header v2 and the violet geometry.

## 6. Flash and verify

```bash
./host/enter-fastboot.sh              # reboots via PON soft-reboot, no button combo
fastboot flash boot boot-mainline.img
fastboot reboot
```

Expected on the way up (serial console, netconsole, or `dmesg` after login):

- `Booting Linux on physical CPU 0x0000000000` and `Linux version 7.2.10-sm6150`
- `msm_dpu ae01000.display-controller: bound ae01000.display-controller` and a lit panel
- `msm ae01000.display-controller: [drm] Initialized msm`
- `qcom_q6v5_pas … remoteproc1: modem is available`, then `remote processor modem is now up`
- `ath10k: wl0: firmware ready` → `wlan0` associates
- `snd_soc_tas2781 … 1-004c` bound; a tone on `hw:0,2` is audible
- `android-translation-layer` runs an APK (once you install ATL, see `docs/CHECKLIST.md` §7)

## 7. Going back

Flash your downstream boot image back to `boot`:

```bash
fastboot flash boot boot-r10.img && fastboot reboot
```

Never re-flash `dtbo-vendor.img`: it is what the mainline path depends on being absent. Restore it only
if you want to go back to the vendor DT overlay world, and only together with the vendor boot image.

## 8. Known failure modes (all reproduced and documented)

| Symptom | Meaning | Where |
|---|---|---|
| `adreno_idle: timeout waiting to drain ringbuffer 0 rptr/wptr = 0/C` → `hangcheck detected gpu lockup rb 0` → clients segfault | GPU locks up under load, especially after a long suspend. Recovers, but the client that owned the context dies | `docs/RULED-OUT.md` (2026-10-29 section) — firmware, DTS votes and `adreno_recover` all ruled out |
| `qcom_q6v5_pas 62400000.remoteproc: Handover signaled, but it already happened` flooding dmesg | modem remoteproc log spam, ~94% of the ring, rotates real crash evidence away | `docs/CHECKLIST.md` S6 |
| `AFE set params failed -110` on audio | ADSP AFE not answering — check pd-mapper domains and the SMMU context-bank reservation (patch 0017) | `docs/PROGRESS.md` audio entries |
| `MASTER_CLASH_DET` on WCD9375 | SoundWire codec parked; microphone known broken | `docs/STATUS.md` |
| No WiFi, `vdev start` rejected ×3 | ath10k ordering: the BSS peer must exist before station vdev start (patch 0015) | `docs/PROGRESS.md` WiFi entries |

## 9. Housekeeping that saves you a brick

- Back up `boot`, `dtbo`, `modem`, `dsp`, `persist`, `misc` **before** the first flash.
- Keep a known-good `boot.img` on the host, not only on the phone.
- `msm.separate_gpu_kms=1` is in the kernel command line on purpose: the GPU stays a separate DRM device.
- If the phone wedges, hold Power ~15 s; ABL still boots fastboot with Volume Down.
