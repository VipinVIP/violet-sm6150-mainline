#!/usr/bin/env bash
# install-glissando-on-phone.sh — put the phone-side build in place as the
# session keyboard, mirroring packaging/device/deploy.sh but with the build and
# the dictionaries already on the phone.
#
#   ./tools/install-glissando-on-phone.sh            install + switch the OSK
#   ./tools/install-glissando-on-phone.sh --dry-run  only report what it sees
#
# Nothing here needs root: it installs under ~/.local/opt/glissando and overrides
# /usr/share/applications/sm.puri.OSK0.desktop with a user copy, which is what
# phosh autostarts (X-GNOME-Autostart-Phase=Panel).
#
# Rollback: rm ~/.local/share/applications/sm.puri.OSK0.desktop  (stevia returns).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

R() { timeout 120 ./rssh "$1" 2>/dev/null | grep -av '^Warning' ; }

echo "== preconditions on the phone =="
R '
  set -u
  b=$HOME/glissando/target/release/glissando
  [ -x "$b" ] && echo "binary : $b ($(stat -c%s "$b") bytes)" || { echo "binary : MISSING (build not finished)"; exit 3; }
  d=$(ls $HOME/glissando/data/dict/*.gld 2>/dev/null | wc -l)
  echo "dicts  : $d .gld file(s)"
  echo "launch : $([ -f $HOME/glissando/packaging/device/glissando-launch ] && echo present || echo MISSING)"
'
rc=$?
[ $rc -ne 0 ] && { echo "aborting: the phone is not ready"; exit 1; }
[ "$DRY" = 1 ] && exit 0

echo "== pushing dictionaries from the laptop =="
if ls /tmp/glissando-src/data/dict/*.gld >/dev/null 2>&1; then
	# scp does not expand a quoted local glob, so stream a tar instead.
	DNS=$(ping -6 -c1 -W1 "ff02::1%enp0s20f0u4" >/dev/null 2>&1; \
		ip -6 neigh show dev enp0s20f0u4 | awk '/REACHABLE|STALE|DELAY/{print $1; exit}')
	if [ -n "${DNS:-}" ]; then
		tar -C /tmp/glissando-src/data/dict -cf - . |
			ssh -T -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
				"user@${DNS}%enp0s20f0u4" 'mkdir -p ~/glissando/data/dict && tar -C ~/glissando/data/dict -xf -'
		echo "pushed: $(ls /tmp/glissando-src/data/dict/*.gld | wc -l) file(s) ($(du -sh /tmp/glissando-src/data/dict/*.gld | cut -f1))"
	else
		echo "push skipped: phone not on USB-NCM"
	fi
else
	echo "no .gld files on the laptop yet — building them is still running"
fi

echo "== installing under ~/.local/opt/glissando =="
R '
  set -eu
  src=$HOME/glissando
  P=$HOME/.local/opt/glissando
  mkdir -p "$P/bin" "$P/share/glissando/dict"
  install -m755 "$src/target/release/glissando" "$P/bin/"
  for f in glissando-launch glissando-trial glissando-session; do
      [ -f "$src/packaging/device/$f" ] && install -m755 "$src/packaging/device/$f" "$P/bin/"
  done
  cp -r "$src/data/layouts" "$src/data/emoji" "$P/share/glissando/" 2>/dev/null || true
  cp "$src"/data/dict/*.gld "$P/share/glissando/dict/" 2>/dev/null || true
  echo "installed: $(ls "$P/bin" | tr "\n" " ")"
  echo "dicts in prefix: $(ls "$P/share/glissando/dict" 2>/dev/null | wc -l)"
'

echo "== switching the on-screen keyboard =="
R '
  set -eu
  P=$HOME/.local/opt/glissando
  mkdir -p "$HOME/.local/share/applications"
  sed "s|^Exec=.*|Exec=$P/bin/glissando-launch|" \
      /usr/share/applications/sm.puri.OSK0.desktop \
      > "$HOME/.local/share/applications/sm.puri.OSK0.desktop"
  grep -E "^Exec=" "$HOME/.local/share/applications/sm.puri.OSK0.desktop"
'

echo
echo "Installed. The override takes effect the next time the session keyboard is"
echo "started (log out/in or restart the session). To try it in the running"
echo "session without logging out:"
echo "    ./rssh \"pkill -f phosh-osk-stevia; sleep 1\""
echo "phosh restarts the OSK from the (now overridden) desktop entry."
