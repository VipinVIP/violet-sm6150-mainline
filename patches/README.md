# Patches against vanilla Linux 7.2.10

No git tree: patches were saved by hand. `violet-vbat.c` is a new file, the others are diffs. Status as of 2026-10-27.

| Patch | What | Status |
|---|---|---|
| 0001 | Add `violet-sm6150.dts` | The DTS has moved on a lot; use `dt/violet-sm6150.dts.20261102` (panel0 label + touchscreen panel phandle added) |
| 0002 | tzmem: no SHM bridge on sm6150 | needed |
| 0003 | icc qcs615: ACV enable mask | needed |
| 0004 | adreno: A612 RGMU bring-up | needed (GPU works) |
| 0005 | spmi-pmic-arb: ack/disable stale IRQs | **REMOVED 2026-11-02** (kexec-only; 0 hits on normal boots; #186/#187 boot fine without it; copy in `proposed/`) |
| 0006 / 0009 | NT36672A shenchao panel + binding | needed; TODO fold into nt36672a.c |
| 0007 | dispcc-qcs615 GDSC/XO fix | needed (see note below about the 288 MHz table) |
| 0008 | dsi phy 14nm vcca rename | needed |
| 0010 | ath10k: skip quiet mode on WCN3990 | needed; same patch is on the ath10k list (2026-03), not merged |
| 0011 / 0013 | pd-mapper one entry per domain, rpmhpd mss | needed for ADSP/modem |
| 0012 | glink early intents + intent-req reuse | early intents needed; **`tx_with_rcid` is dead code on #183 and `violet_intent_req_reuse` is an experiment knob** (cleanup pending) |
| 0014 | ath10k station experiments | **SUPERSEDED by 0015** |
| 0015 | ath10k WCN3990: create the BSS peer before the station vdev start | right idea, **shipped with experiment knobs** (`violet_*` params, retries, hexdump): must be minimised before it counts as a fix |
| 0016 | ASoC qdsp6 vendor-parity (POPP/COPP topology, ADM endpoint_id_2, AFE island config, HW vote result) | **minimised 2026-11-02**: all `violet_*`/`clk_mode` module params removed, defaults are constants, sm8250.c and q6afe-dai.c pristine. #186 audio card + mic/speaker OK |
| 0017 | arm-smmu-qcom: reserve hyp-owned context banks 10-12 on qcs615 | **real audio fix** (hardcoded to qcs615-smmu-500) |
| 0018 | tas2781: ROM-mode power without RCA firmware | workaround: no calibration, no speaker protection |
| 0024 | dispcc-qcs615: MDSS_CORE reset map + `CLK_OPS_PARENT_ENABLE` on pclk0 | **real D1 fix** (matches upstream sm7150/sm6115/sdm845); upstreamable |
| 0025 | talos.dtsi: `resets = <&dispcc DISP_CC_MDSS_CORE_BCR>` on mdss | **real D1 fix**, pair of 0024; upstreamable |
| 0026 | a6xx RGMU suspend in downstream order | **OBSOLETE since #181**: it patched the local RGMU port, which was removed; mainline's own A612 path works (see debug-backup/a6xx_gpu.c.local-rgmu-port) |
| 0027 | a6xx RGMU fault recovery on resume | **OBSOLETE since #181** (same reason as 0026) |
| 0028 | msm_gpu_submit(): check runtime resume, fail the job instead of unclocked register writes | G1 robustness; upstream bug, upstreamable |
| 0029 | pinctrl lpass-lpi: `LPI_FLAG_CHECKED_CLOCKS` + new SM6150 variant (AP-owned pads at 0x62b52000) | **real mic fix** (SSC pads stalled the AP) |
| 0030 | q6afe-clocks: defer until the AFE answers a probe request (v2; q6core-ready alone was not enough) | **real fix** for the boot race (no sound card on ~1 in 2 boots) |
| 0031 | wcd937x: `gpiod_set_value_cansleep()` for reset | real fix, upstreamable |
| 0032 | violet DT: LPI node, SWRM v1.5.1, WCD937x default-only reset pinctrl, capture link, PDR, BOB AUTO | **mic works** (needs `CONFIG_QCOM_PD_MAPPER=y`, `CONFIG_PINCTRL_SM6150_LPASS_LPI=m`) |
| 0033 | drm/msm: remove DSIDBG/D1 diagnostics, DPU core clock dynamic again | cleanup; display verified on #180 |
| 0040 | novatek-nvt-ts: panel follower (init when the panel is prepared) + DT `panel = <&panel0>` on the touchscreen node | replaces the 30 s polling hack; touch detected at 5.96 s on #187. Touch confirmed by the user on #187. |
| 0039 | dwc3-qcom: re-select the UTMI clock in `dwc3_qcom_pm_resume()` | **real fix** for the post-resume `failed to enable ep0out` (USB dead until rebind). `QSCRATCH_GENERAL_CFG` was 0x0d before suspend and 0x04 after (UTMI clock select + PHYSTATUS_SW lost); dwc3 trace: ep0out `Set Endpoint Configuration` timed out. Verified on #185: register back to 0x0d, UDC `configured`, no rebind. Replaces `violet-udc-repair` (removed). Upstreamable. |
| 0038 | net/qrtr/smd.c: queue packets that arrive before probe completes and replay them | **real fix** for the modem's first-start `fatal error without message` at 40 s (the modem's single QRTR HELLO was dropped in the callback-before-drvdata window). Verified on #184: early path fired, modem registered 55 services, WiFi up in 5 s. Module only (`qrtr-smd.ko`), copy to `/lib/modules/.../net/qrtr/` + `depmod`. |
| 0034 | q6dsp-lpass-clocks: `dev_set_drvdata()` before registering clocks | **real fix** for the NULL deref after an ADSP restart (s2idle resume crash); upstreamable |
| `qg/violet-qg.c` (+ `qg/gen_profiles.py`, generated `qg/violet-qg-profiles.h`) | battery gauge + charger policy + `usb` supply for pm6150 (replaces `violet-vbat.c`) | working, see `docs/PROGRESS.md` 2026-11-04/05; module `violet_qg`, autoloaded via the `xiaomi,violet-vbat` compatible. `violet-vbat.c` is superseded (kept for history) |
| `qg/0001-iio-adc5-add-bat_therm_100k_pu.patch` | adds the missing `bat_therm` entry to `qcom-spmi-adc5` (module only) | real fix; installed on the phone, original kept as `.zst.orig` |

## Tree changes that are NOT in any patch file (re-create from this list)

- `drivers/power/supply/Kconfig`: `config BATTERY_VIOLET_VBAT` (tristate, depends on IIO && OF); `Makefile`: `obj-$(CONFIG_BATTERY_VIOLET_VBAT) += violet-vbat.o`.
- Kernel config: see `configs/config-7.2.10-sm6150-2026-10-27` (notably `CONFIG_NVMEM_SPMI_SDAM=y`, `CONFIG_BATTERY_VIOLET_VBAT=m`, ADSP services built in).
- Display debug hacks: removed by 0033 (2026-10-31). Kept, as downstream parity: DMA_FIFO_CTRL, BLOCK_DMA_WITHIN_FRAME clear, PHY_RESET bit 24, video-enable split, 14nm PHY ICP/LDO values.
- `drivers/clk/qcom/dispcc-qcs615.c`: MDP clock table only has 192/288 MHz while the DT OPPs say 192/256/307.2 MHz (Hermes finding; harmless so far).
- Touch driver `novatek-nvt-ts.c` delayed-work init (local hack).

- `0035-userspace-elogind-sleep-hook-hexagonrpcd-udc.sh`: not a kernel patch; install as `/etc/elogind/system-sleep/no-hexagonrpcd-on-suspend.sh` (mode 755). Stops hexagonrpcd and unbinds the USB gadget UDC around suspend.

- `0036-userspace-suspend-resume-adsp-and-udc.sh` — userspace (not a kernel patch): elogind sleep hook
  that stops hexagonrpcd around sleep (ADSP crash on resume, same as pmaports MR 5400) and unbinds the UDC when nothing is attached (dwc3 suspend returns -EAGAIN). The `violet-udc-repair` service and the dwc3-qcom rebind loop were REMOVED 2026-11-02 (kernel fix `0039`). Verified on build #183: USB comes back in ~7 s, no reboot (closed loops measured 2026-11-02 15:01 and 15:11).

- `0037-userspace-sleep-inhibitor-is-alsa-playing.conf` — userspace config: enable pmOS's own
  `is-alsa-playing` sleep-inhibitor plugin so audio playback blocks idle suspend (it shipped but was
  not enabled; without it the phone suspended mid-song). Verified with `elogind-inhibit --list` and a
  150 s playback run at a 60 s idle timeout: zero suspends.

## Proposed (not applied to the tree by default)

- `proposed/imx586.c` - new V4L2 driver for the rear IMX586 (M1 of the camera plan). Probes, detects
  `0x0586`, registers a subdev. Does not capture yet; the init table is from the public
  `youjunl/imx586-v4l2-driver` and does not match this Ofilm module.
- `proposed/imx412-camtest-debug.c` - the instrumented imx412 used as a probe harness during bring-up.
  Debug only, never ship.
- `dt/violet-sm6150-camera.dtsi` - the camera DT (camss + cci + IMX586 node) referenced by the main DTS.
