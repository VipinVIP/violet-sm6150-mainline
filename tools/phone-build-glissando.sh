#!/bin/sh
# Build Glissando (upstream master, no local patches) ON THE PHONE and install it for the user session.
# Needs (apk): git rust cargo build-base pkgconf glib-dev cairo-dev pango-dev wayland-dev.  Run as the login user.
set -eu
cd "$HOME"
[ -d glissando ] || git clone --depth 1 https://github.com/x-vlad-x/glissando.git
cd glissando
git log -1 --format='glissando %h %cd %s' --date=short
cargo build --release -p glissando
python3 tools/build-dicts.py
P="$HOME/.local/opt/glissando"
mkdir -p "$P/bin" "$P/share/glissando/dict"
install -m755 target/release/glissando "$P/bin/"
for f in glissando-trial glissando-session; do install -m755 packaging/device/$f "$P/bin/"; done
# our hardened launcher (phone/glissando-launch-hardened.sh, staged in /tmp): sm.puri.OSK0 is a required session component,
# so every exit path must end in a working keyboard; upstream's launcher only falls back on a non-zero exit.
install -m755 /tmp/glissando-launch-hardened.sh "$P/bin/glissando-launch"
cp -r data/layouts data/emoji "$P/share/glissando/"
cp data/dict/*.gld "$P/share/glissando/dict/"
mkdir -p "$HOME/.local/share/applications"
sed "s|^Exec=.*|Exec=$P/bin/glissando-launch|" /usr/share/applications/sm.puri.OSK0.desktop > "$HOME/.local/share/applications/sm.puri.OSK0.desktop"
grep -E '^Exec=' "$HOME/.local/share/applications/sm.puri.OSK0.desktop"
echo 'GLISSANDO_BUILD_OK (do NOT swap the keyboard live with --replace: log out/in or reboot)'
