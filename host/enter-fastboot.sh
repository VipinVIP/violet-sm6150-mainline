#!/usr/bin/env bash
# Reboot the phone into FASTBOOT from Linux — no buttons, no partition writes.
#
# Works because the DT already carries the reboot-mode magics
# (pm6150_pon: compatible "qcom,pm8998-pon", mode-bootloader = <0x2>) and the
# kernel has CONFIG_REBOOT_MODE + CONFIG_POWER_RESET_QCOM_PON. The helper on the
# phone (/usr/local/bin/reboot-bootloader, source: phone-reboot-bootloader.sh)
# writes "bootloader" through the reboot-mode framework; qcom-pon stores it in the
# PON soft-reboot spare and ABL's ResetReason turns it into FASTBOOT_MODE.
#
#   ./enter-fastboot.sh          reboot into fastboot and wait for it
#   ./enter-fastboot.sh --check  just report whether fastboot is already up
#
# The `misc` BCB route ("bootonce-bootloader" in bootloader_message) does NOT work
# on this ABL: LinuxLoader.c only consults GetKeyPress() and GetRebootReason(),
# there is no misc/BCB parsing on the boot path. Tested 2026-10-25 and ignored.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE" || exit 1

if [ "${1:-}" = "--check" ]; then
	if timeout 6 fastboot devices 2>/dev/null | grep -q .; then
		echo "fastboot: $(timeout 6 fastboot devices)"; exit 0
	fi
	echo "fastboot: not present"; exit 1
fi

if timeout 6 fastboot devices 2>/dev/null | grep -q .; then
	echo "== already in fastboot: $(timeout 6 fastboot devices)"
	exit 0
fi

echo "== asking the phone to reboot into fastboot (reboot-mode, no buttons)"
./rssh '/usr/local/bin/reboot-bootloader' 2>&1 | grep -v Warning || true
# Short check only: the user can see the screen, so a long poll is just noise.
for i in $(seq 1 10); do
	if timeout 4 fastboot devices 2>/dev/null | grep -q .; then
		echo "== fastboot up after ~$((i*2))s: $(timeout 4 fastboot devices)"
		exit 0
	fi
	sleep 2
done
echo "== not seen after 20 s — look at the phone screen, or the helper is missing on it"
exit 1
