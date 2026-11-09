# violet mainline — current status

> **2026-11-03:** the phone's `userdata` was wiped by an Android flash and rebuilt from the repo; every component in the table below was re-verified on build #188 except the items listed as NOT restored in `docs/PROGRESS.md` (top entry): tas2563_coef.bin, NewPipe/ATL master build, Glissando OSK, customised gsettings, personal data. Back up with `host/phone-backup.sh`.


Derived from [PROGRESS.md](PROGRESS.md) (newest entry wins); **update this page whenever a status changes.**
Last synced: 2026-11-09 (docs-only sync; newest PROGRESS entry is 2026-11-07 14:47 vibrator, plus the 2026-11-08 charging work). The audit below is dated 2026-11-02 and the camera/charging/vibrator rows are newer.

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
| Display / DSI / panel | **Works (D1 fixed 2026-10-31)** | 2340×1080, brightness, backlight. The boot-time black panel was the QCS615 dispcc missing the MDSS_CORE reset and `CLK_OPS_PARENT_ENABLE` on pclk0 (`patches/0024`/`0025`); retry workaround removed; DSIDBG diagnostics removed (`0033`), DPU core clock dynamic | 2026-10-31 |
| Backlight / WLED | Works | `qcom,num-strings = <2>` killed the ~1150/s OVP storm | 2026-10-26 00:15 IST — ROOT CAUSE FOUND AND FIXED: backlight WLED |
| GPU (freedreno A612) | **Works on mainline's own A612 power path (#181+)** | The local RGMU port (and its crash under NewPipe: GX power-up failure, then a watchdog reset) was removed; `patches/0028` still stops a failed resume from touching an unpowered GPU. NewPipe video (VOD) plays with 0 GPU errors | 2026-11-02 |
| Touch (NT36672A) | Works | i2c 0x01, delayed_work init (local hack) | 2026-10-25 - TOUCH WORKS |
| phosh / greeter | Works | greetd + phrog start unaided at boot (evdev built in) | 2026-10-25 - greeter comes up on mainline unaided |
| Post-login UI freeze / SoC wedge | **Fixed 2026-10-27** (protected DRAM reservation) | SoC hard-locks ~30-40 s after login; leading cause: MDSS SMMU faults | 2026-10-25 10:45 — CLAUDE SESSION: the post-login freeze is the upstream "drm/msm: fix SMMU fault dumps" bug |
| Storage / eMMC | Works | 8-bit, non-removable, no CQE, HS200; 9.3 GB load test clean | 2026-10-26 00:50 IST — prof14 |
| USB gadget / networking | Works | dwc3 peripheral high-speed, NCM, ssh, netconsole | 2026-10-26 06:40 IST — STATUS SNAPSHOT |
| netconsole as panic channel | Partial | carries normal kmsg, but no panic text | 2026-10-25 — audio: … WRONG DRIVER |
| pstore / ramoops | **Works** | console + pmsg + **readable dmesg panic record** (`record-size` + `pstore.compress=none`; the deflate record was undecodable). Verified with a SysRq-c panic 2026-10-31 | 2026-10-31 |
| Serial console (ttyMSM0) | Works (suspect) | GENI UART registered as console; may be causing IRQ-off stalls | 2026-10-25 10:50 — NOTE FROM THE CLAUDE SESSION: second lead, the serial console |
| PMIC / SPMI IRQ storm | Works (patched) | `cleanup_irq()` now also writes `QPNPINT_REG_EN_CLR` | 2026-10-25 22:35 IST — CPUs 5-7 EXONERATED |
| Watchdog (APSS) | Partial | no mainline driver; disabled via `wdt-disable.py` (sticky across kexec) | 2026-10-24 (night) — the "silent" hang is NOT silent |
| Lockup detection | Partial | softlockup works; hardlockup/NMI unusable ("NMI not fully supported") | 2026-10-25 22:20 IST — UI FREEZE DIAGNOSED |
| WiFi (WCN3990 / ath10k) | **Works (native boot)** | `patches/0015` (create the BSS peer before station vdev start) + MPSS. Live: `wlan0 UP <lan-ip>/24`, associated `<home-ssid>`, −82 dBm, 18 Mbit/s; AP mode works too. Everything in this log since 2026-10-28 is driven over it. W7 (`bdwlan.*` packing via `ath10k-bdencoder` + `qcom,calibration-variant`) is optional sensitivity polish | 2026-10-29 |
| Audio: ADSP / APR / PCM | **Works (heard by ear 2026-10-26; native boot 2026-10-28)** | SMMU fix (context banks 10-12 are hypervisor-owned, stream 0x1721 now translates): the speaker-path stream plays end to end (24 WRITE_DONE, no crash, no reset). `no_rca_mode=2` is boot-wired via `/etc/modprobe.d/50-violet-audio.conf`. Mic works since 2026-10-31 (WCD9375 row below); capture gain fixed 2026-11-02 (see the mic-gain row) | 2026-10-26 18:10 — AUDIO PLAYBACK PATH WORKS |
| Audio: speaker amp (TAS2563) | **Works — ROM mode, no RCA firmware needed** | `tas2563RCA1.bin` is a TI PPC3 regbin that **no vendor image ships** (checked `vendor.img` 2026-10-28: `/firmware` has only `tas2563_uCDSP.bin`; `persist/audio` has only `tas2563_cal.bin`). `patches/0018` adds `no_rca_mode` (set to 2 on the device) + a ROM-mode fallback that writes PWR_CTL.MODE on stream start, so the amp powers and the **speaker is audible — confirmed by ear 2026-10-26**; re-verified 2026-10-28 natively: PWR_CTL 0x0e idle → **0x0c while streaming** → 0x0e after (`phone/amp-pwrctl-during-tone.py`). No boost/BOP tuning without the regbin | 2026-10-26 19:45 — amp powers on with the stream |
| Audio: WCD9375 / SoundWire (mic) | **Works (2026-10-31)** | LPASS LPI at 0x62b52000 (SSC owns pads 0-17), new sm6150 LPI driver with checked vote clocks, SWRM v1.5.1, WCD937x reset on LPI gpio6 with default-only pinctrl, PDR + built-in pd-mapper. AMIC1 -> MultiMedia2, PulseAudio `violet_mic`. Patches 0029-0032 | 2026-10-31 |
| Audio: mic capture gain | **FIXED 2026-11-02 (accepted by ear at 30 cm and 5 cm)** | Speech was ~14 dB below music because `TX_DEC0` sat at 88 of 124 while `ADC1` was already at its hardware max (0..20). Measured from the user's own Sound Recorder files: -28.2 dBFS @30 cm / -26.9 dBFS close at `DEC0=88`, -14.7 dBFS at `DEC0=100` (peak -6.0 dBFS, 0 clipped samples). Upstream alsa-ucm-conf uses 100 for the TX-macro path. Persisted in `phone/violet-audio-setup` + `/usr/local/bin/violet-audio-setup` | 2026-11-02 |
| Audio: 3.5 mm headphones | **PARTIAL - the 2026-11-05 "works" claim was WRONG (corrected 2026-11-06)** | Working configuration: **MultiMedia4 (hw:0,3)** -> `RX_CODEC_DMA_RX_0` -> rx_macro -> SoundWire RX (`swr1`) -> WCD9375 HPHL/HPHR, verified by ear 2026-11-06 (the tone was heard in the earbud with the speaker route off). **MultiMedia3 (hw:0,2) into the codec-DMA port produces no audio at all** on this stock ADSP firmware, and the speaker only plays from MM3 - so each output needs its own PCM. PulseAudio therefore keeps two sinks (Speaker on hw:0,2, `violet_hph` on hw:0,3) and the jack watcher switches the **default sink** on plug/unplug (no stream moving: that killed the GStreamer player; and running both PCMs at once wedged PulseAudio). Consequence, same as Windows: after a plug/unplug the player must start a new stream (press play). Per-sink volume, headphone ceiling in `/etc/violet-audio.conf`. Companders must stay off. Volume OSD label "Headphones" comes from `device.form_factor=headphone` on `violet_hph` (gsd shows a label only for non-internal form factors; 2026-11-07, see PROGRESS). **2026-11-07: the watcher must also set `RX_HPH PWR Mode`=LOHIFI and `RX HPH Mode`=CLS_H_LOHIFI** (boot default ULP/CLS_H_NORMAL gave feeble, chopped speech; fixed in `phone/violet-jack-watch`, clear and loud by ear). Codec regs readable via the TX slave's `wcd937x_csr` regmap. **Retracted from the earlier entry:** the "mic RMS 8218 = proof of sound" measurement was ambient noise (baseline at that gain is 5-7k), and the "clicks were the compander" conclusion was never isolated - MM3 silence was the real blocker. | 2026-11-06 |
| Remoteprocs | **Works** | ADSP boots; CDSP region set (boot not reported); **MPSS boots and stays up** — see the modem row | 2026-10-26 06:15 — the modem is now alive with 41 QMI services |
| Modem (MPSS) | **Works; first-start fatal FIXED 2026-11-02 by `patches/0038` (1 boot where the race fired, verified)** | Registers on QRTR with **41 QMI services** (NAS, WDS, DMS, UIM, IMS, location, EFS, IPA control, servreg 180) and stays up. Three separate causes of the old "fatal error without message" at 40 s, all fixed: (1) `rmtfs@0` sat at **physical address 0** — the vendor `reg = <0 0x200000>` means *allocate dynamically*, so it is now a real carve-out `rmtfs@a1e00000` (0x280000, `qcom,vmid = MSS_MSA`, client-id 1) and the modem opens `modem_fs1/fs2/fsg`; (2) missing **IPA** firmware/GSI carve-outs (`ipa-fw@97100000`, `ipa-gsi@97110000`) plus the ipa-ap/module smp2p pair — without them the first IPA-enabled modem boot reset the SoC ~16 s after "modem is now up"; (3) `qcs615_domains[]` listed the **same root domain twice**, so every probe returned `-EBUSY` and pd-mapper (QRTR service 64) never registered — one entry per domain now | 2026-10-26 06:15 — the modem is now alive with 41 QMI services | **2026-11-02 (audit review):** the 40 s fatal was NOT closed by the earlier fixes: a boot on #183 showed it twice (69 s and 109 s) and others once at 40.03 s after 'modem is now up'. ROOT CAUSE found with the glink trace: the modem sends one QRTR HELLO right after opening IPCRTR; `qcom_smd_qrtr_callback()` returns -EAGAIN until probe sets drvdata and glink RX_DONEs the packet regardless, so the HELLO is lost (no `hello from 0`, no reply). `patches/0038` queues and replays early packets. `violet-modem`'s retry loop is now only a safety net.
| Sensors (SSC) | **Sensors WORK** (2026-10-30; the camera half of this old row is superseded by the next row) | **Accelerometer, gyroscope, magnetometer, ambient light and proximity all return live values** through the Snapdragon Sensor Core, and `iio-sensor-proxy` exposes them, so Phosh's auto-rotate and auto-brightness work: `ssccli --sensor accelerometer` → `Z=9.90 m/s²` (flat), `--sensor light` → 5 lux, `--sensor magnetometer` → ~188/281/21 µT, `--sensor proximity` → FAR; `monitor-sensor` reports `Has accelerometer` (tilt face-up) and `Has ambient light sensor`. Hardware (from the vendor configs, staged in `fw/sensors/`): ST **LSM6DS3-C** accel+gyro (SSC SPI inst. 2), **AKM AK0991x** mag (SSC I²C inst. 1, 0x0C), **Sensortek STK3x3x** ALS+prox (SSC I²C inst. 1, 0x47) — all on the SSC's buses, so no AP-side iio driver applies. Recipe: `hexagonrpcd` `-f /dev/fastrpc-adsp-secure -d adsp -s -R /usr/local/share/violet-sensors` with the vendor configs plus a **faked Android socinfo** (`sys/devices/soc0/*`, `soc_id=355`) and persist stubs; service in the default runlevel, `phone/install-sensors.sh` reproduces it. No kernel/DT change. Orientation is correct with **no mount-matrix rule** — the SSC already delivers device-frame data; an `ACCEL_MOUNT_MATRIX` rule installed earlier on 2026-10-30 was retracted the same day because it made the UI render upside down (`bottom-up` with the rule vs `normal` without, identical raw accel). | 2026-10-30 |
| Camera (CAMSS/CCI + IMX586 / S5K5E8 / OV13855) | **All three cameras WORK in GNOME Camera (2026-11-03); the front camera's darkness is FIXED (2026-11-04)**: rear main IMX586 (4000x3000, vendor tables, RGGB, vendor CCM tuning), rear aux S5K5E8 (CCI0 @0x18, 1296x972), front OV13855 (CCI1 @0x36, 2112x1568); libcamera soft ISP; no autofocus, lens-shading/gamma not applicable to the soft ISP. The front was starving for light because the driver's VBLANK default rewrote the frame length to 1650 lines (~49 fps), halving the maximum exposure; the vendor 3214-line / 30 fps timing is now the default (signal at the AGC ceiling 16 % -> 33 % of full scale) | IMX586 is SMIA: stream-on `0x0100=0x01`, frame counter `0x0005`, EXTCLK `0x0136/7=0x1800` (24 MHz); real init+5 mode tables recovered from the Ofilm `sensormodule.bin` Chromatix records -> `patches/proposed/imx586-vendor-tables.h`; csiphy0, 4 lanes, link 574 MHz; `imx586.ko` in `/lib/modules/7.2.10-sm6150/extra/`. OV13855: `0x380e` is rewritten from `V4L2_CID_VBLANK` at stream start, so its default must be `0x0c8e-1568` = 1646 (max exposure `VTS-8`); gain saturates at `0x07c0` = 7.75x (writing 0x0f80 adds nothing). Build the module with `CONFIG_VIDEO_OV13855=m` or it compiles without `-DMODULE`. Rear mbus code is `SRGGB10` (video `pRAA`), not `SBGGBR10` - the wrong code fails link validation with `-EPIPE`. (Vendor DT cci-master numbers are wrong - buses were scanned.) | 2026-11-04 (front camera fix) |
| Camera: AF, burst merge, app (from project memory notes, not yet in PROGRESS-derived rows) | **Works on device (2026-11-04)** | `dw9800.ko` VCM subdev + contrast AF (`phone/violet-af.c`), multi-frame raw merge (`tools/camera/vpipe.py`, `phone/violet-shot.py`), "Violet Camera" GTK app with Main/Aux/Selfie, tap-to-focus, vcamd ZSL daemon (install: `phone/install-camera.sh`). Shutter to raw 0.2 s, JPEG 2.4 s (1 frame). Open items are in the Open list above | 2026-11-04 |
| Vibration (haptics) | **Works (2026-11-07, felt by the user)** | `&pm6150_vib { status = "okay"; }`; `pm8xxx_vibrator` binds (pmi632 register set), FF device `/dev/input/event4`; feedbackd theme override at 0.63 / 50 ms (vendor-faithful), Glissando haptics configured. Optional hardening (vib-ldo-volt clamp) not done | 2026-11-07 14:47 |
| Suspend / resume | **WORKS - verified end to end 2026-11-02 (patches 0036 + 0037)** | Hook stops hexagonrpcd and unbinds the USB UDC around sleep: s2idle sleeps and resumes with no ADSP crash. Idle suspend AND a real power-button wake are both tested: `wake_irq=19` = `pm8941_pwrkey` (a ~10 s hold resets the SoC instead of waking it). Older notes: s2idle sleeps (WFI-only idle) and wakes on the RTC. On resume the DSP sensor service crashes the ADSP, which restarts; `patches/0034` fixes the q6dsp clock NULL-deref that used to follow, so the system now recovers (no oops, card + mic back, no wedged fs). Deeper idle states untested; ath10k key removal adds ~3 s; audio playback now holds a *block* inhibitor (patches/0037 - pmOS shipped the `is-alsa-playing` plugin disabled), so a song is no longer cut by idle suspend | 2026-11-02 |
| Charging / power supply | **Works — gauge, charger policy and USB-C PD (9 V/3 A)** | `violet-qg` (`patches/qg/`) replaces `violet-vbat`: vendor LC_M6300 profile picked from the batt-id ADC (68k = ATL, 4015 mAh), real battery temperature, vendor cutoff/full scaling, hold-99/hold-1 and one-point msoc stepping; coulomb counting + OCV rest correction (the vendor estimator is a closed userspace piece, so this part is ours). Discharge test: 0.31 %/min at 0.75 A matches physics, rest OCV agrees within 0.4 point. Charger: input-path sequence re-run on every plug-in with ICL from APSD (SDP 500 / CDP 1.5 A / DCP,float,OCP 1.8 A), `usb` supply, status/health from the charger state machine; JEITA/termination/safety timer are programmed by SBL and left alone. Type-C is enabled sink-only; the Moto 68 W charger negotiates 9 V/3 A (needs `USBIN_ADAPTER_ALLOW_OVERRIDE` = FORCE_9V or the PMIC flags over-voltage and pauses). Cold boot with PD verified. Fast-charge current is temperature-limited (vendor jeita ranges, own 43 C cap), default ceiling 2.0 A; 2.5 A was reached but heats the pack ~1.7 C/min. Not done: sustained 2.5-3 A from a cool pack, ICL above 1.8 A, 15/20 V/PPS, SDP path, switcher frequency, thermal mitigation | 2026-11-08 |
| Lock screen / password | **Works (re-enabled 2026-10-28; needs auth now)** | It had been fully disabled on 10-27. Four gsettings keys plus Phosh's own switch: `lockdown disable-lock-screen=false`, `screensaver lock-enabled=true`, `lock-delay=0`, `session idle-delay=300`, and **`sm.puri.phosh.lockscreen require-unlock=true`** (that one alone let anyone swipe past). Authentication additionally needed a PAM service, which phosh does not ship on Alpine: `/etc/pam.d/phosh-lockscreen` + `/etc/pam.d/phosh` (plain `pam_unix`). Same upstream bug as Arch FS#80192 | 2026-10-28 |
| On-screen keyboard (glissando) | **Works, after fixing a seat race with phosh's own OSK. The "keyboard opens with no text field" bug (GTK 4.24 enable-on-focus) was root-caused and FIXED 2026-11-07 by upgrading phoc 0.57 -> 0.58 (text-input-v3 v2 / show_input_panel); no per-app workarounds remain; a real text field opens the keyboard on touch and it hides on tap-away (confirmed by the user 2026-11-07)** | glissando 0.3.0 at `/usr/local/libexec/glissando/`, launched by `/usr/local/bin/glissando-launch-system` (which also serves the greeter/lock screen). phosh 0.58 starts `/usr/bin/phosh-osk-stevia` from the shell; if it owns the seat first, glissando exits with "another input method is already running on this seat" and the launcher falls back to stevia. Launcher now stops stevia/squeekboard before starting glissando. **phoc must stay >= 0.58**: 0.57 activates the input method on GTK 4.24's enable-on-focus, which is the phantom-keyboard bug | 2026-11-07 |
| Android apps (ATL) | **NewPipe works for regular videos** | Launches from the Phosh grid (needs `X-Purism-FormFactor` in the .desktop file, fixed) in 2-5 s; VOD plays ~95 s+ with audio stream and 0 GPU errors (UI-verified). Live streams die after ~1 min with HTTP 403 (YouTube's integrity check needs an Android WebView). IPv6 on wlan0 is disabled (the router advertises a dead v6 route) | 2026-11-02 |
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

**Audio (details of the original bring-up)**
- ADSP: `&rproc_adsp_mem { reg = <0x0 0x95300000 0x0 0x1e00000>; }` (upstream's 0x95900000 gave -22), `&rproc_cdsp_mem` at 0x93b00000,
  firmware `qcom/qcs615/adsp.mdt` + `adsp.b*`.
- Legacy APR (not AudioReach): q6core/q6afe/q6asm/q6adm; card `qcom,sm8250-sndcard`.
- Amp bus: `&qupv3_id_1` + `&gpi_dma1` + `&i2c4` (`i2c@a80000`, gpio20/21) enabled; the amp at 0x4c probes cleanly.
- Playback FE: `mm3-dai-link` -> `pcmC0D2p` (MM1/MM2 are capture-only on this firmware).
- Routing: `PRI_MI2S_RX Audio Mixer MultiMedia3`, set by numid (`amixer sset` rejects the name).
- `&q6afedai { dai@16 { qcom,sd-lines = <0>; } }` is required, or `fail to prepare AFE port 10`.

**WiFi prerequisites (done; WiFi works, see the summary row)**: RPMh regulator nodes for ldo9 (pm6150) and ldo1/2/10 (pm6150l), always-on; `wifi@18800000` with
4-cell GIC IRQs and SID 0x1640; `wlan_msa_mem@93300000` shrunk to 1 MB; ath10k WCN3990 firmware installed. `ath10k_snoc` probe returns 0.

## Open items (current, synced 2026-11-09 from the docs; not re-tested on the phone)

The October "Broken / open" and "In flight" sections (post-login freeze, speaker-amp PMIC reset, WCD9375 parked, WiFi blocked on modem) were all resolved later and moved to `STATUS-HISTORY-2026-10.md`.

- **Reboot/shutdown freeze**: intermittent CPU stall (2 of ~7 reboots on 2026-11-02, later 3 of 3 clean); not root-caused.
- **No hardlockup/NMI detection; APSS watchdog has no mainline driver** (disabled via `wdt-disable.py`).
- **Camera**: no libcamera sensor helper for IMX586; colour/CCM/lens-shading calibration, dark-scene AF, aux/front orientation, speed and outdoor raw validation open; the patched libcamera is not used by the desktop (see `HANDOFF-2026-11-04-camera.md`).
- **Charging**: SDP (500 mA) path never exercised; few-second charge pause at boot; sustained 2.5-3 A from a cool pack, ICL > 1.8 A, 15/20 V/PPS, thermal mitigation not done.
- **Audio**: headphones need a new stream after plug/unplug (two PCMs, MM3 speaker / MM4 jack); TAS2563 in ROM mode (no calibration, no speaker protection; regbin exists in no vendor image); patch 0044 (q6routing) status not recorded.
- **Android apps**: NewPipe live streams 403 (no WebView).
- **Modem/telephony**: modem and QMI services are up; calls/SMS/mobile data are not mentioned anywhere in the docs (unknown).
- **Lost in the 2026-11-03 userdata wipe, not restored**: `tas2563_coef.bin`, screenshot-keys service, some gsettings, personal data.
- **Hacks still carried**: see the Fix-quality audit below (`aggre1_noc` clocks deleted, panel init blob, dsi_phy magic values, hexagonrpcd stop hook).
- **Not upstream-shaped**: see the next section; nothing is committed anywhere (no git repo).

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

## 2026-11-02 15:45 IST — plan items 3 and 4 closed; fix-quality audit

- **Item 4 (suspend/resume) verified.** Full elogind cycle: `PM: suspend entry`, `failed to enable ep0out`
  (kernel bug, unchanged), `PM: suspend exit`, repair rebind → USB shell back ~7 s later, ADSP running,
  wlan associated, `wake_irq=19` = `pm8941_pwrkey` on a short press (a 10 s hold resets the SoC instead).
- **Item 4 catch:** the phone *did* suspend ~65 s into a song. pmOS ships a `sleep_inhibitor` plugin for
  this (`is-alsa-playing`) but `/etc/sleep-inhibitor.conf` enables only `ssh-session-open` and
  `apk-running`. Enabled it (`patches/0037`); with a 60 s idle timeout and 150 s of playback, zero suspends.
- **Item 3 (recording gain) fixed and accepted by ear** (user checked 30 cm and 5 cm). `ADC1` was already at
  its hardware max (0..20); `TX_DEC0` is the only knob (0..124, 1 dB/step). Measured from the user's own
  Sound Recorder files at `DEC0=88`: speech −28.2 dBFS @30 cm, −26.9 dBFS close, vs −13.8 dBFS for music —
  ~14 dB quiet, exactly the complaint. `DEC0` 88 → **100** (+12 dB, upstream alsa-ucm-conf's value) puts
  speech at music level; persisted in `phone/violet-audio-setup` and `/usr/local/bin/violet-audio-setup`.
- **Harness lessons (both cost a false result):** `gsettings` and `paplay` must run as the login user, not
  root (dconf refuses, PulseAudio auth fails); and busybox `find` on violet **silently ignores
  `-newermt`**, so every mtime-filtered search returned nothing. Sound Recorder writes FLAC stereo 44.1 kHz
  to `~/.local/share/org.gnome.SoundRecorder/Recording N` (not `~/Music`). `grim` is a **0-byte binary**
  on the device, so no screenshots.
- **Fix-quality audit** (the user asked which of our changes are fixes and which are hacks) — recorded
  below as a table so the distinction does not get lost: 11 real fixes, 6 sanctioned workarounds,
  7 hacks, 1 untrustworthy component, 5 open problems.

## Fix-quality audit (2026-11-02)

Criterion used: a **fix** makes the wrong state impossible (right value / right ordering / right
ownership) and survives the next upgrade; a **hack** repairs the state after the failure or avoids the
path that fails, and will fight any upstream fix.

| Verdict | Items |
|---|---|
| **Real fixes** (13) | `0039` dwc3-qcom reselect UTMI clock on resume; `0038` qrtr-smd early packets (modem first-start fatal); `0015` (cleaned); `0017` SMMU hyp-owned CBs 10-12; `0024`+`0025` dispcc MDSS_CORE reset + pclk0 parent-enable (matches upstream sm7150/sm6115); `0029` lpass-lpi checked clocks + SM6150 variant; `0002` tzmem blacklist (same as sm7150/sm8150/sdm845); `0003` ACV enable_mask; `0030` q6afe-clocks defer until AFE answers (polls a harmless request for up to 10 s - sound but polling, not a readiness signal); `0031` wcd937x cansleep reset; `0034` q6dsp-lpass-clocks `dev_set_drvdata` ordering; `0028` msm_gpu_submit runtime-resume check; backlight `num-strings=<2>`; rmtfs carve-out at 0xa1e00000 + IPA carve-outs + one-entry-per-domain (modem); `patches/0037` sleep-inhibitor plugin. |
| **Cleaned 2026-11-02** | `0015` ath10k BSS-peer-before-station-vdev (ath11k QCA6390 has the same ordering rule): all `violet_*` knobs, retries, placeholder SSID and hexdump removed; #184 associates fine. Moved to real fixes. `0012`: dead code removed. |
| **Firmware quirk, upstream-pending** | `0010` ath10k skip quiet mode on WCN3990 (same patch is on the ath10k list, March 2026, not merged). |
| **Right value, wrong packaging** | `TX_DEC0=100` (belongs in a UCM `HiFi.conf`, currently a shell script that also loads PulseAudio modules by hand); `/etc/pam.d/phosh*` (belongs in the pmOS package); SMB5 `USBIN_MODE_CHG` init (belongs in the smb5 driver). |
| **Sanctioned workarounds** (6) | `0018` TAS2563 ROM mode (the RCA regbin exists in no vendor image); stop `hexagonrpcd` around suspend (pmaports does the same for sargo, MR 5400); glissando killing phosh's stevia (seat race); `dtbo` erased (ABL cannot apply the stock overlay to our DTB); UART/netconsole as panic channel; IPv6 off on wlan0 (router advertises a dead v6 route). |
| **Hacks** (10) | (`0012` glink dead code `tx_with_rcid`/`violet_intent_req_reuse` REMOVED 2026-11-02, #184 boots fine); `0005` spmi stale-IRQ ack (kexec-only, inline block); (`violet-udc-repair` REMOVED 2026-11-02: root cause was the lost QSCRATCH UTMI-clock select, fixed by `0039`); the hook's ADSP protection (bypass it — e.g. a sysfs suspend — and the ADSP is dead until reboot); `&aggre1_noc { /delete-property/ clocks; }` (dodges hung QoS writes by removing the clocks; STILL OPEN: upstream has a QCS615 QoS series that adds four aggre1 AXI clocks to the node (UFS PHY, USB2 SEC, USB3 PRIM, RPMH IPA) - not tested here, a wrong guess hangs the boot; sc7280 precedent: some firmware blocks the QoS region and the clocks are deleted on purpose); (`novatek-nvt-ts.c` poll REPLACED 2026-11-02 by a DRM panel follower, patch `0040`; touch confirmed by the user on #187, 2026-11-02); panel init as a 325-byte vendor blob in a separate `nt36672e` driver instead of data in `nt36672a.c`; dsi_phy 14nm magic values (LDO 0x1c, ICP 0x3f, HS_TIMER_CTRL 0x3fd08); (`0016` knobs REMOVED 2026-11-02, `0005` kexec-only patch dropped). |
| **Do not trust yet** | `violet-qg` charger side beyond 9 V/1.8 A: the SDP (500 mA) branch has never run (every source read as float/OCP), fast-charge current is unmeasured, and there is a few-second charge pause at boot before the module loads. |
| **Open (no fix at all)** | Reboot/shutdown freeze (intermittent CPU stall, 2 of ~7 reboots); hardlockup/NMI unusable; APSS watchdog has no mainline driver; (camera was started on 2026-11-03, see the camera rows); NewPipe live streams 403. |

## 2026-11-02 13:35 IST — shutdown hang: not a service stop; CPU stall family; suspend kills the USB gadget

- **Reboot/shutdown hang (plan item 1):** the frozen boot's ramoops (`build #183`) ends in a **CPU stall**,
  not a blocked service: CPU1 stops answering IPIs 0.02 s after `stopped remote processor modem`,
  RCU stall 21 s later, `kick_all_cpus_sync` softlockup in a BPF-free workqueue, panic, then a hang at
  `SMP: failed to stop secondary CPUs 1`. Same family as the 2026-10-24/25 analysis; the `cleanup_irq`
  mask patch is in #183 and that boot logged **zero** `cleanup_irq` lines.
- **Killed suspects:** `hexagonrpcd-adsp-sensorspd` stop returns in 2 s; an isolated `violet-modem` stop
  with ath10k live is clean for 90 s; both clean reboots unmounted all 4 filesystems.
- **Suspend (plan item 4) is half the story and is now reproducible:** after `s2idle` resume, dwc3 logs
  `failed to enable ep0out` and `/sys/class/udc/a600000.usb/state` = `not attached` while configfs still
  binds the gadget — **USB is dead until reboot, WiFi still works**. Cause is the elogind hook's rebind
  step. A reboot from that state still completed cleanly, so the gadget bug does not by itself explain
  the shutdown freeze.
- **Instrumentation:** `rc_logger` is inert on OpenRC 0.63.2 (file stays 0 bytes) — do not plan around
  `/var/log/rc.log`. The 2 s synced `dmesg` harvester on ext4 does survive resets. `/dev/watchdog0`
  (`qcom_wdt`, 30 s, no MAGICCLOSE) can be armed to make a frozen shutdown self-reset.
- **3 of 3 reboots clean today** (19 s, 19 s, ~30 s) with suspend/idle-suspend off; freeze not reproduced.
  Next: a working OpenRC stage trace, then catch the freeze.
