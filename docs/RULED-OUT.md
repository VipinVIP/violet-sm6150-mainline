# violet mainline — ruled out, and lessons

Check here before re-testing anything; add to it when something is disproven (with the test tag and the
PROGRESS.md heading). **Last synced: 2026-10-27 23:45 IST** (correction banner added; older sections not rewritten) (against [PROGRESS.md](PROGRESS.md)).

Format: hypothesis — evidence that killed it — *[searchable fragment of the PROGRESS.md heading]*.
Where a later entry overturned an earlier verdict, the item says so; the later entry wins.

## IMPORTANT CORRECTION (2026-10-27): most "silent hard reset under load" verdicts below may be wrong

The long-standing "SoC hard-resets with no log when the system gets busy" (UI freeze after login, GPU/compositor
freezes, "the display commit path", WLED/PMIC storm theories, eMMC, CPU 5-7, audio first-write crash, modem/ADSP
"poisoning", Firefox/video crashes, `apk` installs, all-core busy loops at 1.9 GHz, ...) had a **common root cause
that was found on 2026-10-27**: mainline treated physical DRAM the firmware protects as ordinary RAM, so the first
program whose memory use grew far enough was handed a protected page and the SoC reset silently (PS_HOLD, nothing in
dmesg). Fix: reserve `0x93500000-0x93afffff` (6 MiB hole vs r10's /proc/iomem) and the top of the high bank
`0x173000000-0x17dcfffff` (177152 KiB) as `no-map` in `violet-sm6150.dts`. Found with a page-by-page physical-address
walk (`phone/pfn-walk.py`-style: died exactly at phys 0x173000000). See docs/PROGRESS.md 2026-10-27 "ROOT CAUSE FOUND".

Consequences for this file: entries below that say "X is the freeze" / "Y was ruled in" are **unreliable**; entries that
say "X does not fix it" remain valid *as observations*. Several earlier "ruled out" items (FastRPC `audiopd` static
process creation "resets the SoC", the first-audio-write DSP crash, modem/ADSP crash cascades) should be **re-tested**
now that the allocator can no longer hand out protected pages.

### Tested and ruled out on 2026-10-27 (crash hunt; do not repeat)
- **CPU frequency**: capping both clusters at 1.2 GHz still hung under Firefox video. The "1.9008 GHz OPP crashes" result
  was the memory bug: re-enabled, it survived 85 s of 8-way load at 74 C.
- **GPU / compositor**: headless GPU stress (60 s at 845 MHz) clean; GPU pinned at 435 MHz still hung; software compositing
  (pixman) + software-GL Firefox, GPU idle, still hung (full blue screen then reset).
- **Audio**: the log showed no audio stream at the moment of the last video hang.
- **Venus/video decoder**: no `/dev/video*` on mainline.
- **IRQ storm**: per-IRQ delta tracker (500 ms) showed only arch_timer/IPI/mmc0 before the hang.
- **Display bandwidth/clock (Hermes H1/H3)**: `core_perf` debugfs perf_mode=1 with ib 4 GB/s, ab 1.2 GB/s, clk 307.2 MHz
  still hung (symptom changed from blue to a frozen white/green frame: the blue underrun colour was a side effect).
- **DDR frequency/bandwidth**: `modules/violet-ddrvote` held the CPU->EBI vote at 6.88 GB/s (r10's DDR devfreq top);
  8-process memcpy still hung. Note the interconnect default vote is INT_MAX until a consumer probes.
- **USB power / charger input limit**: same stress on battery alone (USB unplugged) hung within ~2 s.
- **Big cluster**: cpu6/7 offline + 6 memcpy procs on the little cores still hung.
- **Idle**: phone stayed up overnight; the trigger needs memory growth, not time.
- **6 MiB hole alone** (`0x93500000`): reserving only that was not enough; the tail `0x173000000+` was the main culprit.
- **`nmi_watchdog` at runtime**: cannot be enabled on this kernel (stays 0), so hard lockups are never reported.
- **gmobile**: libgmobile has no on-disk device table; cutouts come from a compiled-in GResource (override with `G_RESOURCE_OVERLAYS`).

## Ruled out

### Audio
- **"The boot-time `AFE failed to vote (3)` wedges the AFE" — false.** Removing the last vote consumer
  (`LPASS_HW_MACRO_VOTE` from `vamacro`) makes the vote error disappear and lets `va_macro` probe, and every AFE
  command still returns `-110` (`CLOCK_SET`, `DEVICE_START`). The vote and the AFE's deafness are independent.
  *[2026-10-25 15:05 — `nomacrovote`]*
- **A failed stream attempt does not just fail, it takes the ADSP's AFE away for the rest of the boot** (all
  subsequent `set params`/`port enable` are `-110`). Treat one attempt per boot as the budget; reboot before
  retrying, don't iterate in the same boot.
  *[same entry]*

### Boot / ABL
- **`misc` BCB `bootonce-bootloader` does NOT make ABL enter fastboot** — written to `mmcblk0p50` offset 0 and
  rebooted, ABL booted Linux anyway. Source agrees: `LinuxLoader.c` decides on `GetKeyPress()` + `GetRebootReason()`
  only, no BCB parsing. Use the reboot-mode/PON route instead (`./enter-fastboot.sh`).
  *[2026-10-25 12:45 — hands-free fastboot]*
- **`reboot bootloader` "does not work" was a caller problem, not a bootloader problem** — busybox 1.38 `reboot`
  has no command argument and glibc's `reboot()` wrapper only takes `howto` (hence the recorded `EINVAL`). Raw
  `syscall(142, 0xfee1dead, 672274793, 0xA1B2C3D4, "bootloader")` reaches the reboot-mode framework and the phone
  enters fastboot. *[same entry]*
- **OVERTURNED 2026-10-25 11:56 — "ABL refuses our DTB" was a *branch*, not a verdict.** With a valid dtbo,
  ABL must apply the stock violet overlay (libufdt) to our base DTB, which fails; with **`dtbo` erased** it takes
  the legacy single-appended-DTB path and accepts our DTB with no ID match and no overlay. Native boot works.
  Everything in this subsection that says "refused, so X was not the cause" was measuring the overlay path only.
  *[2026-10-25 11:56 — MILESTONE: ABL BOOTS OUR IMAGE]* Do not reflash `dtbo-vendor.img`.
- **`fastboot boot <img>` tests an image** — it always runs the *flashed* partition (uname stayed 4.14). It invalidated
  an earlier bisection. Only a real flash tests an image. *[2026-10-13 — PAUSED HERE]*
- **ABL rejects our kernel** — newest verdict: ABL accepts our kernel + vendor DTB; our DTB is the blocker. (The "discriminator is the KERNEL" table in the same
  10-13 entry is the invalid `fastboot boot` reading: its "accepted, DT model became VIOLET" is the vendor DT's own model.) *[2026-10-13 (vendor-node port …)]*, *[2026-10-25 - tried the real-ABL-boot route]*
- **Reading ABL's refusal on the repaired screen** — it shows only splash + "powered by android", then fastboot. Needs UART
  or a header byte-diff instead. *[2026-10-25 - touch: driver-side variables exhausted → ABL refusal: identity is NOT the cause]*
- **Arm64 header differences** — no PE/`CONFIG_EFI`, `text_offset 0x80000`, `code0`=branch/`code1`=0, `/memory` node
  dropped/renamed: each flashed, all still refused. *[2026-10-13 (vendor-node port …)]*
- **DT identity (`qcom,msm-id 163 0` / `board-id 22 0`)** — identical to the DTB ABL accepts from boot-r10.img. **AVB**
  — absent in both images. *[2026-10-25 - touch: driver-side variables exhausted → ABL refusal: identity is NOT the cause]*
- **An applyable dtbo / vendor node names** — replacement `dtbo-mainline.img` (fdtoverlay rc=0), `__symbols__`,
  vendor reserved-memory map, imem, `/firmware/android`: still refused. *[2026-10-13 (vendor-node port …)]*
- **Clearing the `misc` BCB** — made no difference; `fastboot getvar all` empty, `logfs` has no ABL log. *[same]*
- **`__symbols__` in our DTB "didn't help"** — it was never there. `mk-bootimg.sh` "adds" it with
  `dtc -I dtb -O dtb -@`, but labels cannot be recovered from a binary, so the image carried **0** occurrences
  (vendor DTB has 1) on every flash. To test the overlay path properly the symbols must be emitted at compile
  time (`DTC_FLAGS=-@` / `make dtbs`). Only matters if we ever return to the dtbo/overlay path; the legacy path
  in checklist N1 needs no `__symbols__`. *[verified 2026-10-25 11:50 by decompiling both DTBs]*
- **Reading imem from Linux** — bus error (xPU-protected); route closed. *[2026-10-17 — BREAKTHROUGH]*
- **Kexec causes the display stall** — blanking fb0 powers MDSS_CORE_GDSC fully off and unblank re-runs bring-up on
  POR hardware: identical stall. Clean hand-off (all CRTCs off on r10 via `drm_off.py`) also identical. *[2026-10-23
  — display … items 14, 17 "KEXEC RULED OUT"]*
- **Kexec is why touch is silent** (ABL power-on needed) — never testable (ABL refuses), and moot: touch works on kexec
  once the address/timing were fixed. *[2026-10-25 (later still) - touch …]*, *[2026-10-25 - TOUCH WORKS]*
- Still untested lead (not ruled out): header v0 `Image.gz-dtb` + zeroed dtbo, as violet's LineageOS builds it.
  *[2026-10-25 - GPU + ABL: research corrections]*

### Display (DSI video stall, 2026-10-23/24; root cause = DPU 5.x prefetch start one line late)
All "no change" for the stall, *[2026-10-23 — display: panel repaired …]* items 6–17:
- INTF_1 CONFIG2 `DATA_HCTL_EN` off (6); MDP core clock forced 288 MHz — removed UNDERFLOW, stall stayed (7).
- DSI sw reset after each FIFO error; `TPG_DMA_FIFO_MODE` cleared; byte_intf = byte/2; DSI cfg entry (8).
- `DMA_FIFO_CTRL=0x00110000`, `TRIG_CTRL` without BLOCK_DMA_WITHIN_FRAME (9).
- Downstream enable ORDER (VID_MODE_EN deferred to bridge `.enable`) (10).
- r10 PHY lane TIMING_CTRL_5/6/9 + PLL 0x8b4/0x8b8 transplanted live; `rot_clk` on (11); `mdp_lut_clk` on.
- DSI vdda moved to l3e 1.232 V (real bug, kept, no stall change); PHY ULPS clamp is 0 on both (12).
- `PHY_SW_RESET` BIT(24)|BIT(0) (13); PLL ICP 0x3f (kept); full DSI ctrl transplant (15); PHY rail 925 mV (17).
- Upstream byte-clock rounding backport 6cd33b6f4155 — kept, stops PLL re-lock per DCS, stall unchanged (16).
- Panel "all pixels on" (DCS 0x23) stays black — a video-mode panel needs a running stream (15).
- `/sys/class/drm/card0-DSI-1/dpms` cannot be written (EACCES, `-r--r--r--`). *[2026-10-25 23:20 — CORRECTION]*
- DPU 5.3 catalogue swapped interrupt-index bug — checked clean for sm6150. *[2026-10-26 00:50 — prof14]*

### Backlight (WLED)
- **"98 million backlight interrupts"** — awk bug: summed the hwirq number. Real count 69,526. *[2026-10-26 00:05 —
  Storage exonerated … Correction 1]*
- **OVP is brightness-dependent** — sweep 0→160→1024→3000 with `dpms=Off`: no movement. But that entry's "nothing
  to fix in `qcom-wled`" was **overturned** 10 min later: storm exists only while the panel is lit (`num-strings`).
  *[00:05 Correction 2]* vs *[2026-10-26 00:15 — ROOT CAUSE FOUND AND FIXED: backlight WLED OVP]*
- **WLED storm is the freezer** — fixed (`qcom,num-strings = <2>`, ovp=0) yet prof13 still froze. Real bug, not *the*
  bug. *[2026-10-26 00:25 — prof13]*

### GPU
- **GPU binds `a3xx_ops` = wrong family** — `a3xx_ops` is the single shared `component_ops`; ID comes from the
  compatible → A612. *[2026-10-25 - GPU + ABL: research corrections]*
- **`vdd`/`vddcx` dummy regulators are a defect** — normal on every a6xx; power is genpd. Do not add supplies. *[same]*
- **`force_mem_core/periph_on` in gpucc-qcs615 + reordering `a6xx_pm_resume`** — unnecessary; `&gcc { power-domains =
  <&rpmhpd RPMHPD_CX>; }` alone fixed `RCG did not turn on` (touch24). The "Remaining work" list in the TOUCH WORKS
  entry is stale on this. *[2026-10-25 - GPU: enabled for real]*
- **GPU runtime suspend causes the freeze** — `power/control=on` on gpu + gmu, `runtime_status=active`, froze anyway.
  *[2026-10-25 22:20 / 22:35]*
- **"The GPU is the hang"** (prof9 pixman no freeze) — withdrawn: pixman also dies at 247 s. *[2026-10-25 23:20 — CORRECTION]*
- Zap: **"solved by ordering"** was WRONG (zap never attempted, `cp_init` failed first). Real fix: SHM bridge
  blacklist for `qcom,sm6150`. Upstream linux-firmware qcs615 zap (14256 B) is rejected by TZ; use ROM
  `a612_zap.elf` (14240 B). *[2026-10-17]*, *[2026-10-18 — MILESTONE]*, *[2026-10-13 (later) — device tree DONE]*
- Repeat-power-cycle fault — ruled out: SRAM init, SMMU CB registers, the 99 downstream wake registers, bus halt.
  Partly my bug (skipped AHB fence). Real fix: hold RGMU OOB from resume to suspend. *[2026-10-18 (evening)/(night)]*
- Junk GMU reads `0x5c00bd00` — my port's addressing; need `(reg<<2) - mmio_offset`. *[2026-10-17, run 40]*
- `506d000.gmu` has no driver bound — probably cosmetic (GMU parsed by adreno), keeps gcc/gpucc sync_state pending.
  Not ruled out, just noted. *[2026-10-25 23:00 — CONFIRMED]*

### Touch (final cause: register map at 0x01 not 0x62, plus probe-before-panel-power ordering)
Every item below was "real but irrelevant while the address was wrong". *[2026-10-25 - TOUCH SOLVED IN PRINCIPLE → Why every earlier attempt failed]*
- Reset polarity (both), 10 ms pulse, high-Z/`GPIOD_ASIS` reset, explicit pinmux, bus speed 100k/400k — all `-6`.
  *[2026-10-25 - touch: driver-side variables exhausted]*, *[2026-10-25 - touch: bus up, chip silent]*
- Driver at fault — A/B with node `disabled`: 0x62 NACKs, 0x68 ACKs. *[2026-10-25 (later) - touch: power was the wall]*
- Wrong bus — r10 `i2c-1 → i2c@884000 → novatek@62` = mainline `i2c-0`. *[2026-10-25 (later still)]*
- "The chip is slow" (20×20 ms retry) — dead as stated; the real issue was LCDB power arriving with the panel.
- Bigger retry window — touch20/21/22: 0.4/9/30 s window pushed panel bind to 5.6/15.1/38.6 s (shared
  `deferred_probe` worker). No constant can win; fixed with delayed_work. *[touch22: the retry loop was itself the problem]*
- **Panel-bias (LCDB) vcc theory "dead"** (touch19) — **overturned**: `vcc-supply = <&pm6150l_lcdb>` is in the working
  config; it failed then only because of 0x62. *[2026-10-25 - Ubuntu Touch question …]* vs *[TOUCH WORKS]*
- Userspace i2c scan on r10 — invalid (vendor GENI returns ENOTCONN to i2c-dev); on mainline it is a real measurement.
- Ubuntu Touch port (Halium 9, 4.14.83) and Xiaomi MiCode OSS repo (no violet DTS) — no mainline touch data.
  *[2026-10-25 - Ubuntu Touch question]*, *[2026-10-25 - Xiaomi OSS kernel repo]*

### Session / greeter
- **Seat/libseat bug** — greeter inherited the ssh cgroup when started from a shell (incl. `rc-service`); boot-time
  greeter has `seat0`. Real blocker: `CONFIG_INPUT_EVDEV=m` with no module tree. *[2026-10-24 (late) - phosh runs]*
- Earlier "survived N minutes" runs — invalid, `phoc=`/`phrog=` empty, no session. *[2026-10-24 (evening)]*
- Not the phrog hang (each ≥60 s alone): bare phoc 11+ min, DPMS via wlopm, backlight 0/1024, gsd-power, wayvnc,
  udisksd, upowerd, feedbackd, callaudiod, gvfs monitors, goa-daemon, 60 vblank waits, 2700 legacy flips, 400 MB
  eMMC write. *[2026-10-24 (later) — GPU + display together]*
- 63 atomic commits / FB_DAMAGE_CLIPS blob — inert (msm has no partial update). *[2026-10-24 (night)]*
- **Firefox/Settings cause the freeze** — wrong; whichever task installs a seccomp/BPF filter (even my sshd child)
  hits `kick_all_cpus_sync` first. *[2026-10-25 22:35 — CPUs 5-7 EXONERATED]*

### UI freeze / SoC wedge ~30–40 s after login (oldest → newest; each killed by the next)
1. **CPU7 lost in PSCI OSI idle (EVK idle states)** — `cpuidle-off` "survived" was an artefact (no session started),
   baseline had no ssh link. Never validly tested; later freezes with other CPUs failing make it moot. (The same
   entry's "both measurements the predicted outcome" paragraph cites the invalid run.) *[2026-10-24 (night)]*
2. **CPUs 5-7 stop answering IPIs; BPF JIT free is the messenger** — offlined 5-7, froze anyway at ~505 s; failing set
   became 0,2,4. *[2026-10-25 22:20]* → *[22:35 — CPUs 5-7 EXONERATED]*
3. **PMIC interrupt storm (`cleanup_irq` never EN_CLRs)** — patch masked it (one line), froze anyway. Symptom; patch
   kept. *[2026-10-25 22:45 — PMIC storm patch did NOT stop the freeze]*
4. **eMMC command timeouts (1-bit, removable)** — `bus-width=<8>`+`non-removable` (real fix, kept): prof7 died 107 s,
   prof8 77 s. *[2026-10-25 22:50]*
5. **GPU/compositor path** (prof9 pixman "no freeze") — pixman died at 247 s, hardware reset. *[23:00]* → *[23:20 — CORRECTION]*
6. **Storage** — prof12: 9.3 GB fsync'd at load 5.5, healthy. Do not reopen without a new signal. *[2026-10-26 00:05]*
7. **WLED OVP storm** — fixed, prof13 froze anyway. *[2026-10-26 00:15]* → *[00:25 — prof13]*
8. **My `max-frequency = <52000000>` cap** — was a regression (HS200 timing at 52 MHz; deaths 321-345 s before, 107/77/155
   s after). Reverted. *[00:25 — prof13 … My 52 MHz cap was a mistake]*
9. **HS200 itself / storage again** — prof14 HS200 at proper clock, 785 s healthy at greeter, froze 37 s after login with
   10× `dpu frame done timeout`; different first victim each boot = one shared resource. *[00:50 — prof14]*
10. **RPMh TCS allocation** — `ACTIVE 2/SLEEP 3/WAKE 3/CONTROL 1` matches vendor; do not add TCS. *[00:25 — prof13]*
11. Open, results not yet in the log: `WLR_DRM_NO_ATOMIC=1` (prof11, staged *[23:20]*); MM1 BCM keepalive (upstream
    sdm845 fix for `rpmh_write_batch` -110) *[10:25]*; upstream "drm/msm: fix SMMU fault dumps" v3 1-7 — prof47 showed
    ~480k MDSS (SID 0x800) faults in the fbcon FB *[10:45]*; UART console at 115200 IRQ-off as amplifier
    (`KCONSOLE="loglevel=4"`) *[10:50]*. Remaining 00:50 leads: disp_rsc/ICC, MDSS GDSC, snapshot dump on timeout.

### Storage
- Storage as the freezer — exonerated (above, prof12). eMMC `EXT4-fs (mmcblk0p86)` errors = known corrupt vendor p86.
- Do **not** enable `mmc-hs200/hs400-1_8v` blind (no `vqmmc` in vendor DT) — moot: core selects HS200 anyway. *[22:45]*
- Untested lead: `qcom,dll-config` DT `0x000f642c` vs live `0x00b7642c`. *[22:45]*

### Modem / QRTR (2026-10-25 evening, kprobe-measured)
- **"The modem never gets to glink / the glink handshake is broken"** — false. Measured on the modem edge: v1 VERSION both ways, IPCRTR
  OPEN/OPEN_ACK **both directions**, 30 intents from the modem (16×128, 8×512, 5×1152, 1×8320) and 5×1024 from us, modem TX_DATA
  52 B using our liid 1, RX_DONE both ways, `glink_ssr` + `SSM_RTR_MODEM_APPS` opened by the modem. *[2026-10-25 21:40]*
- **"Our intent-req reuse patch is the bug"** — false, it is downstream-shaped: vendor `qcom_glink_handle_intent_req()` also ACKs a
  reusable local intent without advertising a new INTENT. *[same]*
- **"Android QRTR control packets carry a checksum we don't set"** — false: `qrtr_calc_checksum()` is only used for
  `QRTR_TYPE_DEL_PROC` (in `pkt->proc.rsvd`). `struct qrtr_ctrl_pkt` is byte-identical (20 B), which is why the modem's packets are 52 B. *[same]*
- **"`qcom,sm8150-mpss-pas` is the wrong compatible"** — false: `sm7150-mpss-pas` and `sm8150-mpss-pas` are the same
  `mpss_resource_init` in the working sm7150-mainline fork. **"Missing IPCRTR `qcom,intents`"** — also not the difference: the working
  sm7150/sc7180 nodes declare none either. *[same]*
- **Open, named next step:** `fatal error without message` at 40.0 s is preceded by the modem's IPCRTR payloads dying between
  `qcom_glink_rx_data()` and the rpmsg callback (all three paths are `dev_dbg`). Turn on `file drivers/rpmsg/* +p` +
  `file net/qrtr/* +p` for one start and the drop names itself. *[same]*
- Restart budget: after 3-4 modem starts in one boot the **SoC resets itself** (came back on r10 unaided). *[same]*

### WiFi
- **Missing/typo'd wifi node** — node, MSA, 4-cell IRQs, rails all correct, probe returns 0; it waits for
  `WLFW_FW_READY_IND` forever. *[2026-10-26 07:40]*
- **Blocked on WCSS remoteproc** (07:40 verdict) — **superseded**: WLAN coprocessor is booted by the *modem* (MPSS);
  talos.dtsi has no MPSS/smp2p. Wifi is a modem bring-up project. Never worked on violet pmOS on any kernel.
  *[2026-10-26 09:40 — WHY WIFI IS DEAD]*
- 06:40 STATUS "wifi not yet tested" is stale; dummy regulators fixed with RPMh nodes (prof19).

### Audio
- **AudioReach / `qcom,qcs615-sndcard` path** (07:40 plan) — superseded: firmware is legacy APR (no `adsp_apps`).
  *[2026-10-26 (later) — AUDIO]*
- Upstream `rproc_adsp_mem` 0x95900000 — `qcom_scm_pas_mem_setup` -22; use 0x95300000. *[same]*
- **SWR clock vote** — clocks running (19.2/9.6 MHz). SWR UNATTACHED, ruled out: runtime-PM pin, SWR v1.3.0, port arrays,
  stripped ports (-EINVAL), codec rails, `qcom_swrm_init` ordering patch. *[same, "Ruled out with evidence"]*
- `pinctrl-sdm670-lpass-lpi` for codec reset gpio24 — wedges a CPU, panic ~44 s. Dead end until LPI is clocked. *[same]*
- **Speaker amp = TAS2562 on `0x88c000`** (that entry's "bypass via tas2562.c") — superseded: amp is `ti,tas2563`
  (`tas2781-i2c.c`) on `i2c@a80000` (gpio20/21, reset gpio22); needs `qupv3_id_1`+`gpi_dma1`. *[2026-10-25 — audio …]*
- MM1/MM2 for playback — capture-only on this firmware; MM3 is the playback FE. *[same]*
- PMIC hard reset on stream start: not a kernel panic (`panic=0` still resets), not the APSS watchdog (`WDT=off`), not
  output stage (Amp Gain 0 still resets). AFE vs amp **not** separated (no_pcm BE can't be opened). Suspected
  wrong driver (TAS2562 init on TAS2563); prof51 (10:54): phone did not return on USB within 3 min, no console (`kexec-prof51.log`). *[same, §5–6]*

### Other / platform
- `HARDLOCKUP_DETECTOR` + pseudo-NMI — `NMI not fully supported`; only softlockup works. *[2026-10-25 22:20]*
- Kernel-image misalignment warning under kexec and bit-garbled ramoops text — harmless/known. *[2026-10-17]*

### UI freeze (preliminary, 2026-10-25 ~11:10)
- **"drm/msm: fix SMMU fault dumps" v3 1-7 stops the MDSS faults** — smmufix1 still shows SID 0x800 `fsr=0x402` faults, from
  t=5.2 s (during boot, before login), at low IOVAs (0x1000...). Not yet written up by the test's owner. *[`login-smmufix1-dmesg.txt`]*

### WiFi / modem (2026-10-26, Claude session)
- **"The modem's QRTR/glink path is broken in mainline"** and every Hermes lead about it (checksum, reuse patch, wrong PAS compatible, intents): wrong. The causes were
  platform wiring: rmtfs memory at physical address 0, IPA missing (carve-outs + smp2p + node), a duplicate-entry pd-mapper table, and a boot script that rebooted
  the phone at 93 s. *[2026-10-26 06:15 / 07:00]*
- **"fatal error without message at 40 s is an AP-side glink problem"**: it fires only until the modem has rmtfs, IPA and a working pd-mapper. *[same]*
- **Missing violet board data** was a red herring for the crash (generic and violet `bdwlan` both boot); the crash was the quiet-mode WMI command. *[07:00]*
- **`qcom,xo-cal-data`, RF clock, extra regulators**: not needed; sm7150's working Xiaomi nodes have none. *[research-wcn3990-crash.md]*
- **OpenRC runlevel for new services**: `/run/openrc/deptree` (dated Oct 12) beats the ~1970 clock, so `rc-update add` services (rmtfs, violet-modem) never start at boot. Use `/etc/local.d` or fix the clock. *[07:30]*
- **`/etc/local.d/90-mainline-probe.start` (reboot -f after ~65 s)**: fixed by `/etc/mainline-stay`; it invalidates most "the SoC wedged ~90 s after ..." readings from 2026-10-25 evening. *[06:15]*

### WiFi station association (2026-10-26 10:45) — SOLVED 12:05: the firmware needs a peer (the BSSID) *before* the station vdev start; everything below was the wrong direction (`vdev-start-response status error -1` unchanged)
- requestor_id, extra start flags, appended fixed-param words (streams), channel power/flags fields, placeholder/real SSID, vdev id, bcn_intval/dtim, retries with delay, STA keepalive/ps/psmode skips,
  STA self peer (crashes the fw), regdomain, board data variant, MAC (cloned/permanent), NetworkManager/P2P presence, QMI host-cap skip quirk, cold vs warm modem, display on/off. *[PROGRESS 10:45]*
- **Hypotheses that looked right and were not:** "requestor_id 2/3/4 fixes it" (a sweep artifact: the runs never reached the auth stage); "IBSS vdev starts fine" (it never reached vdev start); "`iw connect` starts the vdev" (it only runs its own scan).

### Audio / glink (2026-10-25 evening, Claude session)
- **"This ADSP never acks AP-initiated glink opens"** (15:40), and the `tx_with_rcid` workaround built on it: wrong. The opens failed
  only because the edge was already wedged. After an ADSP restart, and with intents advertised early (#117), IPCRTR and fastrpc open
  normally. *[2026-10-25 19:39 / 20:15]*
- **"AFE is deaf / PDR servreg -110 / audio PD missing"**: all symptoms of the same glink wedge (RX_INTENT_REQ before any AP intent).
  Fixed by advertising intents in `qcom_glink_create_ept()`. *[20:15]*
- **Replying to RX_INTENT_REQ with the vendor reuse check alone** (#116): not sufficient. *[19:39, Result 1]*
- **TAS2563 / amp as the reset source**: a dummy-codec SEC MI2S BE with no amp still kills the ADSP. *[20:15 afe1/afe2]*
- **MI2S IBIT clock command as the trigger**: `clk_mode=2` (no clock command) still gives an ADSP watchdog. *[afe2]*
- **Missing fastrpc listener / dynamic modules**: `hexagonrpcd` serving the `dsp` partition makes no difference. *[afe3]*
- **GCC `SDR_*` MI2S clocks gated by Linux**: gcc-qcs615.c does not implement them. **AOP load_state**: `qcom,qmp` is wired. *[20:15]*
- **LPASS core HW vote before MI2S start** (`violet_hw_vote=3`, accepted, handle 20): still an ADSP watchdog. *[20:40 vote3]*
- **Remoteproc coredump / recovery path as the AP wedge**: coredump is already disabled; with recovery disabled it wedges sooner. *[norecov]*
- **WiFi glink reply mode**: reuse=Y (ACK only) leaves the modem silent after its HELLO (fatal at 40 s); reuse=N (new INTENT) wedges an AP CPU
  about 20 s after modem up. Neither gives WLFW. *[20:40 wifi1/wifi2]*
- **SDR clock domain (PRI/SEC only)**: QUAT MI2S wedges too. **Audio TBU GDSC**: all TBU GDSCs read `on`. **LPASS NoC BCM SN13/SN9 keepalive**: no
  change. **Linux disabling clocks/GDSCs**: `clk_ignore_unused pd_ignore_unused` still wedges. *[21:15]*
- **Downstream AFE sequence differs from mainline**: it does not; same CLOCK_SET/I2S_CONFIG/DEVICE_START fields (research-downstream-mi2s.md). *[21:15]*
- netconsole has no target configured; to capture a freeze, stream `./rssh 'sudo -n dmesg -w' > file` from the laptop instead.

## Rules and lessons
Tooling / harness
- **kexec only r10 → mainline.** mainline→mainline: dead boot, no USB, needs power cycle. Check `uname -r` starts `4.14`.
- **`WDT=ext` (~32 s bite) kills eMMC** and mimics the wedge; use `WDT=off` for observation runs or treat as ≤32 s.
- **`wdt-disable.py off` is sticky across kexec** (EN never re-set); with EN=0 a hung mainline needs ~15 s Power hold.
- **`sudo -n dmesg`** — plain `dmesg` returns nothing on this image and looks clean.
- **USB gadget re-enumerates (u1/u4) with a new link-local** — re-resolve every call (`rssh`/`rscp`), rescan `enp0s20f0u*`.
- **`phone()` must validate candidates by ssh** — `ip neigh` after ping holds stale/own addresses.
- **Log `phoc=`/`phrog=` per sample** — no "survival" claim without a session.
- **Evidence must land on ext4 (`/var/log`) or leave via netconsole** — `/tmp` is tmpfs; cold power cycle wipes ramoops.
- **netconsole carries kmsg but not panic text**; `panic=0` separates hardware reset from panic. Mute reset + empty
  pstore = hardware reset; ramoops traces only came via `softlockup_panic=1`.
- **Console ring ending at udevd/switch_root says nothing about later drivers** — use live `sudo dmesg`.
- **`sync` after writing on the phone** — a crash emptied the greetd config and a wrapper.
- **Privileged loops: one `sudo -n sh -c '…'`** — sudo inside a loop silently did nothing.
- **ssh: `%iface` host unbracketed (brackets for scp only); use `ssh -T`**, `-n`/`</dev/null` kill heredocs.
- **`amixer sset` rejects routing names (`PRI_MI2S_RX Audio Mixer MultiMedia3`)** — set by `numid`.
- **`/proc/interrupts` pmic_arb lines: sum `$2..$(NF-4)`**, skip header (hwirq field trap).
- **Measure state-dependent storms from SSH at the greeter** (panel lit) — no login per iteration.
- **Build times: `make modules` for a new `=m` ~90 s; LTO Image relink ~25 min; `make dtbs`, not `make …/x.dtb`**
  (doubles the path).
- **`=m` drivers need `/lib/modules/7.2.10-sm6150`** (747 modules installed 10-26 07:40); before that nothing `=m` loaded.
- **QEMU cannot test this device** (no Qualcomm machine/Adreno model); only a `virt` control boot of the kernel. *[PLAN.md]*
- **EGL ctypes: `EGL_PLATFORM_GBM_KHR` = 0x31D7; give every symbol argtypes/restype** (else segfault 139).
Hardware hazards
- **Never claim `vreg_l11e_2p9`** (eMMC supply) for touch; **never force every rail always-on** (boot dies at 0.236 s).
- **No wide register dumps** (GPU 0..0xc000 → RPMh timeouts); **no /dev/mem reads of INTF_0 (0xae6a800) or
  clock-gated DPU pipes** — they hang the SoC.
- aggre1_noc QoS writes and TLMM gpio0-3 reads hang the CPU (fixed: no clocks on aggre1_noc, `gpio-reserved-ranges = <0 4>`).
- **No BTA/DCS read in panel prepare** — error storm + reset.
- Keep brightness ≤ 1024 (user in a dark room).
Flashing / recovery
- **Only a real flash tests an image**; a refused image returns to fastboot in ~10 s (safe iteration).
- **Any flash script must restore r9/r10 on every exit path** (variant-b-flash.sh didn't; needed Vol-Down+Power).
- **Entering fastboot needs Power+Vol-** — busybox `reboot bootloader` ignored, RESTART2 EINVAL; `fastboot fetch` unsupported.
- Revert image `images-r9/boot-r10.img`; sha mismatch vs partition is padding. Read ABL's refusal off the repaired panel.
Workflow
- **Research upstream first** — byte-clock rounding, MM1 keepalive, SMMU fault fix, `tas2781-i2c.c`, CX vote commit
  `5ad7eb6a944e` were all one lookup away after many blind cycles.
- **Grep `sound/soc/codecs` (any subsystem) for the exact part number before binding a generic driver.**
- **Attach a peripheral to the controller its pins belong to**; `-6` = bus OK/no device, `-110` = bus unusable.
- **Don't copy EVK numbers (idle states, TCS, pil_gpu_mem) without checking vendor DT**; firmware owns TCS allocation.
- **Don't apply "suspected fixes" from research sweeps blindly** (gpucc force_mem_core, regulator supplies).
- **Coordinate: only one session drives the phone** (Claude session paused while Hermes ran prof*).

## Analysis errors made before (don't repeat)
- Read `-110`/`-6` backwards on the amp bus and chased power for a cycle. *[2026-10-25 — audio]*
- Bound amp at vendor's `0x88c000` name instead of its pins' controller. *[same]*
- "98 M backlight interrupts" from summing the hwirq number. *[00:05 Correction 1]*
- "Nothing to fix in qcom-wled" — measured only with `dpms=Off`. *[00:05 vs 00:15]*
- "CONFIRMED: it is the GPU" from one pixman boot before it had run long enough. *[23:00 vs 23:20]*
- "cpuidle-off survived" — no session had started. *[2026-10-24 (night)]*
- "CPUs 5-7 wedge" read as cause; `kick_all_cpus_sync` failures name whichever CPUs are stuck. *[22:20 vs 22:35]*
- PMIC storm, then eMMC, then WLED each declared root cause and each failed the next login. *[22:35/22:45/00:15]*
- 52 MHz `max-frequency` cap assumed to disable HS200; it made HS200 run out of spec. *[00:25]*
- "Zap solved by ordering" when zap was never attempted. *[2026-10-17]*
- "a3xx_ops = wrong GPU family". *[GPU status on mainline vs research corrections]*
- Skipped AHB fence for RGMU — caused part of the power-cycle "lockup". *[2026-10-18 (evening)]*
- Touch: copied vendor DT `reg = <0x62>` that its driver never reads; panel-bias theory declared dead while the address
  was wrong. *[TOUCH SOLVED IN PRINCIPLE]*
- "Seat problem" — artefact of starting greetd from ssh. *[2026-10-24 (late)]*
- Wifi "blocked on WCSS remoteproc" — it is the modem. *[07:40 vs 09:40]*
- touch10's stalled boot looked like the touch chip — actually the eMMC rail (l11e) dropped when touch probe failed. *[power was the wall]*
- Audio write-up appended at file end, and PROGRESS.md date labels one day ahead for a stretch — position is true order.

- **WiFi, 2026-10-26 12:05:** the two `Rejecting vdev_start …` firmware strings are not the cause; requestor_id 0–16 changes nothing. A self-peer with the vdev's *own* MAC on a station vdev is never reported by the firmware and crashes it on vdev delete; the peer must be the AP's BSSID. `/dev/mem` reads of the modem carve-out (0x8b000000–0x92dfffff) reset the SoC (XPU) — do not do that.

- **Audio, 2026-10-26 12:50:** disabling `vamacro/txmacro/rxmacro/swr1/swr2` (no AP-side LPASS MMIO users) does not stop the SoC reset on MI2S start; `VA_CODEC_DMA_TX_0` config is rejected by the ADSP with error 3 (not a hang).

- **Audio, 2026-10-26 15:10:** "MI2S port start resets/hangs the ADSP" is wrong (see PROGRESS 15:10): the reset was the ASM shared memory without an SMMU SID. `iommus <&apps_smmu 0x1721 0x0>` fixes it; mask `0xf` is rejected (-22). `audiopd` static process creation resets the SoC. Topology IDs, `endpoint_id_2`, hexagonrpcd and idle time do not avoid the first-write PD crash.

- **Audio, 2026-10-26 18:10:** the "first-write ADSP audio_process crash" and the instant reset were both the audio SMMU stream 0x1721 not translating (hypervisor owns context banks 10-12). Not the topologies, the island config, period size, hexagonrpcd, warm-up time, or the memory-region/VMID route (TZ rejects LPASS/ADSP VMIDs for HLOS DDR).

## LPI gpio24 via AP register access (2026-10-26)
- LPASS HW vote (q6afe cmd 0x100f4) is unsupported by this ADSP (error 3), and reading 0x62b40000+0x18000 hangs the AP even while an AFE stream runs. Do not read/write 0x62b40000 from the AP again without a new theory (check lpass_core_cc clocks or an ADSP-side reset path).
- LPI read with macro vote (block 3) granted + active stream: still hangs the AP (2026-10-26 pk2). Dropping the DCODEC vote clock (dt/violet-lpi3.dtb) did not help either.

## Ruled out 2026-10-29 — the A612 GPU lockups (do not re-investigate these)

Symptom: `adreno_idle: timeout waiting to drain ringbuffer 0 rptr/wptr = 0/C` → `hangcheck detected gpu lockup rb 0`
→ `hangcheck recover!`, killing `phoc`, `gnome-control-center` and ATL clients. Nine events in 35 min on 2026-10-29.

- **Missing GPU firmware** — no. `a630_sqe.fw`, `a612_rgmu.bin`, `a612_zap.mbn` are all present under
  `/lib/firmware/qcom/`, and `vkcube` runs (Turnip Adreno 612, Vulkan 1.0.354, Mesa 26.2.5).
- **A port regression in `adreno_recover()`** — no. The function is byte-identical to current mainline; mainline
  no longer resets `memptrs->rptr/wptr` (that reset only exists in old trees). Nothing local to restore.
- **Missing/broken GPU bandwidth or OPP data** — no. `talos.dtsi gpu@5000000` has `interconnects =
  <&gem_noc MASTER_GFX3D … &mc_virt SLAVE_EBI1 …>` and a 5-point OPP table with CX `required-opps` and
  `opp-peak-kBps` 3.0–7.05 GB/s; devfreq exposes 435/500/650/745/845 MHz.
- **It is the Vulkan/Turnip driver** — no. `vkcube` is fine, and the same lockups hit plain GL/GTK clients.
- **It is the app (NewPipe/ATL)** — no. `gnome-control-center` and `phoc` trigger it too.
- **`GSK_RENDERER=gl` avoids it** — no. It is slower *and* crashes the same way.

Known upstream state: a postmarketOS series "drm: msm: adreno: attempt to recover from ringbuffer drain timeout"
(2026-03) reports the identical signature (`offending task: sway`) and was rejected — calling `recover()` from
`adreno_idle()` violates the recover worker's locking/state assumptions. No upstream fix exists to port.
