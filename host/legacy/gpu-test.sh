#!/bin/bash
# r10 -> (downstream loads the zap via KGSL, which TZ needs first) -> kexec mainline with separate GPU DRM -> print GPU dmesg
# Usage: gpu-test.sh <tag>
IF=$(ip -br link | awk '/^enp0s20f0u/{print $1; exit}'); TAG=${1:-gpu}
A=$(ip neigh show dev $IF | awk '/fe80/{print $1; exit}')
SSH="ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no"
$SSH user@$A%$IF 'uname -r' | grep -q '^4.14' || { echo "phone is not on r10 (reboot it first: sysrq b)"; exit 1; }
scp -q -o StrictHostKeyChecking=no $HOME/violet-pmos/tools/kgsl_open.py "user@[$A%$IF]:/tmp/"
$SSH user@$A%$IF 'sudo -n timeout 30 python3 /tmp/kgsl_open.py; sudo -n dmesg | grep -c "a612_zap: Brought out of reset"'
EXTRA_CMDLINE="msm.separate_gpu_kms=1 ${EXTRA_CMDLINE:-}" timeout 300 $HOME/violet-mainline/kexec-test.sh $TAG 2>&1 | tail -1
A=$(ip neigh show dev $IF | awk '/fe80/{print $1; exit}')
$SSH user@$A%$IF 'uname -r; sudo -n dmesg | sed -n "/loaded qcom\/a630_sqe/,\$p" | head -${LINES_OUT:-40}'
