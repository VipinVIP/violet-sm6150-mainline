#!/bin/bash
# From a running mainline kernel (or r10) reboot via sysrq and wait until r10 answers.
IF=$(ip -br link | awk '/^enp0s20f0u/{print $1; exit}')
A=$(ip neigh show dev $IF | awk '/fe80/{print $1; exit}')
timeout 10 ssh -o BatchMode=yes -o StrictHostKeyChecking=no user@$A%$IF 'sudo -n sh -c "sync; echo b > /proc/sysrq-trigger"' 2>/dev/null
sleep 20
for i in $(seq 1 60); do
  A=$(ip neigh show dev $IF 2>/dev/null | awk '/fe80/{print $1; exit}')
  [ -n "$A" ] && r=$(timeout 8 ssh -o BatchMode=yes -o StrictHostKeyChecking=no user@$A%$IF 'uname -r' 2>/dev/null) && [ "$r" = "4.14.356-openela-rc1-perf" ] && { echo "r10 up"; sleep 5; exit 0; }
  ping -c1 -W1 ff02::1%$IF >/dev/null 2>&1; sleep 4
done
echo "phone did not come back on r10"; exit 1
