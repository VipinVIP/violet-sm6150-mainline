# Brief for Hermes: research why the Redmi Note 7 Pro (violet) hangs under continuous display updates on mainline Linux

Model: use DeepSeek flash 4.1 if no default is set. Research thoroughly. **Do NOT change anything on the phone or in the repo until your findings are written to `docs/hermes/FINDINGS-display-hang.md` and the user (or Claude) has read them.** Read-only investigation, web research and offline analysis first. Claude is coordinating; it reads that file.

## The problem
SoC SM6150 (Snapdragon 675, "talos"/QCS615 in mainline). Mainline Linux 7.2.10, booted via kexec from the vendor r10 kernel. Display = DPU 5.x (msm_dpu, ae01000), DSI panel NT36672A video mode (1080x2340), backlight WLED on pm6150l. Repo: /home/vipi/violet-mainline (kernel/linux-7.2.10, dt/, docs/PROGRESS.md has the whole history; newest entries are at the top). DT: kernel/linux-7.2.10/arch/arm64/boot/dts/qcom/violet-sm6150.dts (+ talos.dtsi).

**Symptom:** whenever the screen is on and redrawing continuously (a video, or just a full-screen CSS animation in Firefox), the phone dies within a few seconds: full BLUE screen, then SoC reset (r10 reports Power-off reason PS_HOLD = APSS watchdog bite). Kernel prints nothing (no dpu underrun, no smmu fault, no softlockup, even with softlockup_panic=1): a CPU is stuck below kernel detection, probably on an MMIO or bus access.

**Proven NOT the cause** (each tested, still hangs or irrelevant): CPU frequency (capped at 1.2 GHz still hangs), GPU (pinned at 435 MHz still hangs; and with software compositing WLR_RENDERER=pixman plus software-GL Firefox, GPU idle, still hangs), audio (no stream in the log), video decoder (no /dev/video*), idle (stays up overnight), WLED OVP storm (fixed earlier by qcom,num-strings=2), storage. Headless GPU stress with no display is fine. Static pages are fine. The screen must be ON (DPMS off = no hang).

**Facts:** disp_cc_mdss_mdp_clk runs at 288 MHz (not one of the DPU OPPs 192/256/307.2 MHz in talos.dtsi, required-opps low_svs/svs/nom on RPMHPD_CX). mdss_core_gdsc on. Hypervisor-owned SMMU context banks 10-12 are already reserved (patch 0017). The vendor r10 kernel (4.14, source in ~/violet-pmos/kernel) draws smoothly on the same hardware, so the HW is fine and something in mainline config differs.

## What to research (findings first, no changes)
1. Upstream: Linux mainline/linux-next/lore.kernel.org and Qualcomm (CodeLinaro / Qualcomm "talos"/QCS615 DPU+DISPCC patches, msm-next, DRM/MSM mailing list, freedesktop gitlab drm/msm issues) for hangs under continuous display updates on SM6150/SM8150-class DPU 5.x: dispcc clock/OPP/MMCX/CX corner issues, DPU core-perf/interconnect bandwidth votes (mdp0-mem, dpu_core_perf), icc sync_state dropping votes, DSI/DPU underrun handling, fetch/prefetch timing (this repo already needed a one-line-late programmable fetch fix), TE/vsync, CWB, DSC. Note which commits are newer than 7.2.10.
2. Diff vendor vs mainline: compare the vendor display DT (~/violet-pmos/kernel/arch/arm64/boot/dts/qcom/sm6150-sde*.dtsi, violet panel dtsi) and driver defaults (mdp clock rates, bandwidth/ib/ab votes, qcom,sde-* QoS/danger/safe LUTs, DSI clocks/lane rate, regulator/vreg modes for DSI PHY and panel rails) with talos.dtsi + violet-sm6150.dts. List every difference that could matter under load.
3. Check the interconnect nodes used by the DPU in talos.dtsi (MASTER_MDP0 -> SLAVE_EBI1, mmss_noc, mc_virt) and the qcs615 interconnect driver for missing/incorrect QoS or BCM keepalives.
4. Propose ranked hypotheses with the exact config/code change and how to test each safely, and say what log or register read would confirm it BEFORE any change. Cite sources (URLs, commit ids, file:line).

## How to work
- You may ssh to the phone read-only (USB: ./rssh in the repo; or WiFi user@<lan-ip>) but the phone resets itself when the bug triggers; do not trigger it. Do not run video/animation tests; Claude owns the test loop.
- Do not edit the DT, kernel, firmware or phone settings. Do not flash.
- Write everything to `docs/hermes/FINDINGS-display-hang.md`: summary at top (3-5 lines), ranked hypotheses, evidence, proposed minimal tests. Then tell the user it is ready. Claude will read it and run the tests.
