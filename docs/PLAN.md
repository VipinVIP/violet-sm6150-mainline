# violet mainline port — design and plan

Goal: a mainline (`drm/msm`) kernel on the Redmi Note 7 Pro, so the Adreno 612 becomes a **DRM
device**. That is the only way to get GPU acceleration on this phone; see "why" below.

## Why mainline is the only route (proven, not assumed)

The downstream KGSL path is a dead end for *acceleration*, even though the driver now works:

- KGSL is a **char device** (`/dev/kgsl-3d0`), not DRM. This kernel has no KGSL->DRM shim
  (`0` matches for any `KGSL_DRM` config; `0` files in `drivers/gpu/msm/` referencing
  `drm_dev_alloc`/`drm_gem`).
- Mesa **turnip has no KGSL backend** — the installed ICD ships only `tu_knl_drm_msm.cc` and
  `tu_knl_drm_virtio.cc`.
- Mesa's gallium KGSL driver *is* compiled in (`__driDriverGetExtensions_kgsl`) but no EGL platform
  can hand it a `/dev/kgsl-3d0` fd (`DRI2: Device isn't of _EGL_DEVICE_DRM type` -> swrast).
- The installed **phoc/wlroots has no Vulkan renderer** (only `wlr_renderer_is_gles2` /
  `wlr_renderer_is_pixman`), and its gles2 renderer ties EGL to the same DRM device as GBM — which
  can only ever be `card0` = the display (`msm_drm`/`sde-kms`).

So the GPU must be a DRM device => a kernel with mainline `drm/msm`.

## The SoC is already mainlined — under the name `talos`

SM6150's internal MSM codename is **Talos**, shared with QCS615 (postmarketOS wiki, and the LKML
review thread: "IoT variant is QCS615 and Auto variants use SA6155P; both are functionally the same
except some fuses"). So `arch/arm64/boot/dts/qcom/talos.dtsi` **is** the SM6150 SoC description.

Confirmed present in torvalds/master:

| Piece | Where | Notes |
|---|---|---|
| `gpu@5000000` = `qcom,adreno-612.0` | `talos.dtsi` | with `qcom,gmu`, `adreno_smmu`, `zap-shader`, `gpu_opp_table` (845/745/700/550/435/290 MHz = the **mobile** plan) |
| a612 driver | `adreno/a6xx_catalog.c` | `chip_ids 0x06010200`, `funcs = &a6xx_gmuwrapper_funcs`, `a612_rgmu.bin`, `a612_hwcg` |
| RGMU handling | `adreno/a6xx_gmu.c` | `adreno_has_rgmu()` paths |
| PMIC device trees | `pm6150.dtsi`, `pm6150l.dtsi` | **both of violet's PMICs** |
| PMIC regulators | `qcom-rpmh-regulator.c` | `pm6150_vreg_data`, `pm6150l_vreg_data` |
| PMIC pinctrl | `pinctrl-spmi-gpio.c` | `pm6150`, `pm6150l` |
| Panel driver | `panel-novatek-nt36672a.c` | violet's panel is `nt36672a-shenchao-fhd-video` |
| Touchscreen driver | `novatek-nvt-ts.c` | |
| Clocks / pinctrl / interconnect / SMMU / eMMC / I2C / SPI / UART | `gcc-qcs615.c`, `pinctrl-qcs615.c`, ... | 6.14 |
| DSI | msm dsi + `dsi_phy_14nm.c` | **6.19** |
| Board template | `qcs615-ride.dts` | declares `"qcom,qcs615", "qcom,sm6150"` |

Mainline stable at time of writing: **7.2.10**.

### What is NOT there (this is the actual work)
1. **No violet (or any phone) board DTS.** Only `qcs615-ride.dts` and `talos-evk.dts` (IoT EVKs).
2. **No pmOS packaging for sm6150** — upstream pmaports has no `linux-postmarketos-qcom-sm6150`,
   no `device-samsung-a70q`/`minsk`, and no violet entry. pmOS's violet page says "Mainline: no".
3. A panel desc for the shenchao variant may be missing from `panel-novatek-nt36672a.c`.

## Risk: USB peripheral mode is WIP upstream for talos

`linux-msm.github.io/mainline-status/soc/talos`: USB Host Mode 6.14, **USB Peripheral Mode / OTG WIP**.
USB gadget is how this phone is reached from the laptop (NCM/SSH) *and* how pmOS's initramfs exposes
its log disk. A mainline violet may boot but be unreachable. Plan for an alternative observation
channel before spending flashes (see below). Only QCS615-RIDE is a tested board; the mobile SM6150
variant is untested upstream (LKML confirms the mobile GPU plan differs from the IoT plan).

## Observation channel for boot testing (must solve first)

The panel is the fallback, but the primary instrument should be **pstore/ramoops**: violet's DT
reserves `ramoops@a1600000` (`0x800000`, `console-size 0x400000`, `pmsg-size 0x400000`). A mainline
panic/console written there survives in RAM. Sequence:
1. flash mainline boot.img (no button press needed — see recovery), boot it, let it fail/hang;
2. reboot to fastboot, flash the **downstream r9** pair back;
3. read `/sys/fs/pstore/console-ramoops-0` on the working system.

So the mainline DTS must keep the `ramoops` node and enable `CONFIG_PSTORE_RAM` (+ console on
ramoops) — that is the debugging loop, and it is worth designing in from the start.

## Reference data gathered (in `~/violet-mainline/dt/ref/`)

Pulled from the LineageOS tree the working build actually uses
(`LineageOS/android_kernel_xiaomi_sm6150@26ed1e46`), because the local `~/violet-pmos/kernel`
checkout (MiCode branch `violet-q-oss`) has **no violet DT files at all**, only the defconfigs.

- `violet-sm6150.dtsi` — board skeleton; `sdhc_2 cd-gpios = <&tlmm 99 0>`; wdog bark-time 15000
- `violet-sm6150-memory.dtsi` — **the reserved-memory map** (see below)
- `violet-sm6150-pinctrl.dtsi` — gpio101 (output-low/high), gpio93 (pull-down), MI2S on 108-111,
  camera 47/94/98
- `violet-sm6150-display.dtsi` + `dsi-panel-nt36672a-shenchao-fhd-video.dtsi` —
  **te-gpio = tlmm 90, reset-gpio = tlmm 91**, `bl_ctrl_wled`, bl-max 4095, video mode
- `violet-sm6150-usb.dtsi` — `usb0`/`dwc3@a600000` with `qusb_phy0` + `usb_nop_phy`,
  `maximum-speed = "high-speed"`, QUSB init seq, `qusb_phy0` regs `0x88e2000` + tcsr `0x01fcb250`;
  `usb_qmp_phy` disabled
- `violet-sm6150-regulator.dtsi` — `&L7C` always-on HPM
- `violet-sm6150-pm6150.dtsi` — power-on keys: `s1-timer 6720`, `s2-timer 2000`, `s2-type 7`
- `violet-sm6150-pm6150l.dtsi` — lcdb/wled/flash settings
- `violet-sm6150-touchscreen.dtsi` — novatek + ft8719
- `xiaomi/pm6150.dtsi`, `xiaomi/pm6150l.dtsi` — Xiaomi's PMIC overlays

### Reserved memory (violet's OWN addresses — do NOT copy the EVK's)
```
seecom/smcinvoke  0x86d00000 +0x2200000      pil_adsp_mem   0x95300000 +0x1e00000
pil_modem_mem     0x8b000000 +0x7e00000      pil_ipa_fw_mem 0x97100000 +0x10000
pil_video_mem     0x92e00000 +0x500000       pil_ipa_gsi_mem 0x97110000 +0x5000
wlan_msa_mem      0x93300000 +0x200000       pil_gpu_mem    0x97115000 +0x2000
pil_cdsp_mem      0x93500000 +0x1e00000      ramoops        0xa1600000 +0x800000
```
Note: mainline's `talos.dtsi` places `pil_gpu_mem` at **0x97715000**; violet's is **0x97115000**.
The violet DTS must override with violet's addresses or the GPU/zap region will be wrong.

## The port

Two new packages, in a dedicated pmaports tree so the working downstream port is untouched
(build with `pmbootstrap --aports ~/violet-mainline/pmaports`):

1. `device/testing/linux-postmarketos-qcom-sm6150`
   - source: mainline tarball (7.2.x) + `config-postmarketos-qcom-sm6150.aarch64` + the violet DTS
   - `prepare()`: copy the violet DTS into `arch/arm64/boot/dts/qcom/` and add it to the Makefile
     (same pattern as the downstream APKBUILD's `dtb-$(CONFIG_MACH_XIAOMI_VIOLET) += ...`)
   - defconfig seeded from the sm7150 mainline config with `CONFIG_LOCALVERSION="-sm6150"`, then
     iterated with `pmbootstrap kconfig edit`; must have `CONFIG_DRM_MSM`, `CONFIG_QCOM_IOMMU`,
     `CONFIG_PSTORE_RAM`, `CONFIG_DRM_PANEL_NOVATEK_NT36672A`, `CONFIG_TOUCHSCREEN_NOVATEK_NVT_TS`
2. `device/testing/device-xiaomi-violet`
   - only `linux-xiaomi-violet` -> `linux-postmarketos-qcom-sm6150`; drop `90-violet-pixman.sh`
     (the GPU is the point), the KGSL firmware files and `patch 0005`
   - **reuse the existing `deviceinfo` verbatim** — the flash geometry is already correct:
     `flash_method=fastboot`, `pagesize=4096`, `header_version=2`, `base=0x0`, `kernel=0x8000`,
     `ramdisk=0x01000000`, `tags=0x100`, `dtb=0x01f00000`, `initfs_compression=gzip`
   - `deviceinfo_dtb="qcom/violet-sm6150"` (same DTB name the working build produces)
   - start with a plain `rndis.usb0`/NCM gadget assumption, but treat USB as unproven

### `violet-sm6150.dts` skeleton (first cut)
```
/dts-v1/;
#include <dt-bindings/...>
#include "talos.dtsi"            // the SM6150 SoC
#include "pm6150.dtsi"           // mainline PMIC
#include "pm6150l.dtsi"
/ {
    model = "Xiaomi Redmi Note 7 Pro";
    compatible = "xiaomi,violet", "qcom,sm6150";
    chassis-type = "handset";
    // violet's reserved-memory overrides (incl. ramoops + pil_gpu_mem at 0x97115000)
    // regulators (vrpmh uses pm6150/pm6150l); L7C always-on
    // aliases: mmc0 = &sdhc_1
};
&tlmm { /* gpio90 te, gpio91 panel reset, gpio99 sd-cd, ... */ };
&gpu   { status = "okay"; };            // the A612 -> /dev/dri/renderD128
&mdss  { status = "okay"; };
&dsi0  { vdda-supply, panel@0 = <&panel> ... };
&sdhc_1 { status = "okay"; };            // eMMC
&usb_1 { ... };                          // dwc3, qusb_phy0
```

## Status, progress and dead ends — moved to `docs/`

The progress log used to live here; it is now split so this file stays a design doc:

- **[docs/STATUS.md](docs/STATUS.md)** — what works, what is broken, what is in flight (per subsystem). Keep it current.
- **[docs/PROGRESS.md](docs/PROGRESS.md)** — the dated log, **newest first**. New entries go at the top of that file, not here.
- **[docs/RULED-OUT.md](docs/RULED-OUT.md)** — dead ends ("do not re-test") and hard-won lessons/rules.

## Build / test loop

    pmbootstrap --aports ~/violet-mainline/pmaports build linux-postmarketos-qcom-sm6150
    pmbootstrap --aports ~/violet-mainline/pmaports install --no-sshd
    # images land in ~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/
    # flash boot + userdata as a MATCHED PAIR (see `~/violet-pmos/RECOVERY.md`)

Then read the pstore log via the r9 system. Iterate.

## Can we test before flashing? Yes — but NOT with QEMU (verified)

**QEMU cannot emulate this device.** Checked against QEMU's own machine lists: `hw/arm/Kconfig` has
**no** qcom/msm/snapdragon machine, and `hw/display/` has **no** Adreno/msm/KGSL model. The installed
`qemu-system-aarch64` offers 111 machines, **0** of them Qualcomm (`virt`, `sbsa-ref`, RPi, i.MX,
Zynq, Tegra...). A violet DTB describes SPMI PMICs, RPMH, GPUCC, an Adreno 612, a DSI panel and a
QUSB PHY — none of which QEMU models, so a QEMU run would exercise none of the risk. The one
legitimate QEMU use is a **`virt` control boot of the same kernel binary+config**: it proves the
kernel itself is sound, so a phone failure points at the DTS/hardware rather than the kernel.

### The real pre-flash ladder (set up and PROVEN)
Local tooling is installed: `bc`, `dtc`, `dt-validate` (dtschema 2026.9, via `uv tool install
dtschema` — not in the Arch repos), `qemu-system-aarch64`, and mainline **7.2.10** extracted at
`~/violet-mainline/kernel/linux-7.2.10`.

    export PATH="$HOME/.local/bin:$PATH"
    cd ~/violet-mainline/kernel/linux-7.2.10
    make ARCH=arm64 LLVM=1 defconfig                 # once
    make ARCH=arm64 LLVM=1 qcom/violet-sm6150.dtb    # 2.3 s  <- the iteration loop
    dt-validate -m -p Documentation/devicetree/bindings arch/arm64/boot/dts/qcom/violet-sm6150.dtb

Proven baseline: `qcom/qcs615-ride.dtb` builds in **2.353 s** and `dt-validate` returns **rc=0**.
`dt-validate` is the closest thing to a compiler for hardware descriptions — it checks the DTS
against mainline's own YAML bindings (missing required properties, wrong `reg` order/size, wrong
`compatible`, missing `#*-cells`, undocumented props). That catches the class of bug that otherwise
costs a flash, and it needs no phone.

Order of work: `dtc` compile -> `dt-validate` -> kernel build -> diff against the known-booting
`talos-evk.dts`/`qcs615-ride.dts` -> (optional) QEMU `virt` control boot -> only then the phone.

## Mainline idioms confirmed (so the DTS is written against reality)

- Remoteproc/reserved memory: plain `reserved-memory` node (unlabelled — address it as
  `&{/reserved-memory}`), `pil_gpu_mem: pil-gpu@97715000` is `no-map`.
- GPU: `gpu: gpu@5000000` ships `status = "disabled"` -> the board does `&gpu { status = "okay"; }`.
  Its `gpu_zap_shader` already points at `&pil_gpu_mem`.
- **RPMH regulators live under `&apps_rsc`, not `&spmi_bus`**:
      &apps_rsc {
              regulators-0 { compatible = "qcom,pm6150-rpmh-regulators";  qcom,pmic-id = "a"; ... };
              regulators-1 { compatible = "qcom,pm6150l-rpmh-regulators"; qcom,pmic-id = "e"; ... };
      };
  Child node names must be the vreg resource names (`smps1`..`smps5`, `ldo1`..`ldo19`), matching
  `RPMH_VREG("ldo1", ...)` in `qcom-rpmh-regulator.c`. Templates: `sc7180-acer-aspire1.dts` (pm6150)
  and `sm6350-sony-xperia-lena-pdx213.dts` (pm6150l) — both mainline boards that actually boot.
- DSI ctrl label is **`mdss_dsi0`** (`dsi@ae94000`, `qcom,sm6150-dsi-ctrl`) — not `dsi0`.
- Storage `sdhc_1: mmc@7c4000` = `qcom,qcs615-sdhci`; USB `usb_1: usb@a600000` = `qcom,qcs615-dwc3`.

## NEW gap found: violet's panel is not supported by mainline yet

`panel-novatek-nt36672a.c` matches exactly one panel: **`tianma,fhd-video`**. Violet's panel is the
**shenchao** variant, so a `shenchao,fhd-video` desc (init sequence, timings, DSI params) must be
added to that driver. The data is on hand in
`~/violet-mainline/dt/ref/dsi-panel-nt36672a-shenchao-fhd-video.dtsi` (309 lines). Also: **no
mainline board wires a DSI panel on `sm6150-dsi-ctrl` yet**, so the DSI wiring has to be modelled on
another msm phone board's DSI nodes.

## Still to gather
- Violet's **vendor regulator values** for the pm6150/pm6150l rails (the board's own
  `violet-sm6150-regulator.dtsi` only overrides `&L7C`; the rest come from the vendor tree's
  `sm6150-regulator.dtsi`). Needed before the regulators are right — fetch it next.


## Do not break: the recovery path (see `~/violet-pmos/RECOVERY.md`)

- working pmOS pair: `images-r9/boot-r9.img` + `images-r9/rootfs-r9.img` (UUIDs verified against the
  phone's cmdline)
- raw partitions as flashed: `device-backup/boot-p76.img`, `device-backup/dtbo-p60.img`
- Android: `~/Downloads/Android/ROMs/ProjectElixir_5.7_*.zip` + TWRP
- no button presses needed: reboot into fastboot over SSH with the `reboot(2)` syscall
