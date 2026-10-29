# Device tree

`violet-sm6150.dts` is the **authoritative** board DTS — the exact file that was compiled into the DTB
that boots on this device (verified byte-identical to the kernel tree's copy at flash time).

It carries, in order of how much pain each part cost:

- the **protected-DRAM reservations** (`violet-hole@93500000`, `violet-tail@173000000`) — without these
  the SoC wedges after login under load;
- RTC + SDAM offset cell, volume keys (RESIN + `pm6150l` gpio2), and the `battery` node used by the
  `violet-vbat` driver;
- audio (TAS2563 + WCD9375 + SoundWire), WiFi, GPU (`&gpu` / `&gpu_zap_shader`) and display enablement.

**How to use it:** copy it over `arch/arm64/boot/dts/qcom/violet-sm6150.dts` inside a tree with
`patches/0001` applied. Patch 0001 adds the Makefile and `qcom.yaml` entries plus an early version of
this DTS; the file here supersedes that early version and must win.

`talos.dtsi`, `pm6150.dtsi` and `pm6150l.dtsi` come from the vanilla kernel tree — they are not
duplicated here.

Two things ABL needs are added at image-build time, not in this file, because they are
vendor/deprecated concerns: `__symbols__` (via a `dtc -@` round-trip) and the `qcom,msm-id` /
`qcom,board-id` selection keys. See `host/mk-bootimg-clean.sh`.
