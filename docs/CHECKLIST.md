# violet mainline — checklist (audio, WiFi, native boot)

Written 2026-10-25 ~11:45 IST by the Hermes session, taking over from the Claude session that ran into its
token limit right after the three research agents finished. Sources: `docs/STATUS.md`, `docs/RULED-OUT.md`,
`docs/PROGRESS.md`, and the three research notes in
`~/.config/Claude/side-session-notes/local_0be438d6-ef0e-4226-ae8a-32118a1456a6/`
(`research-abl.md`, `research-audio.md`, `research-wifi.md`; tags there are [src]=read in source,
[inf]=inferred, [web]=web source).

Each step: **why** / **how to test** / **expected** / **source**. Cheapest first inside each section.
Nothing here re-tests something `RULED-OUT.md` already killed.

Test tags: log to `kexec-<tag>.log`, `login-<tag>-dmesg.txt` as the existing scripts do; record the result in
`docs/PROGRESS.md` with the real wall-clock time from `date`.

Coordination before any device action: no other session mid-test (`ls -la --time-style=+%H:%M kexec-*.log
login-*.txt`), `uname -r` starts `4.14` for kexec, and only `boot` may be flashed without an explicit OK.
**Touching `dtbo` needs the user's explicit OK** (step N1).

---

## 1. Native boot (ABL) — cheapest, highest probability, unblocks everyone

State: ABL accepts our kernel and refuses our DTB, drops to fastboot in ~10 s (`STATUS.md`). ABL is *not*
failing to match us: while a valid dtbo is present it must apply the stock board overlay to our base DTB, and
that overlay does not apply to a mainline base (we measured `fdtoverlay` → `FDT_ERR_BADOVERLAY`).
`RULED-OUT.md` has already killed: PE/header-v2 details, msm-id/board-id identity, AVB, an applyable dtbo,
`__symbols__`, vendor node names, clearing the BCB, reading imem.

- [x] **N1 — `fastboot erase dtbo`, then flash our current boot.img.** — **DONE 2026-10-25 11:56, WORKS.**
  Rebooted once more from mainline at 12:02 and it came back up as `7.2.10-sm6150` from ABL again, so this is the
  persistent path, not a one-shot. `androidboot.dtb_idx=-1347440721` in `/proc/cmdline` is the fingerprint.
  **`dtbo` stays erased** — reflashing `dtbo-vendor.img` re-arms the overlay path and brings the refusal back.
  - **Why:** with *no valid dtbo*, ABL takes the legacy `DeviceTreeAppended()` path; if exactly one valid FDT is
    appended it is used **without any ID match**, and no overlay is applied at all. This is the one path that
    bypasses the failure we can actually see. Community practice for ABL-era devices and the upstream U-Boot
    Qualcomm doc both say "erase dtbo to avoid conflicts with our DTB". [src: `research-abl.md` §1a/§4.1]
  - **How:** rebuild the image first (current `boot-mainline.img` is 10-24 16:43, tree Image is 10-25 11:15):
    `./mk-bootimg.sh`, then `fastboot erase dtbo && fastboot flash boot boot-mainline.img && fastboot reboot`.
    Recovery: `fastboot flash dtbo dtbo-vendor.img` (8 MB, local copy) — dtbo is not needed by our kernel.
  - **Expected:** mainline boots with no kexec; `uname -r` = 7.2.10 straight from ABL. Refusal still returns to
    fastboot in ~10 s, so the iteration is safe.
  - **Risk:** AVB has to tolerate a missing dtbo. Unlocked bootloader on this device has tolerated every other
    partition change; if the slot refuses, N2 with the stock dtbo restored.

- [ ] **N2 — header v0 `Image.gz-dtb`, dtbo still erased.**
  - **Why:** violet's own LineageOS `BoardConfig.mk` builds header v0 with `--base 0x80000000 --kernel_offset
    0x8000 --ramdisk_offset 0x01000000 --tags_offset 0x100 --pagesize 4096`, separate 8 MB dtbo. Our image is
    header v2 + standalone DTB. This is the last untested format (explicitly *not* ruled out). [src: PROGRESS
    "GPU + ABL: research corrections"]
  - **How:** gzip Image + concatenate DTB, `mkbootimg --header_version 0 --base 0x80000000 …`, flash boot only.
  - **Expected:** if the refusal was format-dependent, this boots; otherwise go to N3.

- [ ] **N3 — UART capture of ABL's own error string.**
  - **Why:** ends the guessing. ABL prints a specific message per failure (`"No match found for Soc Dtb type"`,
    `"Unable to find the Board Dtb"`, `"ApplyOverlay: ufdt apply overlay failed"`, `"Device Tree update
    failed"` …). Reading the repaired panel is closed; UART at 115200 on ttyMSM0 is the only channel left.
    [src: `research-abl.md` §1]
  - **How:** USB-UART on the phone's debug pads / a pogo or test-point rig, capture from power-on through the
    fastboot drop, 115200 8N1.
  - **Expected:** one of the strings above, which names the exact branch and therefore the exact fix.

- [ ] **N4 — (alternative, no dtbo erase) make `DtboNeed = FALSE`.**
  - **Why:** if the base DTB matches SOC + VARIANT + SUBTYPE_EXACT + FOUNDRYID_EXACT + PMIC_EXACT_MODEL_IDX0/IDX1,
    ABL never reads the dtbo at all. Needs `qcom,pmic-id` with the real PM6150/PM6150L model numbers — the vendor
    DTB has no `pmic-id`, so this is not proven necessary, only available. [src: `research-abl.md` §1a step 2, §4.2]
  - **How:** read the models on r10 (`/sys/bus/soc/devices/soc0/*`, `/sys/devices/soc0`) or from the vendor
    kernel's SPMI probe log, then `fdtput -t x <dtb> / qcom,pmic-id <p0> <p1> 0 0` in `mk-bootimg.sh`.

---

## 2. Audio (TAS2563 speaker amp)

> **STATUS 2026-10-28 (read this first): A1, A2, A3, A4 and A6 are SUPERSEDED — do not re-run them.**
> The reset this section was written to explain turned out to be the TAS2562 driver (A1 verdict, 10-25), and
> the audio path now **works**: card 0 = `Xiaomi Redmi Note 7 Pro`, playback PCM `MultiMedia3` exists, and a
> tone was *heard by ear* on 2026-10-26 after the SMMU fix (context banks 10–12 are hypervisor-owned; stream
> `0x1721` now translates). See `docs/STATUS.md` rows "Audio: ADSP / APR / PCM" (Works) and
> "Audio: speaker amp (TAS2563)" (Blocked).
> **The only open audio item is A5 — the amp DSP config.** Verified 2026-10-28 on the device and in
> `~/violet-rom-extract/vendor.img`: `/lib/firmware` has `tas2563_coef.bin`, `tas2563_uCDSP.bin`,
> `tasdev-codec_coef.bin`, and `persist/audio/tas2563_cal.bin` (440 B); the vendor ROM's `/firmware`
> contains only `tas2563_uCDSP.bin` — **`tas2563RCA1.bin` exists nowhere in the ROM**, so A5 is not a
> copy-a-file job; it needs the TI DSP config sourced properly (or the driver's expected name pinned from
> source). Without it `tasdevice_startup()` returns `-EINVAL`, the amp stays in software shutdown and the
> speaker is silent even though the path is fine.
> A0 (ramoops/record-size) is still worth doing, but for *session crash* evidence (see §5), not audio.

Historical state (10-25): card + playback PCM (MM3) + AFE port prepare all work; starting the stream hard-resets the PMIC ("Triggered
from Hard Reset"), even with `panic=0`, `WDT=off`, amp gain 0. **AFE vs amp has never been separated** — that is
the whole job. Amp: `ti,tas2563` at 0x4c on `i2c@a80000`, reset gpio22, irq gpio117 (vendor); vendor sets
`asi-format 0` (I2S), slots left 0 / right 1, and `rx-lines = <1>` (SD0, matches our `qcom,sd-lines = <0>`).

Two facts that change the picture, from `research-audio.md`:
1. `tas2781-i2c.c` **never powers the boost in probe** — power-up is only in the DAPM event and in the firmware
   config. Worse, `tasdevice_startup()` returns `-EINVAL` unless `tas2563RCA1.bin` loaded, so with the driver
   switched and no RCA bin the stream should fail at *open* with the amp never powered. That means **prof51's
   "no USB for 3 min" is not evidence about the amp**: `kexec-prof51.log` only contains
   `Cannot find device "enp0s20f0u4"` and the console file holds one failed ssh — the phone never enumerated, so
   prof51 says nothing about whether the reset still happens. [src: comlib-i2c.c:311,348-357, i2c.c:1625-1830]
2. The `Unknown cmd 0x100f4` (LPASS core/HW vote) answer from this ADSP firmware is the other suspect: an AFE
   port start without a working clock/vote is an unclocked LPAIF access → NoC/XPU fault → TZ reset, which is
   exactly a PMIC "hard reset" that bypasses `panic=0` and the APSS watchdog. [inf, strongest]

- [ ] **A0 — instrument the test harness, 5 min, no build.**
  - **Why:** every audio conclusion so far came from "the phone did not come back", which the above shows is
    ambiguous (no boot vs no USB vs reset). Make the next result unambiguous.
  - **How:** enable `record-size = <0x100000>;` in `ramoops@a1600000` (shrink `console-size` to fit, the
    contradiction note in `STATUS.md` already specifies this), and read the PMIC PON reason on the next r10 boot
    (`/sys/class/power_supply/*/…` or the vendor `qpnp-power-on` reason string) — "Hard Reset" vs "UVLO" vs
    "KPDPWR" separates an AFE fault from an amp brownout.
  - **Expected:** after any audio reset, `console-ramoops-0` survives and states how far the stream got, and the
    PON reason names hard-reset vs UVLO. This single step converts guesswork into data.

- [x] **A1 — amp absent, stream the codec-less BE.** — **DONE 2026-10-25 12:55, verdict: no reset.**
  Streaming MM3 → `PRI_MI2S_RX` with `ti,tas2563`/`tas2781-i2c.c` (and no RCA firmware, so the amp is never
  powered) fails cleanly with `AFE set params failed -110` at `set_sysclk` and `tasdev_codec` `-22` at
  `snd_soc_dai_startup`. The PMIC hard reset is gone, so it was the TAS2562 driver after all. The AFE vote/clock
  path is now the first blocker (A6), and `tas2563RCA1.bin` the second (A5). Note: disabling the amp node is *not*
  a usable way to take it out of the path — the card then fails to register and no PCM exists.
  - **Why:** separates AFE/LPASS from the amp. If the AFE port start alone resets the SoC, the amp is innocent and
    A5–A7 are wasted effort until the clock path is fixed.
  - **How:** DTB: keep the amp node but `status = "disabled"` (or hold gpio22 low); disable pipewire/wireplumber
    autostart so boot cannot open a stream; then `aplay` to the codec-less **Debug Playback (SECONDARY_MI2S_RX)**
    with routing set by numid.
  - **Expected:** no reset → the amp *is* the reset source (go A5). Reset → AFE/clock/vote (go A2, then A8).
  - **Source:** `research-audio.md` §4.1.

- [ ] **A2 — add MI2S pinctrl to the sound node, re-run A1 on PRIMARY_MI2S_RX with the amp held in reset.**
  - **Why:** our sound node has **no** `pinctrl-0` at all, so gpio108-111 are not muxed to `mi2s_1`; talos-evk
    does `pinctrl-0 = <&mi2s1_pins>, <&mi2s_mclk>` on the sound node and `talos.dtsi` already defines
    `mi2s1_pins` (gpio108-111, func `mi2s_1`, drive 8, bias-disable). Driving audio pins that are still in GPIO
    mode is a plausible route to a fault. [src: talos-evk.dts:44-82, talos.dtsi:1661]
  - **How:** add `pinctrl-0 = <&mi2s1_pins>;` to the sound node (leave `mi2s_mclk` out — a TAS2563 clocks from
    BCLK, and gpio122/mclk2 may be unsupported here), `make dtbs`, kexec as `a-pinctrl`.
  - **Expected:** if A1 reset and A2 does not, the pins were it. Silence but no reset = normal (no codec linked).
  - **Source:** `research-audio.md` §2, §4.2.

- [ ] **A3 — bring the amp out of reset with no stream; verify it answers.**
  - **Why:** confirms bus + `ti,tas2563` bind without any boost, and gives the baseline register values the later
    steps need.
  - **How:** `compatible = "ti,tas2563"`, `reset-gpios = <&tlmm 22 GPIO_ACTIVE_HIGH>` (correct polarity: the
    driver ends low→high, i.e. NRST released), modules already built; then `i2cget -y 4 0x4c 0x02`.
  - **Expected:** probe clean, `PWR_CTL (0x02) = 0x0e` = shutdown. Note `tasdevice_startup` will still fail
    `-EINVAL` for playback (no RCA firmware) — that is expected and safe here.
  - **Source:** `research-audio.md` §1, §4.3.

- [ ] **A4 — stream with the amp held in software shutdown (PWR_CTL = 0x02, mode 10).**
  - **Why:** delivers BCLK/LRCLK to the amp with the boost explicitly off. Isolates amp *power* from amp *data*.
  - **How:** `i2cset -y 4 0x4c 0x02 0x02` before starting the stream.
  - **Expected:** no reset, no sound. A reset here means the boost is not the culprit and A8 applies.

- [x] **A5 — firmware before first audible stream.** — **RESOLVED 2026-10-26, re-verified 2026-10-28: not needed.** The RCA regbin is not shipped by any vendor image; `patches/0018` runs the amp in ROM mode (`no_rca_mode=2`, boot-wired), the speaker is audible, and PWR_CTL goes 0x0e idle → 0x0c while streaming → 0x0e after. See STATUS.md.
  - **Why:** the vendor never powers the amp on ROM defaults: boost, BOP and limiter all come from the firmware
    blobs, and `tasdevice_startup` refuses to start without the RCA bin. Streaming without them is how a brownout
    would be produced.
  - **How:** (a) `tas2563RCA1.bin` is a TI "regbin" made from a PPC3 register JSON with TI's regbin tool — not in
    linux-firmware; needs either the vendor ROM's copy or a generated one. (b) try the vendor blob
    `~/violet-pmos/kernel/sound/soc/codecs/tas2563/tas2563_uCDSP.bin` (28871 B, magic `5552`, ppcver 0x8a00) as
    `tas2563_coef.bin`. Drop both in `/lib/firmware/`, mode MUTE (0x01) → ACTIVE.
  - **Expected:** `fw_state` reaches RCA_OK/DSP_OK, startup stops returning `-EINVAL`, amp reaches ACTIVE with
    vendor boost settings, tone audible (`audio-test.sh 440` / `tone440.wav`).
  - **Source:** `research-audio.md` §1, §3, §4.5.

- [ ] **A6 — if A1/A4 still reset: the clock/vote path.**
  - **Why:** `sm8250.c` (our card driver) sets only `PRI_MI2S_IBIT` 1.536 MHz, ignores the return codes, sets no
    MCLK, and sets neither `DAIFMT_I2S` nor an inversion; `sdm845.c` additionally requests `MCLK_1` 24.576 MHz
    behind a refcount. Our ADSP answered `Unknown cmd 0x100f4` to the LPASS core/HW vote request. [src:
    `research-audio.md` §2]
  - **How:** log the `q6afe` clock-set response codes (`AFE_PARAM_ID_CLOCK_SET` 0x10290 vs `LPAIF_CLK_CONFIG`
    0x10238), then try the sdm845-style MCLK_1+IBIT pair, and/or try `qcom,sd-lines = <1>` if the pins turn out
    to be wired to SD1. [inf]

---

## 3. WiFi (WCN3990 / ath10k) — needs MPSS (the modem)

> **STATUS 2026-10-28: WORKS — W1–W6 are done and W7 is optional polish, not a blocker.** Live evidence
> from the device: `wlan0 UP <phone-ip>/24`, associated to `<home-ap-ssid>`, `-82 dBm`, 18 Mbit/s rx, and this
> whole session has been driven over that link (SSH/SCP). AP mode works too. Fix = `patches/0015`
> (create the BSS peer before station vdev start). `STATUS.md` row "WiFi (WCN3990 / ath10k)" = Works.
> W7 (packing `bdwlan.*` with `ath10k-bdencoder` + `qcom,calibration-variant`) would only improve
> calibration/sensitivity on the weak link; it is not needed for WiFi to function and needs a DT change
> (flash) to test.

> **2026-10-26 07:30 — DONE on the kexec path (Claude session).** wlan0 comes up by itself, NetworkManager scans and lists APs. What it took, beyond W1–W7 below:
> rmtfs carve-out at a real address, IPA node + carve-outs, pd-mapper table fix, no `msa-fixed-perm`, violet's own board data, the ath10k quiet-mode guard, `/etc/mainline-stay`, and an
> autostart service (see PROGRESS "2026-10-26 07:00" and "07:30"). Remaining: associate with a real network, stable MAC, native boot.


State: `ath10k_snoc` probes and returns 0, then waits forever for `WLFW_FW_READY_IND`. The WLAN coprocessor is
started by **MPSS** (`wlanmdsp.mbn` served through tqftpserv), and talos/violet have no MPSS node, no smp2p for
the modem, and no QRTR. WiFi has never worked on violet in pmOS on any kernel. This is a modem bring-up project,
not a WiFi one.

- [x] **W1 — kernel: give qcs615 an MSS power domain.**
  - **Why:** the vendor modem node votes `vdd_mss` (pm6150l S7, `mss.lvl`) and `qcom_pas_pds_attach()` fails probe
    with `-ENODATA` if any listed pd name is missing. `qcs615_rpmhpds` currently exposes only CX/CX_AO, so
    `power-domains = <&rpmhpd RPMHPD_CX>, <&rpmhpd RPMHPD_MSS>` cannot work without this. [src:
    `research-wifi.md` §1]
  - **How:** in `drivers/pmdomain/qcom/rpmhpd.c`, `qcs615_rpmhpds[]`: add `[RPMHPD_MSS] = &mss,` (the `mss`
    descriptor already exists, `res_name = "mss.lvl"`; `RPMHPD_MSS` = 12). ~25 min Image relink.
  - **Expected:** probe no longer fails `-ENODATA`; `mss.lvl` appears in the regulator/PD summary.

- [x] **W2 — DT: smp2p-mpss + `remoteproc@4080000` (PAS, `qcom,sm8150-mpss-pas`).**
  - **Why:** vendor loads the modem through TZ PAS (`qcom,pil-tz-generic`, `pas-id 4`, smem crash id 421,
    sysmon 0, minidump 3, ssctl 0x12, CX+MSS rails) — that is field-for-field `mpss_resource_init`, which
    `qcom,sm8150-mpss-pas` selects. No MBA/`q6v5-mss` needed, and TZ authenticates the signed `modem.mdt`
    exactly as stock does. [src: sm6150.dtsi:2422-2468, qcom_q6v5_pas.c:1315-1330]
  - **How:** paste the draft DT from `research-wifi.md` (§"Draft DT"): `smp2p-mpss` (smem 435/428, `mboxes =
    <&apss_shared 14>`, remote-pid 1, entries master-kernel/slave-kernel), `remoteproc_mpss` (GIC_SPI 266 wdog +
    smp2p in 0/1/2/3/7, `clocks = <&rpmhcc RPMH_CXO_CLK>`, `memory-region = <&pil_modem_mem>`,
    `qcom,qmp = <&aoss_qmp>`, `firmware-name = "qcom/qcs615/modem.mdt"`), and a `glink-edge` (GIC_SPI 449,
    `mboxes = <&apss_shared 12>`, label "modem").
  - **Expected:** with no firmware present yet, probe succeeds and `state` is `offline` — that is already a win
    and safe (nothing is started).

- [x] **W3 — fix the modem/MSA memory map before starting it.**
  - **Why:** violet's real map (`dt/ref/violet-sm6150-memory.dtsi`) is `pil_modem_mem 0x8b000000+0x7e00000`,
    `video 0x92e00000`, `wlan_msa 0x93300000+0x200000`. Our DTS shrank MSA to 1 MB only because talos'
    `pil-video@93400000` is still present, and `modem_region@8b000000` has no label. A wrong region means TZ auth
    `-EINVAL` or an XPU violation that resets the whole SoC. [src: `research-wifi.md` §3]
  - **How:** delete talos' `pil-video@93400000`, restore the 2 MB MSA, add `pil_modem_mem:` to
    `modem_region@8b000000`.
  - **Expected:** `qcom_scm_pas_auth_and_reset` gets past authentication when W6 starts the modem.

- [x] **W4 — firmware in the right place.**
  - **Why:** tqftpserv strips `/readonly/firmware/image/` and retries under the remoteproc firmware's *dirname*,
    so `qcom/qcs615/` (same dir as `adsp.mdt`) is the correct home for `modem.mdt` + `modem.b*` and
    `wlanmdsp.mbn`. [src: tqftpserv translate.c; `research-wifi.md` §4]
  - **How:** pull from the vendor `firmware` partition or the r9 rootfs, install to `/lib/firmware/qcom/qcs615/`.
    Check first — `modem.*` may already be on the phone.

- [x] **W5 — rmtfs shared memory address (needs r10, 2 min).**
  - **Why:** the vendor allocates rmtfs dynamically (`qcom,sharedmem-uio`, client-id 1, guard-memory), so no
    address is in any DT. Without rmtfs the modem runs a while then dies on EFS. [src: `research-wifi.md` §3]
  - **How:** on r10: `cat /sys/class/uio/uio*/maps/map0/addr` and `name` (look for the rmtfs entry), then add
    `qcom,rmtfs-mem` with `reg = <0 0x<addr-0x1000> 0 0x202000>`, `qcom,client-id = <1>`,
    `qcom,use-guard-pages`, `qcom,vmid = <QCOM_SCM_VMID_MSS_MSA>` (Fairphone 4 pattern).
  - **Expected:** `rmtfs` opens `/dev/qcom_rmtfs_mem1` without an XPU fault.

- [x] **W6 — start it: rmtfs → tqftpserv → remoteproc.**
  - **How:** `rmtfs -r -P -s` (needs modemst1/modemst2/fsg/fsc via `/dev/disk/by-partlabel`), `tqftpserv`,
    `pd-mapper` (or `CONFIG_QCOM_PD_MAPPER`), then `echo start > /sys/class/remoteproc/remoteprocN/state`, then
    `echo start > /sys/class/remoteproc/remoteprocM/state` for the WLAN part **after** QRTR shows up.
  - **Expected:** `qrtr-lookup` lists WLFW + IPCRTR; ath10k gets `WLFW_FW_READY_IND` and creates `wlan0`.
  - **Risk:** a modem NoC/XPU fault can reset the whole phone — keep SSR recovery enabled and ramoops configured
    (A0). Do not do this while another subsystem experiment is running.

- [ ] **W7 — board data last.**
  - **Why:** the installed `board-2.bin` is generic linux-firmware and has no violet/Xiaomi-sm6150 entry, so even
    with WLFW up, calibration fails. [src: `research-wifi.md` §4]
  - **How:** pack the vendor `bdwlan.*` with `ath10k-bdencoder` as
    `bus=snoc,qmi-board-id=<id>,qmi-chip-id=<id>,variant=xiaomi_violet` (ids appear in dmesg once QMI works) and
    set `qcom,calibration-variant = "xiaomi_violet"`.

---

## 4. What remains (rewritten 2026-10-29 — the old "Order" list below §3a is history, not a plan)

**Done, do not redo:** native ABL boot (N1) · audio path + speaker amp (A1–A6, `patches/0015`–`0018`) · WiFi
associate/DHCP/AP (`patches/0015`, W1–W6) · ATL installed and running real apps · lock screen with password.

**Open, and whether it needs the USB cable:**

| # | Item | Where | Cable? |
|---|---|---|---|
| G1 | **GPU lockups** — 9 `hangcheck detected gpu lockup rb 0` in 35 min (2026-10-29) killing `phoc`, `gnome-control-center`, ATL; follows long GPU suspend (active 1.8 h vs suspended 7.5 h). Fix = a6xx power-up/resume path | kernel (`drivers/gpu/drm/msm/adreno`) | **yes** (flash per iteration) |
| S6 | dmesg flooded by `qcom_q6v5_pas … Handover signaled` (~94% of the ring), which is why crash evidence keeps rotating away | kernel | **yes** |
| M1 | Microphone — WCD937x/SoundWire parked on `MASTER_CLASH_DET`; codec reset is LPI gpio24, not TLMM 24 | DT | **yes** |
| A0 | `ramoops` record-size — pstore is empty after crashes, so there is no cross-reboot evidence | DT | **yes** |
| P1 | Suspend/resume — only `s2idle` exists and the phone does not come back; currently masked three ways | kernel/DT | **yes** |
| X1 | Sensors — behind the Snapdragon Sensor Core; QRTR service 400 is alive but no registry; mainline has no SSC/CHRE driver (see §6) | kernel/DT (+ maybe userspace) | **yes** |
| W7 | `bdwlan.*` packing + `qcom,calibration-variant` — sensitivity polish only, WiFi already works | DT | yes |
| T1 | Two UI checks the user can do without me: tap a text field (keyboard on focus), lock the phone (lock screen shows glissando, password prompt) | — | no |

**Cheap WiFi-only follow-ups:** finish the ATL app trial (only the GPU lockup blocks video), and try the GPU pin
(`power/control=on` on `card0`/`5000000.gpu`/`506d000.gmu`, done manually 07:30 on 2026-10-29) as a holding
measure — it had 0 hangs in the first 7 min where the previous rate was ~1 per 100 s.

---
## 5. Session stability — "Oh no! Something has gone wrong" (started 2026-10-28)

Symptom: Phosh session dies to a full-screen `gnome-session-failed` page ("Please log out and try again"),
observed several times around the glissando keyboard work.

**A. Root cause, measured (not assumed).** `sm.puri.OSK0` is a `RequiredComponent` in
`/usr/share/gnome-session/sessions/phosh.session`, but the dialog appeared while **every** session
process was alive (`phoc`, `phosh`, `gnome-session-binary`, `glissando` owning `sm.puri.OSK0`), so no
component had exited. The last thing written to the session console (`/dev/vcs7`, since gnome-session's
stdout goes to `/dev/tty7`) was
`Failed to activate service 'org.freedesktop.secrets': timed out (service_start_timeout=120000ms)`.
Chain: a **stale `gnome-keyring-daemon --daemonize --login`** (pid 3715, from the 07:02 session) held
`/run/user/10000/keyring/control`; the next session's daemon printed `discover_other_daemon: 1` and
exited instead of serving the bus, so `org.freedesktop.secrets` never appeared → 120 s activation
timeout → gnome-session phase timeout → failure page.
*Proved both directions:* before = `discover_other_daemon: 1` + exit + no name owner; after killing the
daemon and `rm -rf /run/user/10000/keyring` = `discover_other_daemon: 0` + `uint32 <pid>` owns
`org.freedesktop.secrets`.

- [x] **S1 — reap stale session daemons.** `phone/kill-stale-session-procs.sh` (has `--dry-run`):
      discriminates on `DBUS_SESSION_BUS_ADDRESS` ≠ current, plus keyring/session-dbus daemons that
      cannot serve the current bus; removes the stale `keyring/` socket dir afterwards.
  - **Test:** `socat`/`dbus-send … GetConnectionUnixProcessID string:org.freedesktop.secrets` → must
    return a pid; `pgrep -x gnome-keyring-daemon` → exactly one.
- [x] **S2 — stop orphans surviving session end (the systemic fix).**
      `/etc/elogind/logind.conf` → `[Login] KillUserProcesses=yes` (backup `.bak-20261028`), then
      `kill -HUP $(pgrep -x elogind)` (no session loss).
  - **Why:** elogind's documented option; default is `no`, so a daemonized PAM keyring outlives its
    session forever. Sessions here *are* cgroup-tracked (`/proc/<phoc>/cgroup` → `0::/c521`,
    `Service=greetd`), so the kill has a cgroup to act on.
  - **Source:** `logind.conf(5)` ("processes listed in their session cgroup will be terminated"),
    Phosh/pmOS wiki; also `/usr/lib/pam.d/base-session` → `-session optional pam_gnome_keyring.so auto_start`.
  - **Caveat:** `KillUserProcesses=yes` also kills detached tools (tmux/screen) at logout — none used here.

- [x] **S3 — session logging that actually exists.** gnome-session's stdout went to `/dev/tty7` and
      phosh-session's to nothing, which is why none of these crashes ever had evidence.
      `/usr/local/bin/phosh-session-logged.sh` (exports `XDG_CURRENT_DESKTOP=Phosh:GNOME`,
      `ulimit -c unlimited`, logs to `/tmp/user-session.log` with exit status + signal name),
      wired via **both** `greetd-logged.toml` `[initial_session]` and
      `/usr/share/wayland-sessions/phosh.desktop` `Exec=` (backup `.bak-20261028`).
- [x] **S4 — keyboard cannot kill the session.** Every exit path of glissando now ends in a working
      keyboard (`phone/glissando-launch-hardened.sh`, `phone/glissando-launch-system.sh`), because a
      required component that exits is fatal by design (upstream Phosh OSK spec: the OSK "must"
      register and must keep running; gnome-session shows the failure message when it doesn't).

- [x] **S5 — glissando does not implement Phosh's mandatory `RegisterClient`** — **FIXED 2026-10-28 23:0x, PROVEN ON DEVICE.** (grep: 0 hits in
      `crates/glissando/src`). Docs: <https://phosh.mobi/posts/phosh-osk-interface/> §3 — the OSK *must*
      register with `org.gnome.SessionManager` app-id `sm.puri.OSK0` via `RegisterClient(app_id,
      startup_id)` so gnome-session can detect a crash and restart it. Reference impl:
      `phosh-osk-stub.c:pos_session_register()`. **Not the cause of the failure page** (the `gsd-*`
      daemons satisfy `RequiredComponents` without registering either), but it is the documented
      contract and it is what gives automatic keyboard restart.
  - **This WAS the cause of the failure page.** The instrumented log (S3) named it outright:
    `WARNING: Application 'sm.puri.OSK0.desktop' failed to register before timeout` +
    `gsm-manager.c:283:on_required_app_failure:Unrecoverable failure in required component
    sm.puri.OSK0.desktop`. Earlier reasoning that the keyring timeout was the trigger was wrong;
    the keyring orphan was a real, separate defect (S1/S2), not this one.
  - **Patch:** `docs/glissando-registerclient.patch` (commit `121c426` on top of `d1d407d Release 0.3.0`):
    `RegisterClient(app_id="sm.puri.OSK0", startup_id=$DESKTOP_AUTOSTART_ID)`, keep the returned
    `ClientPrivate` proxy alive, honour its `Stop` at logout. One compile fix needed: gio 0.22 wants
    `DBusProxy::new_sync(&conn, …)`, not `Option<&conn>`.
  - **Verified:** built 0.3.0 on the phone (1m11s incremental), installed to both prefixes,
    restarted the keyboard live, then `phone/check-osk-registration.sh` →
    `RESULT: OSK IS REGISTERED -> /org/gnome/SessionManager/Client24 (sm.puri.OSK0.desktop)`,
    24 clients total. Upstream `main` still has 0 `RegisterClient` hits, so this is also
    an un-filed upstream issue worth reporting.
- [ ] **S6 — dmesg is 94% one line** (`qcom_q6v5_pas 62400000.remoteproc: Handover signaled, but it
      already happened`, 1398/1485 lines) → the ADSP handover IRQ re-fires once per second un-acked and
      the ring buffer keeps only ~87 real lines. Proper fix: ack/mask the IRQ in `q6v5_handover_interrupt()`
      after the first event instead of logging forever (kernel patch, not a loglevel tweak).

---

## 6. Sensors (accelerometer / orientation) — scoped 2026-10-28, not started

**Where the hardware is:** not on the AP I2C/SPI buses. The stock DTB
(`device-backup/boot-partition-before-native-2026-10-27.img`) has no accelerometer compatible at all — only
`qcom,ssc-frequency-hz`, `qcom,ssc-ppm`, `qcom,ssctl-instance-id`, `sns_master`, `sns_slave`,
`sns_mode_control`, `sensor_core`. So the sensors hang off the **Snapdragon Sensor Core**, and the AP side
only describes that link.

**What works today on mainline:** nothing for motion. The only IIO devices are the two PMIC ADCs
(`c440000.spmi:pmic@0/4 adc@3100`). `iio-sensor-proxy` is installed but has no IIO accelerometer to read, so
Phosh cannot rotate.

**Measured 2026-10-28 over WiFi (no cable, read-only):**
- QRTR shows the sensor service **alive**: `400 1 0 5 14 Snapdragon Sensor Core service` (node 5 = ADSP).
- `libssc 0.4.4` (installed, ships `ssccli`) finds it: `[qrtr] added server on 5:14 -> service 400` — then
  loops `'registry' sensor unavailable, retrying... (1/100)` forever: the service is up but **no sensor
  registry** is loaded, so no sensor is registered.
- The vendor ships the registry: `vendor.img` → `/etc/sensors/{config, hals.conf, sns_reg_config}` (registry
  = 4036 B), and the dsp partition carries CHRE apps (`chre_app_sensor_cfg.so`, `chre_app_oem.so`,
  `libchre_slpi_skel.so`). On Android the **sensors HAL** reads `sns_reg_config` and pushes it to the SSC —
  `libssc`/`ssccli` have **no registry write support** (checked binary strings + the Python bindings).
- Mainline has **no** driver for the SSC/CHRE/sns link: nothing in `drivers/spi`, `drivers/soc/qcom`,
  `drivers/iio`, no `drivers/misc/chre`, and no `ssc`/`sns` nodes in `qcs615.dtsi` or `violet-sm6150.dts`.

**Verdict:** a real port, not a config flip. Cheapest possible first attempt is userspace-only (implement/obtain
a registry push for the SSC and see whether sensors enumerate), which would be WiFi-only; anything that needs
the SSC/SPI link or a CHRE probe is kernel/DT work and therefore **needs USB** to test. There is no
`KillUserProcesses`-style single knob here, and no evidence yet that the SSC hardware path even exists on the
mainline side.

---

## 7. Android apps (ATL) — installed 2026-10-29; only the GPU lockup blocks video

**What is installed:** `android-translation-layer 0_git20261019-r0` from Alpine edge/testing, with
`art_standalone`, `bionic_translation`, `libandroidfw`, `vixl`, `wolfssl-jni`, `libopensles-standalone`
(21.6 MB). Installed from locally pushed apks (`apk add --allow-untrusted`) because the phone's WiFi stalls
long scp sessions; see `push-file.sh` chunked-push technique in PROGRESS 2026-10-29 07:15.

**Proven working:** `gles3jni.apk` (JVM launches, dex2oat builds the boot image, GTK4 window appears) and
NewPipe 0.29.1 (UI browses; `MediaCodec` configures `h264` + `aac`, PCM comes up `PREPARED`).

**The one blocker is G1 (GPU lockup), not ATL:** video playback (and plain `gnome-control-center`) triggers
`adreno_idle: timeout waiting to drain ringbuffer` / `hangcheck detected gpu lockup rb 0`; Turnip then reports
`VK_ERROR_DEVICE_LOST` and the client segfaults. `GSK_RENDERER=gl` is **slower and still crashes**, so the
renderer is not the variable. `vkcube`/`vkmark` and `devcoredump` (`CONFIG_DRM_MSM_GPU_STATE=y`) are installed
for the eventual fix loop.

**Tools left on the phone:** `/usr/local/bin/atl-run` (launches an APK in the session; default `vulkan`,
override `ATL_GSK_RENDERER=gl|cairo`), `/usr/local/bin/atl-play-video` (drives playback via ATL's
`-u/--uri`), desktop entry "NewPipe (ATL)", APK at `/home/user/atl/NewPipe.apk`.

**Instagram:** no. Split APKs (base + `arm64_v8a` + density) vs ATL's single-APK input, Play Services for
auth/Firebase, and the same GPU path that dies on NewPipe. Laptop cannot substitute: ATL translates APIs, not
CPU, so ARM-only natives cannot load on x86_64.

---

## 8. Lock screen / password — done 2026-10-28 (recorded so it is not "fixed" again by accident)

It had been disabled on 10-27 (`disable-lock-screen=true`, `lock-enabled=false`, `idle-delay=0`). To have a
lock screen that actually asks for the password, **four** things are needed; the first three are cosmetic on
their own:

1. `org.gnome.desktop.lockdown disable-lock-screen` → `false`
2. `org.gnome.desktop.screensaver lock-enabled` → `true` (plus `lock-delay=0`)
3. `org.gnome.desktop.session idle-delay` → `300` (uint32) so it blanks + locks
4. **`sm.puri.phosh.lockscreen require-unlock` → `true`** (Phosh's own switch; while false, anyone swipes past)
5. **A PAM service file** — Alpine's phosh ships none, so `pam_start("phosh-lockscreen")` had nothing to load:
   create `/etc/pam.d/phosh-lockscreen` **and** `/etc/pam.d/phosh` with `pam_unix.so` for auth/account/password/session
   (upstream equivalent: Arch FS#80192).

Check it is really locked: `org.gnome.ScreenSaver.GetActive` on the session bus → `true`; `loginctl … -p LockedHint`
→ `yes`; and Phosh refuses `org.gnome.Shell.Screenshot` while locked (returns false).

---

## 9. History — W1–W7 measured status (2026-10-25; superseded, kept for the measurements)

| Item | State | What was actually measured |
|---|---|---|
| W1 MSS power domain | **done** | `[RPMHPD_MSS] = &mss` in `qcs615_rpmhpds[]`; `qcom_pas_pds_attach()` stopped returning `-ENODATA`. |
| W2 smp2p + remoteproc + glink | **done** | `remoteproc1: modem is available`; `echo start` → `remote processor modem is now up` in 1.27 s; glink VERSION/open/ack/intents all complete on `GIC_SPI 449` + `apss_shared 12`. |
| W3 memory map | **done 2026-10-25 ~23:50** | MSA restored to the vendor's **2 MB** (`0x93300000+0x200000`); talos' `pil-video@93400000` removed and its `pil_video_mem` label re-homed onto `video@92e00000` (violet's real video carve-out). Verified from the built DTB: modem `0x8b000000+0x7e00000`, video `0x92e00000+0x500000`, MSA `0x93300000+0x200000`, **no overlaps**. Only remaining overlap is the pre-existing `xbl_aop_mem`/`aop-cmd-db` nesting from talos, which the vendor has too. |
| W4 firmware | **done** | `/lib/firmware/qcom/qcs615/`: `modem.mdt` + `modem.b00..b27`, `wlanmdsp.mbn`, `bdwlan.*` (31 files) pulled from the phone's own `modem` partition; `bdwlan.102` → `ath10k/WCN3990/hw1.0/bdwlan.bin`. |
| W5 rmtfs memory | **done** | `rmtfs@0`, `reg = <0 0x0 0 0x200000>`, `qcom,client-id = <1>`, **no `qcom,vmid`** (SCM reassign returns `-EINVAL`); `/dev/qcom_rmtfs_mem1` exists. |
| W6 servers + start order | **partly done, one real bug fixed** | `tqftpserv` runs; `rmtfs` is now an OpenRC service. **The flag was wrong all session**: `-s` means "sync with the mss rproc", not storage — it is `-o <dir>`. With `-o /var/lib/rmtfs` the modem stopped dying in ~1 s and ran 32–40 s. |
| W7 board data | **staged** | `bdwlan.bin` in place; `board-2.bin` still generic linux-firmware. Cannot be validated until WLFW answers. |

### New blockers discovered while doing W6 (these are not in the original plan)

- **The modem never sends a single rmtfs request.** With `rmtfs -o /var/lib/rmtfs -v` running before
  `echo start`, the whole log is `registering services` and nothing else, and the modem still asserts:
  `qcom_q6v5_pas 4080000.remoteproc: fatal error without message` exactly **40 s** after `remote processor modem is now up`.
  So this is not EFS; the modem's QMI never reaches the AP.
- **The modem publishes zero QRTR services.** Proven node identity by stopping `remoteproc0`: all 11 services on
  node 5 disappear, so **node 5 = ADSP**. The AP is node 1 (`pd_mapper` = service 64, `tqftpserv` = 4096).
  The modem has no node of its own.
- **ADSP protection domains are never registered.** `/sys/bus/pdr/devices` is empty even after restarting the ADSP
  *with* pd-mapper already loaded, and `PDR: msm/adsp/audio_pd register listener txn wait failed: -110` follows every
  `pd-trigger` load. So the PDR route to `avs/audio` is closed on this firmware, not mis-sequenced.
- **Audio reproduces exactly at the AFE**: with `PRI_MI2S_RX Audio Mixer MultiMedia3` switched on (it was off, which is
  what produced the misleading `-22` at open), the stream opens, buffers allocate, then
  `AFE set params failed -110` / `AFE enable for port 0x1000 failed -110` — the ADSP's AFE service never answers.

### Lesson that cost the most time here

`CONFIG_RPMSG_QCOM_GLINK=y` with `QCOM_GLINK_SMEM=m` means `qcom_glink_native.c` compiles **into the Image**, so
rebuilding the module after editing it produces an unchanged `.ko`. Verify with
`strings qcom_glink_smem.ko | grep <new string>` before believing any glink experiment.

---
