# Archived from STATUS.md on 2026-11-09 (state of 2026-10-25, mostly superseded)

These sections were written during the October crash hunt. Most items are FIXED or re-diagnosed (post-login freeze = protected DRAM, 2026-10-27; speaker amp = ROM mode; WCD9375 = works; WiFi = works). Kept for history only; the live status is STATUS.md.

## Broken / open

**Post-login UI freeze / SoC wedge**
- Symptom: SoC hard-locks ~30-40 s after login (the greeter alone never froze). Each boot a different subsystem notices first (mmc
  timeout, RPMh `-110`, RCU stall, `dpu frame done timeout` x10). The SoC then resets with an empty pstore: a hardware reset, not a panic.
- Leading hypothesis (10:45): the upstream "drm/msm: fix SMMU fault dumps" bug. prof47 netconsole showed
  `arm_smmu_context_fault: 483976 callbacks suppressed`, `fsr=0x402`, SID 0x800 (MDSS), and IOVAs inside the fbcon framebuffer.
  The display keeps fetching a framebuffer whose mapping has already been released.
- Competing leads still standing: (a) `bcm_mm1` (carries `qxm_mdp0`) has no keepalive, so the RPMh sequencer gets stuck, giving
  `Error sending AMC RPMH requests (-110)` (seen in prof13); (b) synchronous 115200-baud UART console printk keeping CPUs IRQ-off;
  (c) older: the vendor's separate `disp_rsc`, and `msm_disp_snapshot_state()` escalating a stall.
- Ruled out (do not re-test): storage/eMMC, GPU runtime-PM, CPUs 5-7, the PMIC storm, the WLED storm, "GPU-only" (pixman dies too, at
  ~247 s), specific apps (BPF/seccomp `kick_all_cpus_sync` is only the messenger), and TCS counts.
- Never measured: the PSCI-OSI idle theory (the `cpuidle-off` "survival" was invalid).
- Last tried: Image = 7.2.10 + MM1 keepalive + SMMU v3 1-7 (built 10:44), run as `smmufix1` via `ml-login-test.sh`.
- **New, preliminary (smmufix1, running at ~11:10, not yet logged):** Image #109 (= MM1 keepalive + SMMU v3 1-7) still faults. `login-smmufix1-dmesg.txt`: SID 0x800 `fsr=0x402` context faults start at **t=5.2 s, during boot, before any login**, at ~30-70k/s (`callbacks suppressed` 140k-380k per 5 s up to t=105 s). Faulting IOVAs are low (0x1000, 0x2000 ... 0x1b9b000), not the fbcon framebuffer range seen in prof47. No RCU stall/soft lockup/AMC -110 yet at t=109 s. So the SMMU v3 patches do **not** remove the MDSS faults, and the source is earlier than the post-login framebuffer release. Wait for the test's own write-up before concluding.
- Unclear: which renderer the current image uses (`90-violet-pixman.sh` was disabled, then restored for prof9; not stated since).

**Speaker amp / audio output**
- Symptom: no audible sound. Starting the stream hard-resets the PMIC ("Triggered from Hard Reset"). This happens even with
  `panic=0`, `WDT=off`, and Amp Gain 0.
- Hypothesis: the TAS2563 was bound to the `ti,tas2562` driver (not register compatible); it should use `tas2781-i2c.c` `ti,tas2563`.
  AFE vs amp is "still not fully separated".
- Last tried: `compatible = "ti,tas2563"`, `reset-gpios = <&tlmm 22 GPIO_ACTIVE_HIGH>`, `SND_SOC_TAS2781_I2C=m` + COMLIB/COMLIB_I2C/FMWLIB.
  Modules and DTB are shipped; boot test `prof51` (10:54): the phone did **not** come back on USB within 3 min and no console was captured (`kexec-prof51.log`), consistent with the PMIC hard reset still happening. The phone was back for smmufix1 by 11:07.

**WCD9375 / SoundWire (parked)**
- Slaves go UNATTACHED after `SWR bus clsh detected`; `wcd937x` probe `-110`, so the codec is kept out of the card.
- The codec reset is LPASS LPI gpio24. The `pinctrl-sdm670-lpass-lpi` probe wedges a CPU (that block needs an audio clock first).
- Ruled out: runtime-PM, SWR version, port tables, rails, and probe ordering (that patch stays).

**WiFi**: blocked on the **modem**. The WLAN coprocessor is started by MPSS (`wlanmdsp.mbn` via tqftpserv); talos.dtsi has no MPSS/smp2p node,
and there is no QRTR. Needs MPSS remoteproc for sm6150, then tqftpserv. WiFi has never worked on violet in pmOS on any kernel.

**ABL / native boot — SOLVED 2026-10-25 11:56**: `fastboot erase dtbo` + our header-v2 image boots natively.
Cause of the long refusal: with a valid dtbo present ABL must apply the stock violet overlay to our base DTB,
and libufdt cannot; with the dtbo erased it uses `DeviceTreeAppended()`'s single-appended-DTB path, which accepts
one FDT with no ID match and no overlay. `androidboot.dtb_idx=0xafafafaf` in cmdline is the fingerprint of that
path. `boot` now holds mainline; the header-v0 `Image.gz-dtb` idea and the `qcom,pmic-id` "skip the dtbo" trick
were never needed (kept in `CHECKLIST.md` as N2/N4 in case a future ABL update reinstates the overlay path).

**Crash evidence**: netconsole drops panic text; ramoops is configured (8 MB at `0xa1600000`, console + pmsg) but has **no `record-size`**, so there is no `dmesg-ramoops` panic record, only `console-ramoops-0`, and a cold power cycle wipes it; hard resets leave nothing behind.

## In flight right now

| Change / test | Where | Look for |
|---|---|---|
| MM1 keepalive (`bcm_mm1 .keepalive = true`) | `drivers/interconnect/qcom/qcs615.c`, in the tree Image since 10:23 | no `Error sending AMC RPMH requests (-110)`, no `dpu_encoder_frame_done_timeout`, session alive. Revert = drop the line |
| "drm/msm: fix SMMU fault dumps" v3 patches 1-7 | tree Image built 10:44 (`build-smmufix.log`), mails in the scratchpad `smmu-v3/split/` | zero `arm-smmu ... Unhandled context fault` from SID 0x800; no freeze after login. Note: the AI review flagged a possible UAF in patch 4 (CRTC disable racing a commit) |
| Serial-console test (cmdline only) | `KCONSOLE="loglevel=4" ./ml-boot.sh <tag>` with the same Image | stable session → then re-add the UART console to see which change was needed; check no getty runs on ttyMSM0 |
| TAS2563 driver switch (`prof51`: phone did not return, see Broken) | DTB + 4 modules in `/lib/modules/7.2.10-sm6150` | no PMIC hard reset on stream start; audible tone (`audio-test.sh 440` / `tone440.wav`) |
| Remove `Debug Playback` link | `violet-sm6150.dts` | only once sound works |

Coordination: the Claude session does not drive the phone while Hermes runs prof* tests.


## Contradictions in the log (resolved 2026-10-25 ~11:15)

- **ramoops "never configured"** (top audio entry): wrong. The DTS has `ramoops@a1600000` (8 MB, `console-size` and `pmsg-size` 4 MB each)
  and `CONFIG_PSTORE_RAM=y`, which is why `console-ramoops-0` traces exist. What is missing is `record-size`, so panics get no
  `dmesg-ramoops-N` record. **Cheap improvement:** add `record-size = <0x100000>;` (and shrink console-size to fit).
- **ABL bisection (2026-10-13)**: the "discriminator is the KERNEL" table is the invalid one. Its "vendor kernel + OUR DTB: accepted"
  reading was evidenced by "DT model became VIOLET", and VIOLET is also the model of the vendor DT the flashed partition runs. That is the
  `fastboot boot` artifact the PAUSED entry says "invalidated an earlier bisection". Valid verdict: **ABL accepts our kernel and refuses our DTB.**
- **Freeze root cause**: the SMMU v3 patches have now been tested (smmufix1, above) and do not stop the MDSS faults. MM1 keepalive and the
  UART console are still unseparated, since both are in or around the same run. A pass would need the A/B the 10:50 note describes.
- **`force_mem_core` "remaining work"** (TOUCH WORKS entry): stale. The later GPU entry made it unnecessary (GCC CX vote).

