# violet mainline — current status

Derived from [PROGRESS.md](PROGRESS.md) (newest entry wins); **update this page whenever a status changes.**
Last synced: 2026-10-29 (latest log entry: "2026-10-29 07:35 — the GPU lockup is systemic, not ATL/Vulkan-specific
(and needs a kernel fix)").

Headings quoted in the tables below are PROGRESS.md entry titles, so they can be searched for. Note that the
stretch of entries labelled 2026-10-25 "touch …" through "2026-10-26 (later) — AUDIO" carries dates one day
ahead (see the header note in PROGRESS.md).

## How it boots today

- Kernel: mainline **7.2.10** (`7.2.10-sm6150`), built with `make ARCH=arm64 LLVM=1`; DTB `violet-sm6150.dtb`
  on top of `talos.dtsi` + `pm6150.dtsi`/`pm6150l.dtsi`.
- Route: **ABL boots `boot-mainline.img` directly** (native boot, verified 2026-10-25 11:56). The `dtbo`
  partition is **erased on purpose**: with no valid dtbo ABL skips the overlay path and takes our single
  appended DTB without an ID match. **Never reflash `dtbo-vendor.img`** — it re-arms the overlay that refuses
  our DTB. Back to the old downstream environment = flash `~/violet-pmos/images-r9/boot-r10.img` to `boot`.
- kexec from r10 is no longer the daily route; `ml-boot.sh` / `kexec-test.sh` / `to-r10.sh` still exist but are
  now legacy (they were the only route before 11:56).
- Scripts: `mk-bootimg.sh` builds `boot-mainline.img` (header v2, base 0, kernel 0x8000, ramdisk 0x01000000,
  tags 0x100, dtb 0x01f00000) and injects `qcom,msm-id 355 0` / `qcom,board-id 34 0`.
- Human-in-the-loop: `cue.sh <ok|fail|fastboot|power|net|ask>` and `need-hands.sh <fastboot|power|net> [sec]`
  play a distinct sound per situation (the user does not see notifications) and poll for the transport.
- Fastboot without buttons: `./enter-fastboot.sh` (calls `/usr/local/bin/reboot-bootloader` on the phone, which
  writes "bootloader" through the reboot-mode framework → PON spare → ABL `FASTBOOT_MODE`). ~15 s, no partition
  writes. The `misc` BCB route does not work on this ABL.
- Phone shell: `./rssh '<cmd>'` (and `./rscp` via the same symlink) re-resolve the NCM link-local every call —
  a cached address fails as `could not resolve hostname %enp0s20f0u4`. ssh host must stay **unbracketed**,
  scp needs the brackets.
- Audio test in one shot: `/usr/local/bin/audio-test [file] [secs]` on the phone (source `phone-audio-test.sh`)
  routes MM3 → `PRI_MI2S_RX`, plays, and dumps the AFE lines. Tones live in `/var/tmp` (`/tmp` is wiped).
  `/etc/modprobe.d/50-violet-audio.conf` sets `no_rca_mode=2` + `clk_mode=0` so a plain reboot is boot-ready.
- **ADSP services must be built in, not modular**: `QRTR_SMD`, `RPMSG_QCOM_GLINK_SMEM`, `QCOM_FASTRPC`,
  `QCOM_PD_MAPPER` are `=y` as of the 14:22 build — as modules they load at ~25 s and fail with `-ENOMEM`
  ("failed to create endpoint"), which leaves the ADSP audio PD unregistered and every AFE command timing out.
- `KCONSOLE`: the default cmdline is `console=ttyMSM0,115200n8 ignore_loglevel loglevel=8`;
  `KCONSOLE="loglevel=4" ./ml-boot.sh <tag>` drops the UART console. Backup: `kexec-test.sh.bak-console`.
- Modules: 747-module tree installed in `/lib/modules/7.2.10-sm6150`. Earlier boots had no module tree,
  so only built-in drivers worked.
- Observation: NCM gadget + ssh over IPv6 link-local (the interface re-enumerates as `enp0s20f0u1`/`u4`), netconsole
  to `10.11.12.1:6666` (`socat` -> `netconsole2.log`), `harvest4.sh`, plus `attention.sh` (a laptop chime when the phone is unreachable).

## Summary

| Subsystem | State | One-line detail | Latest log entry |
|---|---|---|---|
| Boot path (kexec) | Works (no longer needed) | r10 -> kexec -> 7.2.10; `ml-boot2.sh` works around the corrupt /boot/initramfs (now repaired) | 2026-10-27 — kexec failures root-caused |
| Boot path (ABL / native) | **Works, FLASHED to `boot` (2026-10-27)** | `dtbo` erased → ABL legacy path takes our DTB; boots to userspace with no kexec | 2026-10-25 11:56 — MILESTONE |
| Display / DSI / panel | **Works, with a boot-time init race (D1)** | 2340×1080, brightness, backlight all fine. But the first `msm_dsi_host_power_on` at boot can fail to take the 6 GHz link rate — `clk-rcg2.c:136 update_config` warning + `dsi_err_worker status=4` FIFO errors — leaving a black panel while DRM says `DSI-1 connected` and the compositor keeps rendering (proved by a session screenshot). A later unblank re-runs the enable and it comes up; no reboot needed. Seen 2026-10-29 on a charger-mode boot after the battery died | 2026-10-29 |
| Backlight / WLED | Works | `qcom,num-strings = <2>` killed the ~1150/s OVP storm | 2026-10-26 00:15 IST — ROOT CAUSE FOUND AND FIXED: backlight WLED |
| GPU (freedreno A612) | **Renders, but locks up under load** | RGMU/zap bring-up works and `vkcube` runs (Turnip Adreno 612, Vulkan 1.0.354, Mesa 26.2.5), but 9 `hangcheck detected gpu lockup rb 0` events occurred 06:56–07:31 on 2026-10-29 with ordinary clients (`phoc`, `gnome-control-center`, ATL). See the ATL row and PROGRESS "GPU lockup is systemic" | 2026-10-29 |
| Touch (NT36672A) | Works | i2c 0x01, delayed_work init (local hack) | 2026-10-25 - TOUCH WORKS |
| phosh / greeter | Works | greetd + phrog start unaided at boot (evdev built in) | 2026-10-25 - greeter comes up on mainline unaided |
| Post-login UI freeze / SoC wedge | **Fixed 2026-10-27** (protected DRAM reservation) | SoC hard-locks ~30-40 s after login; leading cause: MDSS SMMU faults | 2026-10-25 10:45 — CLAUDE SESSION: the post-login freeze is the upstream "drm/msm: fix SMMU fault dumps" bug |
| Storage / eMMC | Works | 8-bit, non-removable, no CQE, HS200; 9.3 GB load test clean | 2026-10-26 00:50 IST — prof14 |
| USB gadget / networking | Works | dwc3 peripheral high-speed, NCM, ssh, netconsole | 2026-10-26 06:40 IST — STATUS SNAPSHOT |
| netconsole as panic channel | Partial | carries normal kmsg, but no panic text | 2026-10-25 — audio: … WRONG DRIVER |
| pstore / ramoops | Partial | console + pmsg records work after warm resets; no `record-size`, so no panic (dmesg) record | `violet-sm6150.dts` `ramoops@a1600000` |
| Serial console (ttyMSM0) | Works (suspect) | GENI UART registered as console; may be causing IRQ-off stalls | 2026-10-25 10:50 — NOTE FROM THE CLAUDE SESSION: second lead, the serial console |
| PMIC / SPMI IRQ storm | Works (patched) | `cleanup_irq()` now also writes `QPNPINT_REG_EN_CLR` | 2026-10-25 22:35 IST — CPUs 5-7 EXONERATED |
| Watchdog (APSS) | Partial | no mainline driver; disabled via `wdt-disable.py` (sticky across kexec) | 2026-10-24 (night) — the "silent" hang is NOT silent |
| Lockup detection | Partial | softlockup works; hardlockup/NMI unusable ("NMI not fully supported") | 2026-10-25 22:20 IST — UI FREEZE DIAGNOSED |
| WiFi (WCN3990 / ath10k) | **Works (native boot)** | `patches/0015` (create the BSS peer before station vdev start) + MPSS. Live: `wlan0 UP <phone-ip>/24`, associated `<home-ap-ssid>`, −82 dBm, 18 Mbit/s; AP mode works too. Everything in this log since 2026-10-28 is driven over it. W7 (`bdwlan.*` packing via `ath10k-bdencoder` + `qcom,calibration-variant`) is optional sensitivity polish | 2026-10-29 |
| Audio: ADSP / APR / PCM | **Works (heard by ear 2026-10-26; native boot 2026-10-28)** | SMMU fix (context banks 10-12 are hypervisor-owned, stream 0x1721 now translates): the speaker-path stream plays end to end (24 WRITE_DONE, no crash, no reset). `no_rca_mode=2` is boot-wired via `/etc/modprobe.d/50-violet-audio.conf`. Mic still not working (WCD937x / SoundWire parked) | 2026-10-26 18:10 — AUDIO PLAYBACK PATH WORKS |
| Audio: speaker amp (TAS2563) | **Works — ROM mode, no RCA firmware needed** | `tas2563RCA1.bin` is a TI PPC3 regbin that **no vendor image ships** (checked `vendor.img` 2026-10-28: `/firmware` has only `tas2563_uCDSP.bin`; `persist/audio` has only `tas2563_cal.bin`). `patches/0018` adds `no_rca_mode` (set to 2 on the device) + a ROM-mode fallback that writes PWR_CTL.MODE on stream start, so the amp powers and the **speaker is audible — confirmed by ear 2026-10-26**; re-verified 2026-10-28 natively: PWR_CTL 0x0e idle → **0x0c while streaming** → 0x0e after (`phone/amp-pwrctl-during-tone.py`). No boost/BOP tuning without the regbin | 2026-10-26 19:45 — amp powers on with the stream |
| Audio: WCD9375 / SoundWire | Broken (parked) | enumerates, then UNATTACHED after MASTER_CLASH_DET | 2026-10-26 (later) — AUDIO |
| Remoteprocs | **Works** | ADSP boots; CDSP region set (boot not reported); **MPSS boots and stays up** — see the modem row | 2026-10-26 06:15 — the modem is now alive with 41 QMI services |
| Modem (MPSS) | **Works** | Registers on QRTR with **41 QMI services** (NAS, WDS, DMS, UIM, IMS, location, EFS, IPA control, servreg 180) and stays up. Three separate causes of the old "fatal error without message" at 40 s, all fixed: (1) `rmtfs@0` sat at **physical address 0** — the vendor `reg = <0 0x200000>` means *allocate dynamically*, so it is now a real carve-out `rmtfs@a1e00000` (0x280000, `qcom,vmid = MSS_MSA`, client-id 1) and the modem opens `modem_fs1/fs2/fsg`; (2) missing **IPA** firmware/GSI carve-outs (`ipa-fw@97100000`, `ipa-gsi@97110000`) plus the ipa-ap/module smp2p pair — without them the first IPA-enabled modem boot reset the SoC ~16 s after "modem is now up"; (3) `qcs615_domains[]` listed the **same root domain twice**, so every probe returned `-EBUSY` and pd-mapper (QRTR service 64) never registered — one entry per domain now | 2026-10-26 06:15 — the modem is now alive with 41 QMI services |
| Camera / sensors | **Not started** (sensors scoped 2026-10-28) | Sensors are behind the Snapdragon Sensor Core, not AP I2C: QRTR service 400 is alive on the ADSP and libssc reaches it, but no sensor registry is loaded (`'registry' sensor unavailable`) and mainline has no SSC/CHRE/sns driver or DT nodes. Only IIO devices are the two PMIC ADCs, so Phosh cannot rotate. See `CHECKLIST.md` §6 | 2026-10-28 — sensors scoped |
| Suspend / resume | **Does not work — masked, not fixed** | Only `s2idle` is available (`/sys/power/state` = `freeze mem`, `mem_sleep` = `[s2idle]`, no `deep`). On 2026-10-26 the phone suspended when idle on battery and never came back (black screen, WiFi gone, power key did not wake it). Masked three ways so it cannot happen by accident: gsd-power `sleep-inactive-{battery,ac}-type='nothing'`, `/sys/power/autosleep` off, and `HandlePowerKey=ignore` in `/etc/elogind/logind.conf`. Real fix = qcs615 s2idle/PDC/RPMh wakeup work in the kernel → needs USB to test | 2026-10-28 — verified capability + masking |
| Charging / power supply | **Works — charges in the SMB5's hardware defaults; gauge sign fixed 2026-10-29** | Charger registers read directly (`0x1006`=0x03 active, `0x1051` bit0 inhibit=0, `0x1340`=0x00 not suspended, `0x1370`=0x1e ≈3 A ICL, `0x1310` bit4 VBUS present): the SMB5 charges without any driver. `violet-vbat` had the current sign inverted (positive = charging), which made it report `Not charging` and count *down* while the pack filled; fixed, `current_now` now reads +0.85 A. **No upstream SMB5 driver** → no AICL/PD/thermal/termination control | 2026-10-29 |
| Lock screen / password | **Works (re-enabled 2026-10-28; needs auth now)** | It had been fully disabled on 10-27. Four gsettings keys plus Phosh's own switch: `lockdown disable-lock-screen=false`, `screensaver lock-enabled=true`, `lock-delay=0`, `session idle-delay=300`, and **`sm.puri.phosh.lockscreen require-unlock=true`** (that one alone let anyone swipe past). Authentication additionally needed a PAM service, which phosh does not ship on Alpine: `/etc/pam.d/phosh-lockscreen` + `/etc/pam.d/phosh` (plain `pam_unix`). Same upstream bug as Arch FS#80192 | 2026-10-28 |
| Android apps (ATL) | **Installed; simple + real apps run, video hits the GPU lockup** | `android-translation-layer 0_git20261019-r0` from Alpine edge/testing (chunked push over WiFi, no flash). `gles3jni` runs; NewPipe 0.29.1 launches and browses. Playing video dies because the A612 GPU hangs (`hangcheck detected gpu lockup rb 0` → `VK_ERROR_DEVICE_LOST` → SIGSEGV) — **same failure with `GSK_RENDERER=gl`**, and `gnome-control-center` triggers it too, so this is the GPU driver, not ATL or Vulkan. MediaCodec = ffmpeg software decode (no VAAPI/DRM_PRIME). Launcher `/usr/local/bin/atl-run` (default now `vulkan`; override `ATL_GSK_RENDERER` to gl or cairo), desktop entry "NewPipe (ATL)". Instagram not viable (split APKs + Play Services + same GPU path) | 2026-10-29 — ATL brought up |
| pmOS kernel package | Partial | `linux-postmarketos-qcom-sm6150-7.2.10-r0.apk` builds; never booted from | 2026-10-18 (evening) |

## Works (verified)

**Boot / platform**
- Fixes that were needed to boot: pm6150l RPMh `qcom,pmic-id = "c"`; `&aggre1_noc { /delete-property/ clocks; }` (its QoS writes
  hung the CPU); `&tlmm { gpio-reserved-ranges = <0 4>; }`; board-defined `sleep_clk`/`xo_board_clk`; `pil_gpu_mem` at
  0x97115000; and in the config, `QCS_GCC_615`, `QCS_GPUCC_615`, `QCS_DISPCC_615`, `PINCTRL_QCS615`, `INTERCONNECT_QCOM_QCS615`.
- `CONFIG_INPUT_EVDEV=y` and `CONFIG_FUSE_FS=y`. Without evdev, phoc died with "libinput initialization failed".

**Display**
- Root cause of the DSI stall: DPU 5.x needs the programmable fetch one line later. The fix in `dpu_encoder_phys_vid.c`
  `programmable_fetch_config()` adds `horiz_total` when `core_major_ver == 5` (start 0x2e5e41 = r10).
- Also kept: the new `qcom-lcdb-regulator.c` driver (`qcom,pm6150l-lcdb`) for panel avdd/avee; DSI vdda = `vreg_l3e_1p2`
  (1.232 V); PHY rail l4a at 925 mV; PHY LDO 0x1c; `data-lanes = <1 2 3 0>`; HS_TIMER_CTRL 0x3fd08; PLL ICP 0x3f; and a
  backport of the upstream 6G byte-clock rounding.
- One DRM device: boot **without** `msm.separate_gpu_kms=1`, which gives card0 with DSI-1 + renderD128. Console font: `fbcon=font:TER16x32`.

**Backlight**: WLED on PM6150L with `qcom,num-strings = <2>` (driver default was 4). OVP = 0/s with the panel lit.

**GPU**
- `&gcc { power-domains = <&rpmhpd RPMHPD_CX>; }` fixed `gpu_cc_gx_gfx3d_clk_src: RCG did not turn on`. Devfreq OPPs 435/500/650/745/845 MHz.
- The zap shader works after adding `"qcom,sm6150"` to `qcom_tzmem_blacklist[]` (no SHM bridge). Zap firmware = the ROM's `a612_zap.elf`
  (installed as `qcom/a612_zap.mbn`), plus `a630_sqe.fw` and `a612_rgmu.bin`.
- RGMU bring-up port (`GMU_BYTE_OFFSET = (reg<<2) - mmio_offset`, `adreno_has_rgmu()`). Patch 0004 holds the GPUSTART OOB from
  resume until suspend, which fixed the repeat power-cycle bug. Also `bcm_acv` `.enable_mask = 0x8`.
- `bound ... (ops a3xx_ops)` and the dummy vdd/vddcx messages are normal (not defects). The `force_mem_core`/`a6xx_pm_resume`
  "fixes" turned out to be unnecessary.
- Loose end: `506d000.gmu` has no driver bound, so the gcc/gpucc `sync_state()` stays pending (possibly cosmetic).

**Touch**
- `touchscreen@1`, `reg = <0x01>` (0x62 is only the HW command window); `vcc-supply = <&pm6150l_lcdb>`; `iovcc-supply = <&vreg_l13a_1p8>`;
  reset gpio 88 taken `GPIOD_ASIS` and never written.
- `novatek-nvt-ts.c`: probe only claims the resources, then `nvt_ts_init_work` polls every 200 ms for up to 30 s. Waiting inside
  probe blocks the panel's deferred probe. Verified: 944 real events.
- Never use `vreg_l11e_2p9` for touch (it is the eMMC supply).

**Greeter**: greetd -> phrog starts at boot, unaided, on seat0/vc7. Launching greetd from an ssh shell gives a session with no seat (it inherits the ssh cgroup).

**Storage**: `&sdhc_1 { bus-width = <8>; non-removable; /delete-property/ supports-cqe; }` and no `max-frequency` (the 52 MHz cap ran HS200 timing out of spec).
`mmc0: new HS200 MMC card`, 58.2 GiB, 21 partitions. The rootfs is a loop image on `mmcblk0p86` (recurring EXT4 error count 16 on that partition).

**USB**: `&usb_1_hsphy` (vdd=L4, pll=L11, dpdm=L17); `&usb_1 { dr_mode="peripheral"; maximum-speed="high-speed"; qcom,select-utmi-as-pipe-clk; }`; `USB_CONFIGFS`/`USB_F_NCM` built in.

**PMIC**: the stale-IRQ quench in `spmi-pmic-arb.c` (out-of-range APIDs and `cleanup_irq()` EN_CLR) reduced 16,677 suppressed reports to one line.

**Audio (partial)**
- ADSP: `&rproc_adsp_mem { reg = <0x0 0x95300000 0x0 0x1e00000>; }` (upstream's 0x95900000 gave -22), `&rproc_cdsp_mem` at 0x93b00000,
  firmware `qcom/qcs615/adsp.mdt` + `adsp.b*`.
- Legacy APR (not AudioReach): q6core/q6afe/q6asm/q6adm; card `qcom,sm8250-sndcard`.
- Amp bus: `&qupv3_id_1` + `&gpi_dma1` + `&i2c4` (`i2c@a80000`, gpio20/21) enabled; the amp at 0x4c probes cleanly.
- Playback FE: `mm3-dai-link` -> `pcmC0D2p` (MM1/MM2 are capture-only on this firmware).
- Routing: `PRI_MI2S_RX Audio Mixer MultiMedia3`, set by numid (`amixer sset` rejects the name).
- `&q6afedai { dai@16 { qcom,sd-lines = <0>; } }` is required, or `fail to prepare AFE port 10`.

**WiFi prerequisites (done, not sufficient)**: RPMh regulator nodes for ldo9 (pm6150) and ldo1/2/10 (pm6150l), always-on; `wifi@18800000` with
4-cell GIC IRQs and SID 0x1640; `wlan_msa_mem@93300000` shrunk to 1 MB; ath10k WCN3990 firmware installed. `ath10k_snoc` probe returns 0.

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

## Local patches / tree changes not upstream-shaped yet

- `novatek-nvt-ts.c` delayed_work init. Upstream shape: panel-follower (`drm_panel_add_follower`, the unmerged "support being panel follower" patch).
- `panel-novatek-nt36672e.c` + `novatek,nt36672a-shenchao` (325-byte init via `gen-panel.py`). TODO: fold into `nt36672a.c`; add the binding entry.
- `qcom-lcdb-regulator.c` (new driver); `dpu_encoder_phys_vid.c` prefetch fix; `dsi_phy_14nm.c` LDO 0x1c + ICP 0x3f; `dsi_host.c`
  HS_TIMER_CTRL + byte-clock rounding backport; DSI bridge `.enable` deferral of VID_MODE_EN.
- Display debug code to remove (as of 2026-10-23): DSIDBG/DSIREG/INTFREG in `dsi_host.c`, `msm.dsi_tpg` in `dsi_manager.c`,
  forced core clk in `dpu_core_perf.c`, the 288 MHz entry in `dispcc-qcs615.c`. Still to re-check one by one: DSI PHY reset BIT(24),
  TPG/DMA_FIFO_CTRL/TRIG_CTRL tweaks.
- `spmi-pmic-arb.c` stale-IRQ quench + `cleanup_irq()` EN_CLR (probably kexec-only).
- `qcom_tzmem_blacklist[]` += sm6150; `bcm_acv` enable_mask; `bcm_mm1` keepalive; the RGMU port + patch 0004. The 6-patch series against vanilla 7.2.10 lives in `patches/` (dated 2026-10-18).
- `drivers/soundwire/qcom.c` init-before-add ordering patch (harmless, kept); the SMMU v3 1-7 backport.
- DTS-only kexec workarounds: `aggre1_noc` clocks deleted, `gpio-reserved-ranges`, vendor reserved regions/imem/`/firmware/android`
  (only for the old ABL experiments).
- Image hygiene: delete `90-violet-pixman.sh.disabled`; drop `90-violet-disable-touch.rules` from the device package (pmaports).

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
