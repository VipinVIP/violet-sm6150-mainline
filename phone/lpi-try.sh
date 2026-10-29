#!/bin/sh
# Controlled test of the LPASS LPI pinctrl (the node that wedged the boot).  Run on the phone, mainline booted with
# dt/violet-wcd.dtb and  /etc/modprobe.d/60-no-lpi.conf = "blacklist pinctrl_sdm670_lpass_lpi", so nothing touches LPI at boot.
# Stream dmesg to the laptop first:  ./rssh 'sudo -n dmesg -w' > dmesg-live-lpi.txt
# The last line before the connection dies tells where it hangs.
set -u
echo "== ADSP / audio PD up?"; dmesg | grep -a -c "apr:service@7:dais"
echo "== vote clock provider present?"; ls /sys/kernel/debug/clk 2>/dev/null | grep -i -E "vote|q6afe" | head
echo "== loading pinctrl_sdm670_lpass_lpi (may hang the AP; watchdog will recover)"
sync
modprobe -v pinctrl_sdm670_lpass_lpi
sleep 2
dmesg | tail -15
