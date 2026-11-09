# Findings: display hang under continuous updates (read-only investigation)

Hermes, 2026-10-27. Nothing on the phone, in the DT, in the kernel or in firmware was changed;
everything below is from source reading + read-only ssh (phone was up on `7.2.10-sm6150`, WiFi
`user@<lan-ip>`, no test triggered).

## Summary (read these 5 lines)

1. **The full blue screen is the DPU's own INTF underrun fill colour.** It is hard-coded blue in
   mainline: `dpu_encoder_phys_vid.c:89` `timing->underflow_clr = 0xff` → written to
   `INTF_UNDERFLOW_COLOR` at `dpu_hw_intf.c:254` (0x0000ff = blue). The vendor panel DT sets the same
   value (`qcom,mdss-dsi-underflow-color = <0xff>`). So the "blue screen" is **not** a lost panel
   sync: the timing engine is alive and streaming the underrun colour because **no pixels arrive**.
2. **Mainline cannot report that underrun.** `dpu_encoder_phys_vid.c:694` registers an underrun
   callback, but `dpu_hw_intf.c` contains **no `INTF_INTR_EN` / `INTF_INTR_STATUS` programming at
   all**, so the INTF underrun interrupt is never unmasked in hardware. This is why every hang is
   silent — it is a missing diagnostic, not a missing event.
3. **The SoC reset is a second, downstream failure.** Sequence consistent with all evidence: MDP
   fetch path starves → permanent underrun (blue) → the next CPU access to the MDSS/VBIF block wedges
   the core (the same "NMI unanswered / bus access never returns" behaviour we already saw when
   reading LPI `/dev/mem`, PROGRESS 2026-10-26 19:45) → APSS watchdog → PS_HOLD. The hang is not in
   the compositor, not in the panel, not in the DSI link.
4. **Top suspect for the starvation: the MDP's bandwidth votes are much smaller than the vendor's
   design point.** Live ICC vote on `mdp0-mem` is **avg 735 298 / peak 800 000 kB/s**, and the peak is
   just `min_dram_ib` (800 000); the vendor DT allows **4 500 000 kB/s per pipe**, keeps an
   **800 000 kB/s LLCC floor** (mainline: none), and models `dram-channels = 2`. The QoS programming
   itself is *not* the difference — I compared it and the VBIF remap tables, memtypes and
   `qos-lut` values are bit-identical to the vendor's (§4). So H1 is about vote *magnitude* and
   fetch head-room, not about wrong QoS knobs.
5. **Two real defects found on the way, both worth fixing independently of the hang:** the DPU's
   clock is stale-debug-pinned (`if (1) /* DSIDBG */` in `dpu_core_perf.c:287`) and the qcs615 dispcc
   cannot generate two of the three MDP OPPs the DPU asks for (`288 MHz` is what you get when you ask
   for `307.2 MHz`), so the CX corner vote and the real MDP clock disagree.

---

## 1. Verified facts (live, this session)

From `/sys/kernel/debug/clk/clk_summary`, `pm_genpd_summary`, `interconnect_summary`,
`dri/0/debug/*`:

| item | value | note |
|---|---|---|
| `disp_cc_pll0` | 576 000 000 | only PLL0 rate available |
| `disp_cc_mdss_mdp_clk_src` / `mdp_clk` | **288 000 000** | not an OPP in the DT (192/256/307.2) |
| `disp_cc_mdss_mdp_lut_clk` | 288 MHz, **disabled** | vendor drives it at 192 MHz |
| `disp_cc_mdss_rot_clk` | 19.2 MHz, disabled | vendor enables it |
| DSI: pclk0 / byte0 / byte0_intf / esc | 183 257 000 / 137 442 750 / 68 721 375 / 19.2 M | sane for 1080×2340@60, 4 lanes |
| `mdss_core_gdsc` | **on**, `ae00000.display-subsystem` active | not a power-collapse problem at idle |
| ICC `mdp0-mem` (llcc_mc/ebi) | avg **735 298**, peak **800 000** kB/s | peak == `min_dram_ib` |
| ICC `cpu-cfg` | avg 0, peak 400 000 kB/s | |
| `debug/core_perf/core_clk_rate` | 288 000 000 | = `max_core_clk_rate`, force-max hack active |
| `perf_mode` / `enable_bw_release` | `mode 0` / `0` | dynamic; bandwidth release **off** (dead end) |
| `min_dram_ib` / `min_core_ib` / `max_core_ab` | 800 000 / 2 400 000 / 4 800 000 | |
| `debug/danger/safe_status` | `MDP: 0x1` (safe asserted), danger `0x0` | at *idle*; must be re-read under load |
| `debug/core_irq` | `IRQ=[0,27] count:961 cb:0x0` | TOP0_INTR 27 = INTF_1 vsync, no callback |

Boot dmesg is clean: `dpu hardware revision:0x50030000` (DPU 5.3 = sm6150 catalog), fb0 up,
no `dpu`, no `arm-smmu`, no `mdss` error lines in 18 min of uptime.

**The machine currently has no lockup detector that could ever see this hang.**
`/proc/sys/kernel/nmi_watchdog = 0` (softlockup on, `watchdog_thresh = 10`). `.config` has
`CONFIG_HARDLOCKUP_DETECTOR=y` + `CONFIG_HARDLOCKUP_DETECTOR_PERF=y` +
`CONFIG_HARDLOCKUP_DETECTOR_COUNTS_HRTIMER=y`, so the detector is compiled in but **off at runtime**.
A core wedged on a bus access cannot run its own softlockup thread, and with the NMI detector disabled
nothing else notices — exactly "softlockup_panic=1 never fires, no message". `COUNTS_HRTIMER=y` means
the detector can flag a CPU that stops taking hrtimer interrupts even if its NMI is not answered, so
`nmi_watchdog=1` (or `=panic`) is a **one-sysctl** upgrade from total silence to a named CPU. This is
the cheapest single improvement available and should be on before any further hang test.

## 2. Why the 288 MHz is not "one of the OPPs" — two stacked defects

**a) A debug hack is still in the tree.** `drivers/gpu/drm/msm/disp/dpu1/dpu_core_perf.c:287`:

```c
static u64 _dpu_core_perf_get_core_clk_rate(struct dpu_kms *kms)
{
	if (1)	/* DSIDBG: force max core clock */
		return kms->perf.max_core_clk_rate;
```

The per-commit clock computation (`_dpu_core_perf_calc_clk`, which is where per-plane/mode clock,
`clk_inefficiency_factor` and the CX OPP vote come from) is bypassed. The DPU never scales.

**b) The qcs615 dispcc cannot produce 256 or 307.2 MHz.**
`drivers/clk/qcom/dispcc-qcs615.c:266`:

```c
static const struct freq_tbl ftbl_disp_cc_mdss_mdp_clk_src[] = {
	F(19200000,  P_BI_TCXO, 1, 0, 0),
	F(192000000, P_DISP_CC_PLL0_OUT_MAIN, 3, 0, 0),
	F(288000000, P_DISP_CC_PLL0_OUT_MAIN, 2, 0, 0),
```

with PLL0 = 576 MHz. `talos.dtsi:4419` nevertheless advertises
`opp-192000000 / opp-256000000 / opp-307200000` with `required-opps` `low_svs/svs/nom` on
`RPMHPD_CX`. Asking for 307.2 MHz rounds down to 288 MHz, so:

* the DPU runs **6.25 % below the OPP it believes it has**;
* the CX corner (`nom`) is voted for a rate the clock cannot reach.

Compare the vendor `drivers/clk/qcom/dispcc-sm6150.c:339`: `19.2 / 192 / 256 / 307 MHz`, all
`P_DISP_CC_PLL0_OUT_MAIN`, `enable_safe_config = true`, plain `clk_rcg2_ops`, and a CX `vdd_class`
with `rate_max` 192/256/307 per corner. Mainline uses `clk_rcg2_shared_ops` instead.

Upstream status (checked, nothing newer than 7.2.10 fixes it): the driver was added 2025-07-16 by
Taniya Das, commit `9b47105f5434707eab065f65e7d35c62a51179f8`; the only later commits are
constify cleanups (`87df31ea43eef5f6b9e7be0fa2555e58a9455e05`, `573ddd0d22aa06f72ea7d4152d65c8bcb0eca24e`,
`995832b2cebe6969d1b42635db698803ee31294d`).
Source: <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/log/drivers/clk/qcom/dispcc-qcs615.c>

Note the vendor ran the MDP at **256 MHz** for normal content and only 307 MHz under load, so 288 is
not absurd per se — what differs is that the vendor scales *clock and bandwidth together per corner*
while mainline is pinned at 288 and votes a flat 800 MB/s peak.

## 3. Why the blue screen happens at all (the DPU has no underrun detector)

* `dpu_encoder_phys_vid.c:89`: `timing->underflow_clr = 0xff;` — this is the colour the INTF emits
  for every pixel it cannot get from the MDP.
* `dpu_hw_intf.c:254`: `DPU_REG_WRITE(c, INTF_UNDERFLOW_COLOR, p->underflow_clr);` — programmed on
  every `setup_timing_gen`.
* `grep -n "IRQ_EN\|intr_underrun\|UNDERRUN" dpu_hw_intf.c` → **no hits**. The sm6150 catalog does
  declare `intr_underrun = DPU_IRQ_IDX(MDP_SSPP_TOP0_INTR, 26)` (`catalog/dpu_5_3_sm6150.h:181`) and
  `dpu_encoder_phys_vid.c:694` registers a callback for it, but nothing ever sets the INTF's
  interrupt-enable bit, so the source stays masked. Hence: underrun → blue screen, **zero dmesg**.
* The vendor panel DT (`dt/ref/dsi-panel-nt36672a-shenchao-fhd-video.dtsi:29`) sets
  `qcom,mdss-dsi-underflow-color = <0xff>` — identical, so "blue" is expected behaviour on this panel
  from either kernel.

**Consequence for the test loop:** the panel turning blue is a *reliable, early* signal that the MDP
fetch path has stalled, seconds before the SoC dies. That is a much better hook than dmesg.

## 4. Vendor (working, r10) vs mainline (hangs) — display differences that can matter under load

Offsets line up: vendor `qcom,sde-off = <0x1000>` means vendor `intf-off = <0x6b000 …>` is mainline
`0x6a000` (`sm6150_intf[]`), mixer `0x45000`→`0x44000`, pp `0x71000`→`0x70000`, sspp `0x5000`→`0x4000`.
So the *layout* is fine; the **performance/QoS** side is what was dropped.

| # | Vendor (`~/violet-pmos/kernel/arch/arm64/boot/dts/qcom/sm6150-sde.dtsi`, `drivers/gpu/drm/msm/sde/`, `dispcc-sm6150.c`) | Mainline (`talos.dtsi`, `catalog/dpu_5_3_sm6150.h`) | Relevance |
|---|---|---|---|
| 1 | `qcom,sde-max-per-pipe-bw-kbps = <4500000>` (×5) | peak vote on the wire = 800 000 kB/s (= `min_dram_ib`) | **high** — 5.6× less burst head-room for the MDP's AXI reads |
| 2 | `qcom,sde-panic-per-pipe` (feature bit `SDE_MDP_PANIC_PER_PIPE`) | not represented | **low-medium** — only matters once the screen is split across two LMs; we drive one pipe, so likely irrelevant |
| 3 | `qcom,sde-vbif-qos-rt-remap = <3 3 4 4 5 5 6 6>`, `qos-nrt-remap = <3 3 3 3 3 3 3 3>` | `sdm845_rt_pri_lvl = {3,3,4,4,5,5,6,6}`, `sdm845_nrt_pri_lvl = {3,3,3,3,3,3,3,3}` (`dpu_hw_catalog.c:519`) | **none — identical.** Earlier suspicion withdrawn; do not chase |
| 4 | `qcom,sde-qos-cpu-mask = <0x3>`, `qos-cpu-dma-latency = <300>` | absent | **none — dead in the vendor tree too.** Those properties appear nowhere in `sde/*.c`; no register write consumes them |
| 5 | `qcom,sde-min-llcc-ib-kbps = <800000>` | `.min_llcc_ib = 0` | medium — no LLCC (system-cache) instantaneous-bandwidth floor |
| 6 | `qcom,sde-dram-channels = <2>`, `num-nrt-paths = <0>` | not represented | medium (bw math) |
| 7 | danger LUT 5 entries `0xf 0xffff 0x0 0x0 0xffff`; safe linear `0xfff8`, macrotile `0xf000`, nrt `0xffff`, cwb `0xffff` | `{0xf, 0xffff, 0x0}` / `{0xfff8, 0xf000, 0xffff}`, macrotile-qseed reuses macrotile (`TODO` at `dpu_5_3_sm6150.h:214`) | **low** — the only delta is macrotile-qseed: vendor `0x0`, mainline `0xffff` = mainline panics *earlier*, i.e. more conservative, so not a hang cause |
| 8 | `qos-lut-linear = <0 0x00112222 0x22223357>`, `macrotile = <0 0x00112233 0x44556677>`, `nrt = <0 0x0 0x0>` | `sm8150_qos_linear = 0x0011222222223357`, `sc7180_qos_macrotile = 0x0011223344556677`, `sc7180_qos_nrt = 0x0` | **none — identical bit-for-bit.** Do not chase |
| 9 | MDP clk 256 MHz nominal / 307 max, plus `mdp_lut_clk` 192 M and `rot_clk` | 288 pinned; lut/rot clocks never touched | medium (see §2) |
| 10 | `qcom,sde-highest-bank-bit = <0x1>`, `ubwc-version 0x200`, `has-cdp`, `qcom,sde-secure-sid-mask` | `highest_bank_bit` from mdss compatible; CDP via `cdp_cfg` | medium — UBWC fetch pattern; worth verifying the bank bit actually lands in `MDSS_UBWC_STATIC` |
| 11 | panel: `burst_mode`, `force-clock-lane-hs`, `tx-eot-append`, `bllp(-eof)-power-mode`, `lp11-init`, `h-sync-pulse 0`, `rgb_swap_rgb`, underflow `0xff`, border `0` | panel desc `MIPI_DSI_MODE_VIDEO \| VIDEO_BURST \| LPM`, RGB888 (no `CLOCK_NON_CONTINUOUS` ⇒ HS clock lane, matches) | **low** — DSI link config matches the vendor; DSI is not the prime suspect |
| 12 | timings 1080×2340, hfp 90 / hbp 120 / hpw 2, vbp 8 / vfp 13 / vpw 3, 60 fps | same panel driver variant | low |
| 13 | `mdss_mdp` `clock-rate`/`clock-max-rate` + `qcom,dss-cx-ipeak = <&cx_ipeak_lm 3>` | OPP table with `required-opps` | medium — see §2, the CX ↔ clock pairing is inconsistent in mainline |

Things **already correct** in 7.2.10 (do not chase): the SM6150 LM-pairing fix is in the tree
(`dpu_5_3_sm6150.h` `sm6150_lm[]` has no `lm_pair`; upstream
<https://patchew.org/linux/20241217-dpu-fix-sm6150-v2-1-9acc8f5addf3@linaro.org>), writeback for
SM6150 is in (`sm6150_wb[]`), and the UBWC/reg-dma/vbif bases match the vendor once `sde-off` is
subtracted.

## 5. Ranked hypotheses, with the read that confirms each *before* any change

### H1 — MDP fetch starvation because mainline's bandwidth/QoS votes are ~6× weaker than the vendor's (most likely)
Mechanism: under a full-screen 1080×2340@60 update the MDP must sustain ≈606 MB/s *by itself*; add
the compositor's GPU/CPU read traffic and the CPU's own DDR traffic and the MDP's real-time reads
exceed the 800 MB/s peak vote. The VBIF starves the realtime pipes, the INTF underruns (blue), and
once the MDP's AXI transactions are backed up the block's register slave stops responding → CPU
wedge. Fits: static page fine, DPMS off fine, video + CSS animation + software compositing all die,
idle fine.

*Confirm first (no change):* under load, read
`/sys/kernel/debug/dri/0/debug/danger/{danger_status,safe_status}` — if `safe` asserts and never
clears while `danger` stays 0, the DPU's own QoS unit says it is starving. Cross-check
`interconnect_summary` (`ae00000.display-subsystem` peak pinned at 800 000).
*Cheap test with existing knobs, no rebuild:*
```
echo 1        > /sys/kernel/debug/dri/0/debug/core_perf/perf_mode     # 1 = FIXED
echo 4000000  > /sys/kernel/debug/dri/0/debug/core_perf/fix_core_ib_vote
echo 1200000  > /sys/kernel/debug/dri/0/debug/core_perf/fix_core_ab_vote
echo 307200000 > /sys/kernel/debug/dri/0/debug/core_perf/fix_core_clk_rate
```
then replay the CSS-animation test. Positive control: `perf_mode = 2` (MINIMUM) zeroes all ICC
votes — if the phone dies *faster*, the bandwidth axis is proven.

### H2 — secondary bandwidth gaps (LLCC floor, per-pipe cap) — weaker than I first thought
After checking values instead of property names, most of the VBIF story dissolves: the QoS remap
tables are bit-identical (`sdm845_rt_pri_lvl` == vendor `qos-rt-remap`), memtypes are identical
(14 × 3), `default_ot_rd_limit`/`wr_limit` are **0 in both** (vendor DT does not set
`qcom,sde-vbif-default-ot-*` either; the live `/sys/kernel/debug/dri/0/debug/vbif` shows
`default_rd_ot_limit 0`, `default_wr_ot_limit 0`, `features 4`, `xin_halt_timeout 16384`), and
`qos-cpu-mask`/`qos-cpu-dma-latency` are dead properties in the vendor tree. What is genuinely left:
`min_llcc_ib` (vendor 800 000 kB/s, mainline 0 → no LLCC floor at all) and the per-pipe IB/split
math (`max-per-pipe-bw-kbps`, `dram-channels = 2`, `num-nrt-paths = 0`). Treat H2 as a refinement of
H1, not a separate root cause.

*Confirm first:* the same `interconnect_summary`/`debug/vbif` snapshot under load; if the LLCC path
never carries a display vote while the MDP is underrunning, H2 adds weight to H1.

### H3 — MDP clock/OPP/CX inconsistency (§2)
288 MHz instead of 307.2 gives 6 % less fetch head-room and an OPP/CX vote that does not match
reality. Not sufficient alone (vendor runs 256 statically) but it removes margin exactly where the
load case needs it.

*Confirm first:* `perf_mode=1` + `fix_core_clk_rate=192000000` — if the hang arrives much sooner,
clock head-room is on the critical path. The permanent fix is a DT/clock change (see §6-T4).

### H4 — the SoC reset itself: a wedged AHB/AXI access to MDSS after the stall (this is what kills the phone)
Precedent in this repo: reading LPI `0x62b40000` via `/dev/mem` wedged CPU6 with the NMI unanswered
and the modem dying 30 s later (PROGRESS 2026-10-26 19:45/18:10 entries). Same signature here: no
printk, no softlockup, PS_HOLD after the APSS watchdog. The access in flight is most likely the DPU
IRQ handler's MDP/INTF register read (every vsync/frame-done) or a `dpu_vbif_clear_errors` write.

*Confirm first:* nothing in dmesg can confirm it — this needs the hardlockup detector + console that
survives: `nmi_watchdog=1 hardlockup_panic=1` on the cmdline, netconsole live, and see whether you
get `Watchdog detected hard LOCKUP on cpu N` (with or without a PC). If the NMI does not arrive, the
only reliable way to name the wedged access is a **DRAM breadcrumb**: a `no-map` reserved page where
every DPU/DSI register-group write is preceded by `writel_relaxed(cookie, breadcrumb_addr)`; read it
from r10 after the reset (`/dev/mem` on r10, or fold it into the existing ramoops region, which is
already present — pstore files in the repo root). That converts "no information at all" into an exact
function:line.

### H5 — SMMU stall on the display stream (lower)
Bring-up already hit `fsr=0x402` faults when a frame was flushed while still being fetched
(PROGRESS 2026-10-24). A translation fault terminates a transaction normally, but a *stall*
(CB with SCTLR.CFG stall / CPR) leaves it outstanding forever — that would also explain a hard bus
hang. The hyp-owned CB 10-12 issue (patch 0017) is audio-only, so not this; but the display stream
`0x800` should be checked for `FSR`/`FSYNR` after a hang.

*Confirm first:* arm/log `arm-smmu` faults (`dmesg | grep -i smmu` is empty today) and read
`apps_smmu`'s `FSR`/`FSR_SYNTR`/`S2CR[display cbndx]` **from r10** after the reset, not from mainline.

### H6 — DSI link / panel (low — config already matches the vendor)
The only real risk here is that our DSIDBG patches hide the evidence: `dsi_host.c:1648-1660` **masks
the DSI error IRQ after 50 FIFO errors**, and `DMA_FIFO_CTRL`, `PHY_SW_RESET` bit 24 and the
`dsi_tpg` path are all local hacks. If a FIFO/underrun storm precedes the hang, mainline is
programmed to stop telling us.

*Confirm first:* revert just the 50-error mask, stream netconsole, replay the CSS animation. Expect
either a `DSIDBG`/`dsi_err_worker` storm right before the blue screen (DSI is a participant) or
nothing at all (DSI is innocent, and H1/H2 stand).

## 6. Minimal tests, in the order I would run them (all reversible, none needs a flash)

* **T0 (2 min, no rebuild, reversible):** `echo 1 > /proc/sys/kernel/nmi_watchdog` — the hardlockup
  detector is compiled in and currently off (§1). Do this *before* anything else; it is the only
  setting that can make the next wedge name itself (`Watchdog detected hard LOCKUP on cpu N`).
* **T0b:** under a *static* screen and under load, snapshot
  `debug/danger/{danger_status,safe_status}`, `debug/vbif`,
  `debug/core_perf/{core_clk_rate,perf_mode}`, `interconnect_summary`, `clk_summary | grep mdss`.
  Difference between idle and load is the baseline for everything else.
* **T1 (no rebuild):** `perf_mode=1` + big `fix_core_ib_vote`/`fix_core_ab_vote`/`fix_core_clk_rate`
  (§5-H1). Then `perf_mode=2` as the positive control. Bank the result, reset to `perf_mode=0`.
* **T2 (kernel, diagnostic only):** enable the INTF underrun interrupt and print a ratelimited
  counter (`dpu_hw_intf.c`: set `INTF_INTR_EN` bit 26 equivalent, read `INTF_INTR_STATUS` in the
  handler). One line of dmesg per underrun turns every future hang into data. Keep it.
* **T3 (kernel, diagnostic):** remove the DSIDBG DSI error mask (§5-H6) and keep netconsole up.
* **T4 (kernel + DT, the actual candidate fix, only after T1/T2 point here):** add the missing
  `256000000` and `307200000` entries to `ftbl_disp_cc_mdss_mdp_clk_src` (they need PLL0 at 768 /
  921.6 MHz, or switch the OPP table to `192/288` with matching `required-opps`) **and** delete the
  `if (1) /* DSIDBG: force max core clock */` hack so the DPU scales per mode. Test the clock part
  and the hack removal separately.
* **T5 (kernel, perf-data parity — not QoS-knob parity):** make the sm6150 `dpu_perf_cfg` match the
  vendor's design point — `min_llcc_ib = 800000`, a per-pipe IB ceiling of 4 500 000 kB/s instead of
  the `min_dram_ib` floor, and the `dram_channels = 2` / `num_nrt_paths = 0` inputs to the bandwidth
  math. **Do not** re-touch the VBIF remap tables or the `qos_lut`s — they are already bit-identical
  to the vendor's (§4 rows 3 and 8). Still the largest change; only after T1/T2 prove starvation.
* **T6 (safety net):** persist `nmi_watchdog=1` (cmdline) + `hardlockup_panic=1` if T0 shows the
  detector firing, and add the DRAM breadcrumb from §5-H4. With those in place the next hang names
  itself instead of costing a day.

## 7. Things this investigation rules out (so nobody re-tests them)

* `icc` bandwidth *release* churn per commit — `enable_bw_release = 0`, and the release path is
  debugfs-gated (`dpu_core_perf.c:277`, `dpu_crtc.c:680,1249`).
* Idle power collapse / GDSC collapse races — `has_idle_pc` exists but the PC path is only wired to
  command-mode encoders (`prepare_idle_pc` is defined only in `dpu_encoder_phys_cmd.c:509`); our panel
  is video mode, and `mdss_core_gdsc` is on with the subsystem `active`.
* Missing MDP clock rate change churn per commit: because of the force-max hack the OPP never changes,
  so `dev_pm_opp_set_rate` early-returns; there is no per-frame RCG re-glitch today.
* DSI link configuration mismatch with the vendor (burst mode, HS clock lane, 4 lanes, pclk/byte
  clocks all match).

## 8. Open questions — status after the follow-up checks

1. ~~`qos_lut` tables~~ — **closed, no difference.** mainline `sm8150_qos_linear = 0x0011222222223357`
   / `sc7180_qos_macrotile = 0x0011223344556677` / `sc7180_qos_nrt = 0x0` are exactly the vendor's
   `<0x00112222 0x22223357>` / `<0x00112233 0x44556677>` / `<0 0>` unpacked.
2. `highest_bank_bit`: does the DT value actually reach `MDSS_UBWC_STATIC`? Still open. Needs one
   register read **from r10** (or r10's own reg dump) — do **not** poke MDSS from mainline while it
   is running.
3. ~~Is the hardlockup detector available?~~ — **yes, compiled in but OFF at runtime**
   (`CONFIG_HARDLOCKUP_DETECTOR_PERF=y`, `nmi_watchdog = 0`). §1 has the detail; turning it on is the
   first thing to do before the next hang test.
4. Whether the vendor `sde` leaves INTF_INTR_EN unmasked and thus would have flooded dmesg — i.e.
   whether r10 logs underruns on this phone at all (it draws smoothly, so probably never). Still open,
   low value.
5. **New:** what does r10 actually vote on `mdp0-mem`/llcc during video playback? Reading
   `/sys/kernel/debug/interconnect/interconnect_summary` on r10 under load would give the vendor's
   real numbers instead of the DT's ceiling — the single most direct calibration for H1. r10's icc
   debugfs is `debugfs`-mounted (`/sys/kernel/debug/qcom_icc` or the standard one) — `r10` only,
   read-only, no risk.

## Sources

* Mainline tree in this repo: `kernel/linux-7.2.10/drivers/gpu/drm/msm/disp/dpu1/{dpu_core_perf.c,dpu_encoder_phys_vid.c,dpu_hw_intf.c,catalog/dpu_5_3_sm6150.h}`, `drivers/clk/qcom/dispcc-qcs615.c`, `arch/arm64/boot/dts/qcom/talos.dtsi`, `drivers/interconnect/qcom/qcs615.c`.
* Vendor r10 tree: `~/violet-pmos/kernel/{arch/arm64/boot/dts/qcom/sm6150-sde.dtsi, drivers/clk/qcom/dispcc-sm6150.c, drivers/gpu/drm/msm/sde/sde_hw_catalog.c}`; vendor panel/bus reference in `dt/ref/`.
* Upstream clock history: <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/log/drivers/clk/qcom/dispcc-qcs615.c> (add `9b47105f5434707eab065f65e7d35c62a51179f8`, 2025-07-16; nothing newer that adds MDP rates).
* SM6150 LM-pairing fix already present: <https://patchew.org/linux/20241217-dpu-fix-sm6150-v2-1-9acc8f5addf3@linaro.org>; writeback for SM6150: <https://patchew.org/linux/20250114-add-writeback-support-for-sm6150-v2-1-d707b31aad5c@quicinc.com>.
* Local history relied on: PROGRESS 2026-10-27 (crash isolation), 2026-10-26 19:45 (LPI `/dev/mem` read wedges the AP, NMI unanswered), 2026-10-24 (DPU prefetch one-line-late fix, `fsr=0x402` in-flight fetch faults); RULED-OUT "Display (DSI video stall)".
