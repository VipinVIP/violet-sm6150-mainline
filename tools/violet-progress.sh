#!/usr/bin/env bash
# violet-progress — one live view of everything in flight for the glissando
# keyboard build: phone-side work (apk, clone, cargo) and laptop-side work
# (dictionary build, background jobs).  Refreshes in place; safe to leave
# running in the desktop app's terminal pane.
#
#   ./tools/violet-progress.sh          refresh every 15 s (Ctrl-C to stop)
#   ./tools/violet-progress.sh 5        refresh every 5 s
cd "$(dirname "$0")/.." || exit 1
INTERVAL=${1:-15}
PHONE_TIMEOUT=12

hr() { printf '%s\n' "────────────────────────────────────────────────────────────────────────"; }

phone_block() {
	timeout $PHONE_TIMEOUT ./rssh '
		printf "  uptime : %s\n" "$(uptime | sed "s/^ *//;s/,.*load/  load/")"
		printf "  load   : %s\n" "$(cut -d" " -f1-3 /proc/loadavg)"
		printf "  memory : %s\n" "$(free -m | awk "/^Mem:/{printf \"%s MB used / %s MB total\", \$3, \$2}")"
		printf "  disk / : %s\n" "$(df -h / | awk "NR==2{print \$3\" used, \"\$4\" free\"}")"

		if grep -aqE "^OK:" /var/tmp/apk-gloss.log 2>/dev/null; then
			printf "  apk    : DONE — %s\n" "$(grep -aE "^OK:" /var/tmp/apk-gloss.log | tail -1 | cut -c1-70)"
		elif pgrep -x apk >/dev/null 2>&1; then
			printf "  apk    : RUNNING — %s\n" "$(tail -1 /var/tmp/apk-gloss.log 2>/dev/null | tr -d "\r")"
		else
			printf "  apk    : not started\n"
		fi

		if [ -d "$HOME/glissando" ]; then
			printf "  source : cloned (%s files)\n" "$(find "$HOME/glissando" -maxdepth 2 -type f 2>/dev/null | wc -l)"
		else
			printf "  source : not cloned yet\n"
		fi

		if pgrep -x cargo >/dev/null 2>&1 || pgrep -f "cargo build" >/dev/null 2>&1; then
			built=$(find "$HOME/glissando/target" -name "*.rlib" 2>/dev/null | wc -l)
			printf "  cargo  : BUILDING — %s rlibs compiled, %s\n" "$built" "$(tail -1 /var/tmp/cargo-gloss.log 2>/dev/null | cut -c1-80)"
		elif [ -x "$HOME/glissando/target/release/glissando" ]; then
			printf "  cargo  : DONE — %s\n" "$(ls -la "$HOME/glissando/target/release/glissando" | awk "{print \$5\" bytes\"}")"
		else
			printf "  cargo  : idle\n"
		fi

		d=$(ls "$HOME"/glissando/data/dict/*.gld 2>/dev/null | wc -l)
		printf "  dicts  : %s .gld file(s) on the phone\n" "$d"
		printf "  osk    : %s\n" "$( [ -f "$HOME/.local/share/applications/sm.puri.OSK0.desktop" ] && echo "glissando override INSTALLED" || echo "stevia (default)" )"
		printf "  build  : %s rustc, %s cargo process(es) running\n" \
			"$(pgrep -f "rustc" 2>/dev/null | wc -l)" "$(pgrep -f "cargo build" 2>/dev/null | wc -l)"
	' 2>/dev/null
}

laptop_block() {
	printf "  dicts  : "
	if pgrep -f "tools/build-dicts.py" >/dev/null 2>&1; then
		printf "RUNNING — %s\n" "$(tail -1 /tmp/dicts.log 2>/dev/null | cut -c1-90)"
		printf "           cache: %s\n" "$(du -sh /tmp/glissando-src/.devtools/dict-cache 2>/dev/null | cut -f1)"
	elif ls /tmp/glissando-src/data/dict/*.gld >/dev/null 2>&1; then
		printf "DONE — %s\n" "$(ls -la /tmp/glissando-src/data/dict/*.gld | awk '{printf "%s (%s) ", $9, $5}' | sed 's|.*/||')"
	else
		printf "idle\n"
	fi
	printf "  phone link: %s\n" "$(ip -6 neigh show dev enp0s20f0u4 2>/dev/null | awk '{print $1, $NF}' | head -1)"
}

# --once: print a single frame and exit (used by violet_progress_server.py)
ONCE=0
[ "${1:-}" = "--once" ] && { ONCE=1; INTERVAL=0; }

while true; do
	[ "$ONCE" = 1 ] || clear 2>/dev/null || printf '\033[H\033[2J'
	printf ' violet / glissando keyboard build — %s   (refresh %ss, Ctrl-C to stop)\n' "$(date '+%H:%M:%S')" "$INTERVAL"
	hr
	printf ' PHONE (%s)\n' "<phone-ip> / USB-NCM"
	phone_block
	hr
	printf ' LAPTOP\n'
	laptop_block
	hr
	printf ' Legend: apk = toolchain install · cargo = keyboard compile (20-40 min) · dicts = word lists\n'
	[ "$ONCE" = 1 ] && exit 0
	sleep "$INTERVAL"
done
