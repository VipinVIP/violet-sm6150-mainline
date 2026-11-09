# Camera bring-up — violet (SM6150), plan 2026-11-03

Status at start: **no camera stack at all**. `/dev/media*` and `/dev/video*` do not exist on the phone,
dmesg has zero `camss`/`cci` lines, and the DT has no enabled camera node. Recorded from the live phone
(2026-11-03 13:2x, build running 7.2.10-sm6150).

## What already exists in this tree (7.2.10) — verified by reading the sources

| Piece | Where | State |
|---|---|---|
| CAMSS SM6150 support | `drivers/media/platform/qcom/camss/camss.c` (`csiphy_res_sm6150`, `csid_res_sm6150`, `vfe_res_sm6150`, `icc_res_sm6150`, `sm6150_resources`) | **merged**; upstream series "media: qcom: camss: add sm6150 camss support", Wenmeng Liu (Qualcomm), v4 2026-01-12, tested on Talos EVK (lwn.net/Articles/1053829, spinics msg5997336) |
| CAMSS binding | `Documentation/devicetree/bindings/media/qcom,sm6150-camss.yaml` | present, with a full example |
| SoC nodes | `arch/arm64/boot/dts/qcom/talos.dtsi`: `cci@ac4a000`, `isp@acb3000`, `camcc@ad00000` (`qcom,qcs615-camcc`) | **present, `status = "disabled"`** — this is the whole reason nothing loads |
| Board example | `talos-evk-camera-imx577.dtso` | reference wiring: csiphy1 + cci_i2c1 + imx577 |
| Sensor driver | `drivers/media/i2c/imx412.c` claims `sony,imx577` | works for the EVK sensor; **no IMX586 driver exists anywhere in the tree** |
| Kernel config | `QCS_CAMCC_615=y`, `VIDEO_QCOM_CAMSS=m`, `I2C_QCOM_CCI=m` | already correct |

So the SM6150 camera *controller* side is not the project — it is merged and tested on the sister board.
The work is board wiring + a sensor driver.

## violet hardware (vendor dtbo `dtbo-entry-0.dtbo` + vendor HAL libs in `vendor.img`)

| Camera | Sensor | CSIPHY | CCI master | MCLK | Reset | Rails (vendor) |
|---|---|---|---|---|---|---|
| Rear main | **Sony IMX586 48 MP** (`com.qti.sensor.imx586.so` in `/lib64/camera`) | 0 | 0 | mclk0 (GPIO 28) | GPIO 47 (0x2f) | `cam_vio` = pm6150_l13, `cam_vana` = `camera_vana0_ldo`, `cam_vdig` = `camera_ldo`, `cam_clk` = `titan_top_gdsc` |
| Rear aux | S5K5E9YU05 5 MP | 1 | 0 | mclk1 (GPIO 29) | GPIO 45 (0x2d) | `camera_vana1_2_ldo`, `camera_ldo` |
| Front | 13 MP (verify in HAL) | 2 | 1 | mclk2 (GPIO 30) | GPIO 37 (0x25) | `camera_vana1_2_ldo`, `camera_ldo` |

The `camera_ldo` / `camera_vana*_ldo` are **gpio-regulators** in the vendor dtbo; their GPIO numbers must be
copied into our DT (they are the camera power switches, and the porting guide's #1 touch/camera trap is that
the rail is off and the chip never answers).

## Open unknowns (resolve before writing the sensor driver)

1. **CSIPHY 1.2 V / 1.8 V rails on violet.** The EVK overlay uses `vreg_l11a` / `vreg_l12a`; violet's
   `l11a`/`l12a` are both 1.8 V rails, so the vendor wiring is probably different. Check the vendor base DTB
   (inside `boot-r10.img` / the stock `boot.img`), not the overlay.
2. GPIO numbers for `camera_ldo` / `camera_vana0_ldo` / `camera_vana1_2_ldo` (vendor dtbo has them in
   `gpio-regulator@0..2`).
3. Whether `camera_region@8ab00000` (5 MiB, `removed-dma-pool`, no-map) is needed by camss on this platform
   — probably not for RDI capture, but confirm before enabling.

## Milestones

**M0 — camss + cci probe (no sensor, no driver).** New `violet-sm6150-camera.dtsi`: enable `&camss` with
`status = "okay"`, the two CSIPHY supplies, `&cci` okay, and the CCI i2c buses. Build, flash `boot`, then:
`ls /dev/media*`, `dmesg | grep -i camss`, `media-ctl -p`, and `ls /sys/bus/i2c/devices` for the CCI adapters.
Risk: camcc GDSC/power-domain bring-up can hang the boot (this is exactly what happened with dispcc, patches
0024/0025) — keep `boot-mainline-186-rollback.img` ready.

**M0.5 — sensor answers on CCI.** With rails + MCLK on, read the IMX586 chip ID (register 0x0016/0x0017,
expect 0x0586) over the CCI bus from userspace. This validates power, MCLK and CCI timing **without writing
any driver**. This is the cheapest possible "is the hardware alive" test and should be done before the driver.

**M1 — IMX586 driver.** Minimal single-mode V4L2 subdev, modelled on `imx412.c` (same Sony register style,
and it is the closest merged driver), with a 4-lane 10-bit mode at 4056x3040 or the binned 2028x1520.
Register tables are the work: the vendor HAL `.so` is not usable, so derive from the sensor's public
datasheet snippets / other open projects, and verify by capture.

**M2 — capture path.** `camss` RDI node + `v4l2-ctl`/`libcamera` (simple pipeline) capture to a file on the
phone; confirm a real image, not a green/garbage frame.

**M3 — userspace.** PipeWire/libcamera wiring and one app (GNOME Camera / megapixels) showing a live preview.

## Rules for this work (from the repo's standing rules)

- One change per boot; every claim from a command output; update `docs/PROGRESS.md` + `docs/STATUS.md` +
  `patches/README.md` as things land.
- Search upstream first for each piece (done for M0: the SM6150 series is merged).
- Verify user-style at M3 (open the app, see the picture).
- Never flash `dtbo-vendor.img`; recovery image is `~violet-pmos/images-r9/boot-r10.img`.

## M0 result (2026-11-03 13:43)

Done and verified on the phone: `/dev/media0`, `msm_vfe0_video{0,1,2}`, `msm_vfe1_video{0,1}`,
camcc registered and feeding `isp@acb3000`/`cci@ac4a000`, CCI buses as i2c-2/3. Boot is clean; the image is
`boot-mainline-cam.img`. Camera rails confirmed as PM6150L GPIO 3/9/4 (not TLMM).

## M0.5 result (2026-11-03 14:20) — buses characterised, sensor silent

- CCI master 1 (i2c-3): VCM/actuator at 0x0c, EEPROM at 0x50/0x51. **Alive.**
- CCI master 0 (i2c-2): silent at every address — this is where the current sensor node sits.
- IMX586 at 0x1a: no ACK on either master, either reset polarity.
- Rails report enabled but the PM6150L gpio3/gpio9 pads read "out low", so rail switching is the prime suspect.
- Vendor dtbo puts the rear eeprom on `cci-master = <1>` and the sensor on `<0>` — matches the measurement.

### Revised next steps

1. **Prove rail switching**: add `camtest-gpios = <&pm6150l_gpios 3 ...>, <&pm6150l_gpios 9 ...>` to the sensor node,
   request them in a module, drive high, read back, and check `/sys/kernel/debug/gpio`. If they do not switch,
   find the real enable (vendor `pinctrl-0` state, or TLMM 94/98 `CAM_DVDD1_2V`/`CAM_AVDD1_8V`).
2. **Settle the CCI master**: move the sensor node to `cci_i2c1` (the live bus) and re-read 0x1a; if the rear
   module is the one on master 1, the sensor should appear once its rails are really on.
3. Only then M1: the IMX586 driver (start from the vendor-side mode tables or the public `imx586-v4l2-driver`
   projects found upstream; `imx412.c` is only a probe harness).

### Operational cost note

Two of the four reboots in this session froze on shutdown (the known open issue in STATUS.md), each needing a
15 s power-button hold. Camera iterations must be batched per boot; prefer insmod tests over flashes.

## M0.5 DONE (2026-11-03 14:35)

IMX586 identified: **ID 0x0586 at 0x1a on CCI bus 1** (`cci_i2c1`), once (a) the node was moved off the dead
master 0, (b) a third rail (PM6150L gpio 4, `camera_vana1_2_ldo`) was enabled, and (c) the sequence
reset-assert -> rails -> MCLK -> reset-release -> 20 ms was used. Reset polarity ACTIVE_LOW confirmed
(asserted = NACK, released = ACK).

### M1 recipe (what the real driver must do)

1. assert reset, 2. enable avdd/dovdd/dvdd (+ the gpio4 rail) ~1 ms apart, 3. enable MCLK 24 MHz,
4. release reset, 5. 20 ms settle, 6. read ID 0x0016 == 0x0586, 7. one 4-lane 10-bit mode, controls,
   v4l2 async registration, then M2 capture.

## M1 DONE (2026-11-03 14:45)

`drivers/media/i2c/imx586.c` probes and prints `IMX586 detected (id 0586)`; subdev at `/dev/v4l-subdev10`.
Requires: XCLR assert -> rails (AVDD, DOVDD, DVDD) -> MCLK -> release -> 20 ms, plus TLMM 94 (vendor
`CAM_DVDD1_2V`) driven high and the gpio4 rail on.

### M2 next

1. Link the graph: `&camss` port@0 endpoint (`data-lanes = <1 2 3 4>`, `remote-endpoint = <&imx586_ep>`) and the
   sensor endpoint's remote back to it; the sensor sits on CSIPHY0 per the vendor dtbo (`csiphy-sd-index = <0>`).
2. Media graph check: all entities link up on `/dev/media0`, then `v4l2-ctl --list-devices` for the RDI node.
3. Capture one frame: `v4l2-ctl -d /dev/videoN --set-fmt-video=width=3856,height=2180,pixelformat=BG10
   --stream-mmap --stream-count=1 --stream-to=frame.raw`, convert with `raw2rgb`/`ffmpeg`.
4. Once frames are sane, M3: libcamera/pipewire + an app.

## M2 status (2026-11-03 15:00) — pipeline linked, no frames

Graph: imx586 -> csiphy0 -> csid0 -> vfe0_rdi0 -> video0 (all SBGGR10 3856x2180, video pBAA).
Driver now writes common+mode init and sets 0x3000=0x00 (read back). VFE IRQ count stays 0 -> no CSI data.

Next experiments, cheapest first:
1. Try the 1080p binned table (1928x1090) — if frames appear, the 4K datarate/PLL is the problem.
2. Read sensor status registers during streaming (0x3000, 0x3028/0x302C timing, 0x3033 PLL lock if present).
3. Check CSIPHY programming (`HW Version = 0`), and try 2-lane vs 4-lane.

## M2 status (2026-11-03 15:15) — no CSI activity

Sensor configured + streaming (0x3000=0x00), but csiphy/csid/vfe IRQ counts stay flat during capture →
the sensor is not transmitting. CSIPHY1 tried (vendor index off-by-one), same result.

Gotcha: `make qcom/violet-sm6150.dtb` does NOT rebuild when only the included .dtsi changed — `touch` the .dts
first and check the DTB mtime before flashing.

Next: vendor-derived init table (Xiaomi kernel source), lane permutations, CSIPHY register dump while streaming.

## M2 blocker (2026-11-03 15:20)

Sensor configured + streaming, but zero CSI activity on csiphy/csid/vfe. Tried: csiphy0, csiphy1, 4 lanes,
2 lanes. Next sources for the real init sequence:
1. Xiaomi's published violet kernel source (camera DTS: CSI PHY index, lane count).
2. Ghidra the `camera.qcom.so` imx586 init function to lift the register array (module = Ofilm IMX586).
3. Cross-check the Nvidia/i.MX8 IMX586 driver tables.

## Direction review (2026-11-03 17:40) — the open question to settle first

External review of the symptoms raised a likely error in this plan's own assumption: **the IMX586 may not use
the 0x3000 register block** that the public Raspberry-Pi table writes. Supporting evidence:

- chip ID reads `0x0586` at **0x0016** (SMIA-style ID register; both maps coexist on Sony parts, so this alone
  is not proof);
- the vendor's own CCI writes observed through kprobes showed small register addresses (`0x0112`-like);
- `0x3014`/`0x3040` reading back fixed values may mean those are not the registers we assume, so the
  "2-lane strap" conclusion is doubtful.

**Next test (cheap, decisive):** on mainline, read the SMIA frame counter (`0x0005`) before and after writing
`0x0100 = 0x00`. If it does not increment, the sensor never streamed and the init table/map is the problem —
not the CSI link. Then check `0x0114` (lane count) and `0x0136/0x0137` (EXTCLK divisor, must match the 24 MHz
MCLK we run) against what the vendor sets.

Also do not wipe the Android oracle again for this: the vendor PHY dump, the HAL memory dump and the CAMX
logs are already on the laptop in `~/violet-ios/cam/`.
