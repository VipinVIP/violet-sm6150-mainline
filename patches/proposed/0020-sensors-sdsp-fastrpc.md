> **SUPERSEDED 2026-10-30 — DO NOT IMPLEMENT.** Reading the real Alpine `hexagonrpcd` package
> (`0.4.0-r3`, aarch64) settles it: `/etc/init.d/hexagonrpcd-adsp-sensorspd` runs
> `hexagonrpcd -f /dev/fastrpc-adsp -d adsp -s`, i.e. `-s` (attach to sensorspd) is applied to the **plain
> ADSP FastRPC device that this port already has** (audio `allocpd` works through it). No `sdsp` DT node, no
> extra compute-cb SIDs, no kernel change. The same package also fixes the config layout:
> `-R <dir>` serves `<dir>/sensors/config/`, `<dir>/sensors/registry/` and `<dir>/sensors/sns_reg.conf`,
> default root `/usr/share/qcom/<soc>/<vendor>/<device>`. Staged tree: `fw/sensors/qcom/sm6150/Xiaomi/violet/`.
> The text below is kept only as a record of the dead end. See `CHECKLIST.md` §6 for the real procedure.

# Sensors: candidate `sdsp` (sensors protection domain) FastRPC node — PROPOSAL, untested

Status: **not applied, not compiled, not booted.** Do not fold this into a boot image without a device
session to verify it; a second `fastrpc` node probing on the ADSP can in principle disturb the audio
`allocpd` path that currently works.

## Why

`drivers/misc/fastrpc.c` in this tree already resolves the `sdsp` domain
(`fastrpc_get_domain_id(): !strncmp(domain, "sdsp", 4) → SDSP_DOMAIN_ID`), and
`Documentation/devicetree/bindings/misc/qcom,fastrpc.yaml` allows `label = "sdsp"`. But
`arch/arm64/boot/dts/qcom/talos.dtsi` only declares `fastrpc` children with `label = "adsp"` (under
`remoteproc_adsp`'s `glink-edge`) and `label = "cdsp"`. The vendor expresses the sensors PD on a single
legacy node with `qcom,fastrpc-adsp-sensors-pdr`.

On violet the sensors run **inside the ADSP** (QRTR node 5 advertises service 400), so the sensors PD is an
ADSP protection domain, not a separate DSP: the node belongs inside `remoteproc_adsp`'s `glink-edge`, next to
the existing `label = "adsp"` node.

## Sketch

```dts
&remoteproc_adsp {
	glink-edge {
		fastrpc_sensors: fastrpc@1 {
			compatible = "qcom,fastrpc";
			qcom,glink-channels = "fastrpcglink-apps-dsp";
			label = "sdsp";
			#address-cells = <1>;
			#size-cells = <0>;

			compute-cb@1 {
				compatible = "qcom,fastrpc-compute-cb";
				reg = <1>;
				/* SID: unknown for sm6150's sensors PD - must come from
				 * the vendor fastrpc PD configuration, do not guess. */
				iommus = <&apps_smmu 0x0000 0x0>;
			};
		};
	};
};
```

## Open questions to settle before writing this as a real patch

1. **Compute-cb SIDs** for the sensors PD on sm6150 — the vendor's `qcom,msm_fastrpc` node is in the legacy
   single-node style and does not carry them per-cb, so they must be derived from the vendor's
   `ipa`/`fastrpc` SID tables or observed at runtime on the downstream kernel.
2. Whether `hexagonrpcd` (the config-serving daemon) can attach to a PD exposed by mainline fastrpc at all,
   or whether it needs the same `qcom,fastrpc-adsp-sensors-pdr` property name the vendor uses.
3. Whether the ADSP firmware on violet ships the `sns_lsm6ds3c` / `sns_ak0991x` / `sns_stk3x3x` modules
   **statically** (likely, they are referenced by the vendor configs) or expects to load them from the
   `dsp` partition's CHRE apps — the latter would need those files staged for the daemon.

Cheapest next test needs **no kernel change at all**: run the config-serving daemon against `fw/sensors/`
and watch whether `ssccli` stops looping on `'registry' sensor unavailable`.
