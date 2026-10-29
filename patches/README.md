# Patches against vanilla Linux 7.2.10

Patches are against vanilla Linux 7.2.10 and are applied with `git apply` in numeric order.
`violet-vbat.c` is a new file (a small battery/voltage driver), the rest are diffs. Status as of 2026-10-29.
Patch 0014 is not shipped: it is superseded by 0015.

Verify the series parses before applying: `git apply --numstat patches/*.patch`.

| Patch | What | Status |
|---|---|---|
| 0001 | Add `violet-sm6150.dts` + Makefile/binding entries | **apply it**, then overwrite the DTS with `dt/violet-sm6150.dts` (authoritative) |
| 0002 | tzmem: no SHM bridge on sm6150 | needed |
| 0003 | icc qcs615: ACV enable mask | needed |
| 0004 | adreno: A612 RGMU bring-up | needed (GPU works) |
| 0005 | spmi-pmic-arb: ack/disable stale IRQs | probably kexec-only, harmless |
| 0006 / 0009 | NT36672A shenchao panel + binding | needed; TODO fold into nt36672a.c |
| 0007 | dispcc-qcs615 GDSC/XO fix | needed (see note below about the 288 MHz table) |
| 0008 | dsi phy 14nm vcca rename | needed |
| 0010 | ath10k: skip quiet mode on WCN3990 | needed |
| 0011 / 0012 / 0013 | pd-mapper, glink early intents, rpmhpd mss | needed for ADSP/modem |
| 0015 | ath10k WCN3990: create the BSS peer before the station vdev start | **real WiFi fix** (has a debug hexdump + `violet_sta_self_peer` param) |
| 0016 | ASoC vendor-parity + experiment knobs (`violet_popp`, `violet_copp_topo`, `violet_island`, `violet_slave`, hw-vote param) | works, **not minimised**: several knobs are experiments |
| 0017 | arm-smmu-qcom: reserve hyp-owned context banks 10-12 on qcs615 | **real audio fix** (hardcoded to qcs615-smmu-500) |
| 0018 | tas2781: ROM-mode power without RCA firmware | workaround: no calibration, no speaker protection |
| `violet-vbat.c` | battery gauge reading the pm6150 QG hardware | WIP: sign convention inverted, coulomb counting not validated; needs `Kconfig`/`Makefile` hooks below |

## Tree changes that are NOT in any patch file (re-create from this list)

- `drivers/power/supply/Kconfig`: `config BATTERY_VIOLET_VBAT` (tristate, depends on IIO && OF); `Makefile`: `obj-$(CONFIG_BATTERY_VIOLET_VBAT) += violet-vbat.o`.
- Kernel config: see `configs/config-7.2.10-sm6150-2026-10-27` (notably `CONFIG_NVMEM_SPMI_SDAM=y`, `CONFIG_BATTERY_VIOLET_VBAT=m`, ADSP services built in).
- Display debug hacks still in the tree (documented, not applied by a patch): `if (1) /* DSIDBG: force max core clock */` in `dpu_core_perf.c`; `DSIDBG` DMA_FIFO_CTRL/PHY reset/error-IRQ-mask code in `dsi/dsi_host.c`; `dsi_tpg` test pattern in `dsi/dsi_manager.c`; `pr_info("DSIDBG ...")` in `dpu_hw_intf.c`. Hermes (docs/hermes/) flagged them; none was shown to be a cause. Remove before any upstream submission.
- `drivers/clk/qcom/dispcc-qcs615.c`: MDP clock table only has 192/288 MHz while the DT OPPs say 192/256/307.2 MHz (Hermes finding; harmless so far).
- Touch driver `novatek-nvt-ts.c` delayed-work init (local hack).
