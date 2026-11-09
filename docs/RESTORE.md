# Backing up and restoring the phone's userspace

Why this exists: on 2026-11-03 an Android flash wiped `userdata` (the pmOS rootfs lives there). Our own flashing only ever
writes the `boot` partition. Everything on the laptop (kernel tree, `patches/`, `dt/`, boot images, docs, `phone/` scripts)
survives such an accident; everything installed or built on the phone does not unless it was backed up.

## Backup (laptop, phone reachable over USB-NCM or WiFi)
    host/phone-backup.sh quick     # ~300 MB, ~2 minutes: configs, services, firmware, kernel modules, usr/local, apk list,
                                   # NetworkManager profiles, and the COMPILED things as they are (Glissando install + dictionaries,
                                   # ATL build tree, NewPipe APK, launchers). NOT backed up: personal folders (Documents, Downloads,
                                   # Music, Pictures, Videos, ...), recordings, caches, cargo/maven caches, the Glissando source tree.
    host/phone-backup.sh full      # whole root filesystem (~1 GB), minutes
Output: `device-backup/phone-userspace/<kind>-<date>.tar.gz`. The archives contain secrets (the WiFi profile with its key):
keep them out of any public export. Run `quick` after every change on the phone, `full` after milestones.

## Restore
    host/phone-restore.sh check            # read-only: base rootfs image + backup are present and contain the key files
    # put the phone into fastboot (power + volume down, or `phone-reboot-bootloader.sh`)
    host/phone-restore.sh flash            # WIPES userdata, flashes ~/violet-pmos/images-r9/rootfs-r9.img (asks to type WIPE-USERDATA)
    # wait for the phone to boot on the base system, USB cable connected
    host/phone-restore.sh files            # internet over USB (sudo on the laptop), extract the backup over /, reinstall the apk list
    host/phone-restore.sh finish           # reboot, prints the checklist
`boot` is never touched (it keeps the flashed mainline kernel + the matching UUID); `dtbo` stays erased.
The base image and the boot image must be a matched pair (same baked root UUID); `rootfs-r9.img` matches the current boot images.
`flash` and `files` have not been run end to end against a wiped phone (that would wipe it); `check` was run against the real backup.

## Verify after a restore (what we checked on 2026-11-03)
- `uname -v` (the boot image you expect), `iw dev wlan0 link`, internet (`wget -qO- http://example.com`)
- audio: `pactl list short sinks sources` shows `violet_speaker` and `violet_mic` (the autostart runs `violet-audio-setup`)
- GPU: `/tmp/user-session.log` has `GL renderer: FD612`, `cat /sys/class/devfreq/5000000.gpu/cur_freq`, no hangcheck in dmesg
- sensors: `ssccli --sensor accelerometer`; orientation upright when the phone is held upright (`phone/90-violet-accel-mount-matrix.rules`)
- touch (`Detected 1080x2340 touchscreen` in dmesg), Glissando running (`pgrep glissando`), NewPipe from the app grid
- suspend: `loginctl suspend` with an RTC wake: USB `configured`, hexagonrpcd restarted, WiFi reassociated
- gotchas: `KillUserProcesses=yes` kills detached jobs when an ssh session ends (use a long-lived ssh session for builds);
  per-user settings (dconf: lock screen, caffeine, idle timers) live in `~/.config`, which the quick backup does include.
