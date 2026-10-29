#!/bin/sh
D=/sys/kernel/debug/dri/0/debug
for f in core_perf/perf_mode core_perf/core_clk_rate core_perf/fix_core_clk_rate core_perf/fix_core_ib_vote core_perf/fix_core_ab_vote core_perf/min_dram_ib core_perf/min_core_ib core_perf/max_core_ab core_perf/enable_bw_release danger/danger_status danger/safe_status; do printf "%s=" $f; cat $D/$f 2>&1 | tr '\n' ' '; echo; done
echo "--- icc"; grep -B1 -A3 "qxm_mdp0" /sys/kernel/debug/interconnect/interconnect_summary | head -6
echo "--- mdp clk"; grep -E "disp_cc_mdss_mdp_clk " /sys/kernel/debug/clk/clk_summary | cut -c1-110
echo "--- nmi"; cat /proc/sys/kernel/nmi_watchdog; grep -c . /proc/cmdline; tr ' ' '\n' < /proc/cmdline | grep -E "nmi|lockup|pseudo"
