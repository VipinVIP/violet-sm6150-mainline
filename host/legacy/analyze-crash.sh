#!/bin/sh
# Pull a crash trace from both durable sources and symbolize it.
#  1. netconsole.log  — live kernel output captured on this laptop (arrives even mid-hang)
#  2. pstore          — console-ramoops on the phone, survives a warm reset/panic
# Usage: ./analyze-crash.sh
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
KDIR="$DIR/kernel/linux-7.2.10"
NC="$DIR/netconsole.log"

echo "=============================================================="
echo " 1. netconsole capture ($NC)"
echo "=============================================================="
if [ -s "$NC" ]; then
    wc -l < "$NC" | sed 's/^/lines: /'
    echo "--- watchdog / lockup / panic / oops / fault mentions ---"
    grep -nE "watchdog: BUG|soft lockup|hard LOCKUP|Kernel panic|Oops|Call trace|Unable to handle|rcu:|smmu|iova|Internal error" "$NC" \
        | head -40 || echo "(none)"
    echo "--- last 30 lines captured ---"
    tail -30 "$NC"
else
    echo "(netconsole.log empty or missing)"
fi

echo
echo "=============================================================="
echo " 2. pstore on the phone"
echo "=============================================================="
[ -f /tmp/phone ] || { echo "(no /tmp/phone — cannot reach phone)"; exit 0; }
set -- $(cat /tmp/phone)
A=$1; I=$2
O="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=8"
timeout 40 ssh $O user@$A%$I 'echo "kernel: $(uname -r) up=$(cut -d. -f1 /proc/uptime)s"; echo "pstore entries:"; sudo -n ls -l /sys/fs/pstore/ 2>/dev/null || echo "(none)"' </dev/null 2>&1 | head -12

echo "--- extracting console-ramoops (grep for the interesting part) ---"
timeout 60 ssh $O user@$A%$I 'sudo -n cat /sys/fs/pstore/console-ramoops-0 2>/dev/null || sudo -n cat /sys/fs/pstore/console-ramoops 2>/dev/null' </dev/null > "$DIR/crash-ramoops.txt" 2>/dev/null
if [ -s "$DIR/crash-ramoops.txt" ]; then
    wc -l < "$DIR/crash-ramoops.txt" | sed 's/^/ramoops lines: /'
    grep -nE "watchdog: BUG|soft lockup|hard LOCKUP|Kernel panic|Call trace|Unable to handle|rcu:" "$DIR/crash-ramoops.txt" | head -20
else
    echo "(no ramoops content — cold boot wipes it; warm reset is required)"
fi

echo
echo "=============================================================="
echo " 3. symbolize any stack trace found"
echo "=============================================================="
DEC="$KDIR/scripts/decode_stacktrace.sh"
for f in "$DIR/crash-ramoops.txt" "$NC"; do
    [ -s "$f" ] || continue
    if grep -qE "Call trace:|\[<[0-9a-f]{8,}\]" "$f"; then
        echo "--- decoding $f ---"
        if [ -x "$DEC" ]; then
            ( cd "$KDIR" && ./scripts/decode_stacktrace.sh vmlinux < "$f" 2>/dev/null ) | grep -A25 -E "Call trace:" | head -50
        else
            echo "(decode_stacktrace.sh not found; raw addresses kept)"
        fi
    fi
done
