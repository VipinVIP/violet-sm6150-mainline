#!/bin/sh
# Install the Violet camera on the phone (run on the phone as the normal user, from the directory holding the files):
#   vcamd.c violet-camera.py violet-shot.py violet-cam-app.py vpipe.py
set -e
D=$HOME/violet-camera
mkdir -p "$D" "$HOME/Pictures" "$HOME/.local/share/applications"
cp vcamd.c violet-camera.py violet-cam-app.py vpipe.py "$D/"
gcc -O2 -Wall -fopenmp -o "$D/vcamd" "$D/vcamd.c" -lm
cat > "$HOME/.local/share/applications/violet-camera.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Violet Camera
Comment=Fast ZSL camera with autofocus
Exec=python3 $D/violet-cam-app.py
Icon=camera-photo-symbolic
Categories=GNOME;GTK;Graphics;Photography;
StartupNotify=true
X-Purism-FormFactor=Workstation;Mobile;
EOF
echo "installed to $D"
