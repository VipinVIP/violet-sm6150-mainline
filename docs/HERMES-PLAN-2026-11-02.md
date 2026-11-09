# Plan for Hermes - violet, after the user's unplugged test (2026-11-02 afternoon)

Phone: build #183, `7.2.10-sm6150`, USB cable unplugged. Tree: `~/violet-mainline` (not git; patches/ + docs/ are the source of truth).

## What the user observed (unplugged, by hand)
1. `sudo reboot` in a terminal: plymouth showed for a few seconds, then the phone froze. After ~1 min, holding power ~10 s rebooted it.
2. Sound Recorder records and plays back, but its playback is quiet. Normal videos/songs are at normal volume.
3. After that reboot WiFi never appeared (no wlan0 in the UI), so NewPipe could not be tested.
4. Power button turns the screen off/on and audio keeps playing. This is Phosh blanking, not suspend; suspend only happens after 30 s idle with nothing playing.

## Standing rules (from the user; non-negotiable)
- **Search online first** for every item (lore.kernel.org, pmaports GitLab/MRs, sm7150-mainline / sdm845 forks, Debian hexagonrpc) and cite what you find. Most of these have prior art.
- Facts only: every claim from a command output or a cited source. Real fixes, no workarounds that hide a bug (if something is a workaround, say so in the docs).
- Wrap anything that can hang in `timeout` (`sync`, `rc-service stop`, scp). Never wait >30 s without checking why. ssh over WiFi costs ~2.6 s/command: use `-o ControlMaster=auto -o ControlPath=/tmp/ssh-mux-%C -o ControlPersist=900`.
- Never `pkill -f` a pattern that matches your own shell.
- Verify by driving the phone like a user. Take a screenshot before each tap sequence. Say "verified in the UI" only if it was.
- Record each result in `docs/PROGRESS.md`, `docs/STATUS.md`, `README.md`, `patches/` + `patches/README.md`.

## Order of work

### 1. Reboot/shutdown hang (highest: it costs a hard power-off every time)
Suspects, in order (measure; do not guess):
- **`hexagonrpcd-adsp-sensorspd` stop hangs.** Already seen today: `rc-service ... stop` blocks while the daemon sits in a FastRPC ioctl and needs SIGKILL. OpenRC waits for it at shutdown.
- **Modem/rmtfs order at shutdown.** LKML 2019 ("qcom_q6v5: don't auto boot remote processor") says stopping the modem after rmtfs is gone leaves the modem in limbo. `violet-modem` is started from `/etc/local.d`, so check that OpenRC stops it *before* rmtfs/tqftpserv.
- A D-state task in `sync` or umount (seen before with the ADSP wedge).

How to find which: keep a laptop stream running during a reboot so the last lines survive:
```
ssh user@<phone> 'sudo -n dmesg -wT' > reboot-dmesg.txt &
ssh user@<phone> 'sudo -n sh -c "rc_verbose=yes reboot"'
```
Also enable `rc_logger="YES"` in `/etc/rc.conf` (log at `/var/log/rc.log`, read after the next boot) and check pstore (`/sys/fs/pstore`) after the forced restart.

Likely fixes, applied only once the log names the stage:
- In `/etc/init.d/hexagonrpcd-adsp-sensorspd` set `retry="SIGTERM/3/SIGKILL/2"` (supervise-daemon honours it), or add `stop_post` that SIGKILLs.
- In `/etc/init.d/violet-modem`, make `stop()` write `stop` to the remoteproc and wait (bounded, `timeout`) for `offline`. Its `need rmtfs tqftpserv` makes OpenRC stop it before rmtfs, but only if OpenRC has it marked started (`rc-status` after boot).

**Verify:** `sudo reboot` from the phone's terminal app, unplugged, 2 times. Pass = back at the lock screen in <100 s with no button press. `/var/log/rc.log` shows every service stopped. Also try "Restart" from the Phosh power menu once.

### 2. WiFi missing after boot (modem)
First collect facts from the bad boot. If it is gone, from the next boot that has no wlan0:
- `/var/log/violet-modem.log` (attempts, "no wlan0 after 120s")
- `cat /sys/class/remoteproc/remoteproc1/state`
- `dmesg | grep -E "modem|fatal|qrtr|ath10k|wlfw"`
- `rc-service rmtfs status; rc-service tqftpserv status; pgrep -a rmtfs`
- `/var/lib/rmtfs` present and writable

Known so far: in about 1 of 3 boots the first start gets `fatal error without message` exactly 40.0 s after "modem is now up". `docs/PROGRESS.md` (2026-10-25/26) names a candidate: the modem sends one QRTR HELLO that is dropped before the glink endpoint callback is installed, so the name service never sees it. A hard power-off right after a hung shutdown may also leave rmtfs/EFS state bad, so fix item 1 first and check whether this goes away.
- Search: "qrtr hello dropped glink", "qcom_glink_create_ept callback race", pmaports issues for sm6150/sm7150 "modem fatal error 40 s".
- Candidate test, one boot each: QRTR_SMD + GLINK_SMEM + Q6V5_PAS built in (`=y`) vs modules. Compare the fatal rate over ~3 boots.

**Verify:** 3 boots unplugged. Each boot: WiFi icon in the status bar and connected within ~100 s; `dmesg | grep -c "fatal error"` = 0; screenshot of the status bar.

### 3. Sound Recorder playback quiet (likely capture level, not playback)

> **DONE 2026-11-02 - confirmed by ear by the user at 30 cm and 5 cm.** Root cause was `TX_DEC0` (88 -> 100,
> +12 dB; `ADC1` was already at its hardware max). See the PROGRESS entry "2026-11-02 15:45" and the
> `Audio: mic capture gain` row in STATUS.md.
Videos are loud and the recorder is quiet, so the speaker path is fine. The recording itself is probably low.
- Measure the newest recording: `sox <file> -n stats` (peak and RMS dBFS). Speak at 30 cm. If peak is below about -20 dBFS, the capture gain is low.
- Current gains: ADC1 20, TX_DEC0 88 (`phone/violet-audio-setup`). Search for the vendor/sm7150 values (UCM `HiFi.conf` for wcd937x, `TX_DEC0 Volume`, `ADC1 Volume`) and raise in steps. Check for clipping (peak <= -1 dBFS) on a loud clap.
- Rule out the app: play the same file with `paplay` and compare loudness with a known song at the same volume.

**Verify:** record 5 s of speech in Sound Recorder (UI), play it back at the same volume as a song. Report `sox stats` peak/RMS before and after the gain change. The user confirms by ear.

### 4. Suspend and the power button (confirm the real case)

> **DONE 2026-11-02.** Wake source is `IRQ 19 pm8941_pwrkey` (RTC alarm = IRQ 103); USB returns ~7 s after
> resume via patches/0036; audio playback blocks idle suspend after enabling the `is-alsa-playing` plugin
> (patches/0037). Still open: this is userspace scaffolding over a dwc3 resume bug - see the fix-quality
> audit in STATUS.md.
Already done: elogind hook `/etc/elogind/system-sleep/no-hexagonrpcd-on-suspend.sh` (copy in `patches/0035-...`) stops hexagonrpcd and unbinds the USB gadget UDC around sleep. Idle suspend after 30 s works, and resume showed no ADSP crash. Still open: the 2026-11-02 resume woke after only 5.5 s and no button was pressed; the wake source is unknown.
- After each resume read `cat /sys/power/pm_wakeup_irq` and `cat /sys/kernel/debug/wakeup_sources` (sort by `wakeup_count`) to name the wake source.
- Check that gsd-power does not suspend while audio plays (it should not: PipeWire takes an idle inhibitor).

**Verify (user-style, unplugged, nothing playing):** screen off with the power button, wait 45 s, `dmesg` must show `PM: suspend entry`. Then press the power button: the screen comes on, `pm_wakeup_irq` = the pwrkey IRQ, no `fatal`/`crash` in dmesg, WiFi reconnects, a song plays, and a sensor reads (auto-rotate). Repeat once with music playing: it must not suspend.

### 5. NewPipe (after WiFi is reliable)
- Regular (non-live) video, unmuted: record with the laptop mic or the phone's Sound Recorder and correlate with the video's audio (yt-dlp the same video on the laptop as reference).
- Live 403: NewPipe 0.29.1 is the newest release and its notes have no fix. Decide on a practical path: Firefox (mobile UA) on youtube.com, or `yt-dlp` + `mpv` (yt-dlp handles PoTokens via plugins). Test one live stream for 5 min each.

## Deliverables per item
A `docs/PROGRESS.md` entry (what was measured, sources, result, open points), the `docs/STATUS.md` row, a `README.md` line if user-visible, and a patch or script in `patches/` with a `patches/README.md` index line.
