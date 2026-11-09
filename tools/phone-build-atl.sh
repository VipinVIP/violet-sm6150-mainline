#!/bin/sh
# Build ATL (Android Translation Layer) master with our phone fixes ON THE PHONE, as the login user.
# Needs (apk): git build-base meson java-common openjdk8-jdk openjdk17-jdk apache-ant android-build-tools maven
#   pc:alsa pc:glib-2.0 pc:gtk4 pc:gudev-1.0 pc:libportal pc:openxr pc:vulkan pc:webkitgtk-6.0 pc:libsecret-1 ffmpeg-dev
#   bionic_translation-dev art_standalone-dev libandroidfw-dev gmobile-dev android-translation-layer
# Stage /tmp/atl-phone-fixes.diff (patches-atl/) first.  Pinned base: 37b8ed08 (2026-11-02), the diff applies cleanly there.
# Three-step JDK dance (see the notes): ninja under JDK 8 fails at the upcall generator, `ninja upcalls.h` under JDK 17,
# then ninja again under JDK 8 (compiling the Java parts with JDK 17 breaks TLS: cipherSuite == null).
set -eu
J8=/usr/lib/jvm/java-8-openjdk
J17=/usr/lib/jvm/java-17-openjdk
cd "$HOME"
[ -d atl-master ] || git clone https://gitlab.com/android_translation_layer/android_translation_layer.git atl-master
cd atl-master
git checkout -q 37b8ed08e5820258b201f666fee49c8d818c68fc
if git apply -R --check /tmp/atl-phone-fixes.diff 2>/dev/null; then echo "fixes already applied"; else git apply /tmp/atl-phone-fixes.diff; fi
rm -rf builddir
meson setup builddir -Ddownload_tool_deps=true 2>&1 | tail -8
( export JAVA_HOME=$J8 PATH=$J8/bin:$PATH; ninja -C builddir -j4 > build1.log 2>&1 || echo "step 1 failed as expected (upcall generator)" )
( export JAVA_HOME=$J17 PATH=$J17/bin:$PATH; ninja -C builddir upcalls.h > build2.log 2>&1 )
( export JAVA_HOME=$J8 PATH=$J8/bin:$PATH; ninja -C builddir -j4 > build3.log 2>&1 )
ls -l builddir/android-translation-layer
echo ATL_BUILD_OK
