# Device tree snapshots and variants

**Source of truth:** `kernel/linux-7.2.10/arch/arm64/boot/dts/qcom/violet-sm6150.dts` (+ `talos.dtsi`, `pm6150*.dtsi`).
`violet-sm6150.dts.20261027-final` is a snapshot of it as flashed on 2026-10-27.

| File | Purpose / status |
|---|---|
| `violet-sm6150.dts.20261105-torch` | **Current, flashed (`boot-mainline-torch.img`).** The 11-05 typec DT plus `&pm6150l_flash` with one `led-0` (channels 1+2, torch cap 500 mA, flash 1.8 A / 1.28 s) and `#include <dt-bindings/leds/common.h>`. Pre-change copy: `.20261105-pre-torch`. |
| `violet-sm6150.dts.20261105-typec` | **Current, flashed (`boot-mainline-typec.img`).** On top of the 10-27 final: camera nodes, `bat_therm`/`bat_id` ADC channels with io-channels on the `battery` node (`boot-mainline-batt.img`), and `&pm6150_typec` enabled sink-only (5 V/3 A + 9 V/3 A sink PDOs, `vdd-pdphy-supply` = L17, no vbus-supply, not linked to the dwc3 role switch). Pre-change copies: `.20261104-pre-battid`, `.20261105-pre-typec`. |
| `violet-sm6150.dts.20261027-final` | Current, flashed. Has: protected-DRAM reservations (`violet-hole@93500000`, `violet-tail@173000000`), RTC + SDAM offset cell, volume keys (RESIN + pm6150l gpio2), `battery` node for violet-vbat, speaker/audio, WiFi, GPU. |
| `violet-sm6150.dts.20261027-pre-memhole` | Before the memory reservations (this is the one that crashed under load). |
| `violet-sm6150.dts.20261027-with-opp-cap` | With `delete-node opp-1900800000` (not needed: the crash was the memory bug). |
| `violet-sm6150.dts.20261027-pre-rtc` | Before the RTC change. |
| `violet-sm6150.dts.20261026-*` | Earlier audio / LPI / volume-key snapshots. `-lpi-WEDGES-BOOT`: do not boot. |
| `violet-ddr.dtb/.dts` | Experiment: `ddr-floor` node for `modules/violet-ddrvote` (DDR bandwidth floor). Rejected as a fix, not needed. |
| `violet-mic.dtb/.dts`, `violet-mic2`, `violet-mic3` | Mic experiments: headset playback/capture links, LPI pinctrl node. The WCD9370 stays in reset (see docs/PROGRESS.md 2026-10-26/27 mic entries). |
| `violet-audio*.dtb`, `violet-iommu.dtb`, `violet-wcd.dtb`, `violet-lpi*.dtb`, `violet-vacap.dtb`, `violet-noswr.dtb` | Audio/SMMU/LPI bisect variants from 2026-10-26. Historical. |
| `violet-lpi3.dtb/.dts` | LPI node with only the macro-vote clock: AP hung on first register access. |
| `ref/` | Vendor (downstream) display/panel DT fragments used as reference. |

Reminder: ABL takes our single appended DTB because the `dtbo` partition is erased; `mk-bootimg*.sh` add `qcom,msm-id`/`board-id`.
