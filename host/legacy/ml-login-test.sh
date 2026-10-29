#!/bin/bash
# Logged-in-session stability test without a human: r10 -> kexec mainline (ml-boot.sh), then greetd with a
# one-shot [initial_session] (autologin of "user" into phosh) started from a fresh cgroup, then watch the
# kernel log over a pre-opened ssh stream for SMMU faults / lockups and check liveness every 10 s.
# Usage: ml-login-test.sh <tag> [seconds]      (phone must be on r10)
TAG=${1:-login}; DUR=${2:-180}
HERE=$(cd "$(dirname "$0")" && pwd)
O="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=6"
IF=$(ip -br link | awk '/^enp0s20f0u/{print $1; exit}'); A=$(ip neigh show dev $IF | awk '/fe80/{print $1; exit}')
# on r10: autologin config for the NEXT greetd start (= mainline boot), restored right after mainline is up
ssh $O -T "user@$A%$IF" 'bash -s' <<'EOF'
sudo -n tee /etc/phrog/greetd-autologin.toml >/dev/null <<'T'
[terminal]
vt = 7

[initial_session]
command = "phosh-session"
user = "user"

[default_session]
command = "/usr/libexec/phrog-greetd-session"
user = "greetd"
T
grep -q greetd-autologin /etc/conf.d/greetd || sudo -n cp /etc/conf.d/greetd /etc/conf.d/greetd.pre-autologin
sudo -n sed -i 's#^cfgfile=.*#cfgfile="/etc/phrog/greetd-autologin.toml"#' /etc/conf.d/greetd; sync
grep ^cfgfile /etc/conf.d/greetd
EOF
WDT=off "$HERE/ml-boot.sh" "$TAG" || exit 1
IF=$(ip -br link | awk '/^enp0s20f0u/{print $1; exit}'); A=$(ip neigh show dev $IF | awk '/fe80/{print $1; exit}')
H="user@$A%$IF"; LOG="$HERE/login-$TAG-dmesg.txt"
(timeout $((DUR + 60)) ssh $O -o ServerAliveInterval=2 -o ServerAliveCountMax=5 "$H" 'sudo -n dmesg -w' > "$LOG" 2>&1 &)
ssh $O -T "$H" 'bash -s' <<'EOF'
sudo -n cp /etc/conf.d/greetd.pre-autologin /etc/conf.d/greetd; sync      # restore for the next boot
sleep 15
echo "session: phoc=$(pidof phoc) phosh=$(pidof phosh) phrog=$(pidof phrog)"; loginctl list-sessions --no-legend 2>/dev/null
EOF
t0=$SECONDS
while [ $((SECONDS - t0)) -lt $DUR ]; do
	r=$(timeout 8 ssh $O "$H" 'echo "up=$(cut -d" " -f1 /proc/uptime) phoc=$(pidof phoc) phosh=$(pidof phosh)"' 2>&1 | tail -1)
	echo "$(date +%T) +$((SECONDS - t0))s $r  faults=$(grep -ac 'Unhandled context fault' "$LOG")"
	case "$r" in up=*) ;; *) echo "LOST CONTACT"; break;; esac
	sleep 10
done
echo "--- kernel log highlights ($LOG)"
grep -aE "callbacks suppressed|Unhandled context|frame done|rpmh|AMC|soft lockup|rcu:|BUG|Oops" "$LOG" | head -12 | cut -c1-160
