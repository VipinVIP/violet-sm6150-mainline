## 2026-11-07 14:47 - Vibrator ENABLED and flashed: pm6150_vib node turned on, driver binds, FF device present, feedbackd plays haptics

Change: `&pm6150_vib { status = "okay"; };` added to `violet-sm6150.dts` (with a comment pointing at the pmi632 register-set match). DTB rebuilt (`make ARCH=arm64 LLVM=1 qcom/violet-sm6150.dtb`), verified in the compiled DTB (`fdtdump` -> `status = "okay"`), boot image rebuilt with `mk-bootimg.sh` (O=boot-mainline-vib.img, 46 MB, sha256 0a5fbb93...), and flashed `boot` only (45000 KB, OKAY) after dumping the old partition to `device-backup/boot-before-vib-20261107.img` (64 MB, sha256 65933539c6f93442405012c79a1b0bc20c1dd27b649d5b4f56059398c73cd4d0, also kept at /home/user/boot-before-vib.img).

Verified after reboot:
- `/proc/device-tree/.../pmic@1/vibrator@5300/status` = `okay`.
- dmesg: `input: pm8xxx_vib_ffmemless as /devices/platform/soc@0/c440000.spmi/spmi-0/0-01/c440000.spmi:pmic@1:vibrator@5300/input/input4`.
- `lsmod`: `pm8xxx_vibrator` loaded, `ff_memless` in use; new `/dev/input/event4` = `pm8xxx_vib_ffmemless`; FF caps `107030000`.
- feedbackd 0.8.9 accepted `fbcli -E button-pressed` (3 quick + one 2 s). **User confirmed 2026-11-07 14:49: the long buzz was felt.** Replayed 3 short + 1 s + a double-tap rhythm afterwards as a final check.
- **Perception threshold measured** (feedbackd `Haptic.Vibrate` sweep at 0.9 strength, 2026-11-07): 10 ms not felt, 20 ms felt but "too quick", 30 ms "very feelable", 60/120 ms clear. Set `~/.config/glissando/config.toml` to `haptics = true`, `haptic_strength = 0.9`, `haptic_ms = 30` (Glissando reloads it live).
- **Why nothing buzzed before on any UI interaction:** feedbackd's default theme (`/usr/share/feedbackd/themes/default.json`) asks for `button-pressed`/`key-pressed` = 7 ms at **0.2** strength and `*-released` = 12 ms - far under this motor's ~20-30 ms spin-up. Glissando bypasses the theme with its own `Haptic.Vibrate` pattern, so only OSK keys benefit until the theme is overridden (user theme copy in `~/.local/share/feedbackd/themes/` with 0.9 / 30 ms would fix Phosh buttons and every app using TriggerFeedback). **Changed 2026-11-07 (user preferred the vendor-faithful feel, B/C of the sweep):**
- Glissando: `~/.config/glissando/config.toml` -> `haptic_strength = 0.63`, `haptic_ms = 50` (0.63*160 -> ~2790 mV on the mainline FF scale = the vendor's 2.8 V; 50 ms = the vendor's `QPNP_VIB_MIN_PLAY_MS`).
- feedbackd: `gsettings set org.sigxcpu.feedbackd max-haptic-strength 0.63` (caps every feedbackd client at the vendor voltage) and a user theme override at `/usr/local/share/feedbackd/themes/default.json` (found before /usr/share via XDG_DATA_DIRS) with `button-pressed`/`key-pressed` = 0.63 / 50 ms and `*-released` = 50 ms vibra-rumble, instead of the stock 0.2 / 7 ms.
- feedbackd reloads the theme only at startup: `pkill -x feedbackd` then any trigger auto-starts it via `/usr/share/dbus-1/services/org.sigxcpu.Feedback.service` (verified: new pid, theme active).
- Optional remaining hardening (not done): add `qcom,vib-ldo-volt-uv` to the vibrator node and clamp `vib->level` in pm8xxx-vibrator, so even a client writing FF directly to /dev/input/event4 cannot exceed 2.8 V. Needs a DTB change (boot flash), so deferred. Glissando's haptics defaults are on (strength 0.5, 12 ms per key; `~/.config/glissando/config.toml` `haptics`/`haptic_strength`/`haptic_ms` to tune), so OSK key presses should now buzz.
- Also installed the missing `/usr/local/bin/reboot-bootloader` from `phone-reboot-bootloader.sh` (it was lost in the userdata wipe), so `./enter-fastboot.sh` works again.

Rollback: `fastboot flash boot device-backup/boot-before-vib-20261107.img` (or `boot-mainline.img` of the same date), then reboot.
## 2026-11-07 14:35 - Vibration (haptic motor): works in hardware, DISABLED in mainline DT - one-line fix identified

- Hardware: violet's vibrator is the PM6150 "vibrator LDO" (`qcom,qpnp-vibrator-ldo`, SPMI 0x5300, LDO 2.8 V, vendor driver `drivers/leds/leds-qpnp-vibrator-ldo.c`). Vendor registers: STATUS1 0x08 (VREG_READY BIT7), VSET_LB 0x40/0x41, EN_CTL 0x46 (BIT7), 1504-3544 mV in 8 mV steps.
- Mainline already has the node: `pm6150.dtsi: pm6150_vib: vibrator@5300 { compatible = "qcom,pm6150-vib", "qcom,pmi632-vib"; status = "disabled"; }`. The `pm8xxx-vibrator` driver's `pmi632_regs` (enable 0x46 BIT7, drv 0x40, drv2 0x41 bits 0-3, 1504-3544 mV / 8 mV steps) matches the vendor register map exactly. Module `pm8xxx-vibrator.ko.zst` is installed.
- On the device the node is present but `status = "disabled"` (`/proc/device-tree/soc@0/spmi@c440000/pmic@1/vibrator@5300/status`), so nothing binds: no FF input device, no LED, `lsmod` has no pm8xxx-vibrator. feedbackd 0.8.9 is installed/running, and Glissando/Phosh ask it for haptics - they get nothing, so there is no vibration anywhere in the UI.
- Fix: `&pm6150_vib { status = "okay"; };` in `violet-sm6150.dts`, rebuild the boot image (DTB), flash `boot` only, reboot. Then the header's pmi632 register set drives the motor; the driver exposes an evdev FF (rumble) device that feedbackd's FF backend can use, so OSK/Phosh haptics work.
- Not done yet: needs a boot-image flash and a human to feel the motor; the phone is currently reachable only over WiFi (no USB cable for recovery), so this waits for the user.
## 2026-11-07 14:30 - Nautilus multi-select on touch; UI smoothness profiled (60 fps, no systemic bottleneck)

**Nautilus 51.0.1 multi-select on the phone (measured with real touch, `touch.py`)**
- Long-press on an item selects it and opens the item menu (Open/Cut/Copy/Move to/Copy to/Rename/Compress/Trash/Properties) - **no "Select" entry, no checkbox selection mode**.
- Dragging on empty space **scrolls** (touch pan); the rubber-band box only works with a pointer (mouse/VNC), not with a finger.
- Header menu (three dots) has **Select All**; Ctrl+A also works (16 folders selected in the test).
- So on touch: Select All (menu or Ctrl+A via the OSK); for an arbitrary subset there is no touch gesture - workaround is search-then-select-all, or a mouse/keyboard. Selection actions (Copy/Trash) then live in the header/menu.

**Smoothness profile (all measured on the device, nothing changed yet)**
- Hardware state: 8 cores, `schedutil`, little 300M-1.59G, big 300M-1.90G; GPU A612 `simple_ondemand` 435-845 MHz; thermal zones ~39 C (no throttling); load ~1.0 with the session idle; 3.4 GB RAM, 5 GB swap unused.
- GL is in use: Nautilus has the DRM render fds open, `GSK_RENDERER` unset (auto -> ngl/GL). Compositor uses freedreno (dmesg loads a612_rgmu/a630_sqe).
- Continuous icon-view scrolling for 7 s: **Nautilus 216 ticks = ~31% of one core, phoc 43 ticks = ~6%**. Overview swipes for 6 s: phoc ~7%, phosh ~12%.
- Frame pacing, GTK4 client with a 300-row scrolled list, scrolling by touch for 12 s: **758 frames, 59.5 fps, p50/p90/p99 = 16.7 ms, one 150 ms hitch; 1 frame >20 ms**. So the compositor+GTK path delivers a locked 60 fps; there is no systemic jank to fix in phoc/GTK/the SoC.
- Caveat: a first probe measured 13 fps, but its window was fully occluded behind Nautilus - GTK throttles frame clocks for obscured windows, so that number is meaningless (recorded here so nobody repeats it).
- Remaining candidates for perceived jank are app/UX-level: Nautilus icon view is the heaviest (thumbnails, ~1/3 core while scrolling), Phosh animation durations, and app startup. `org.gnome.desktop.interface enable-animations` is currently `true`; turning it off makes transitions instant but is a UX choice (not changed).
## 2026-11-07 14:00 - Clipboard/selection investigation: Firefox copy works, Bazaar selects all its description (app bug), Ghostty paste keybinds; touch injection tool for UI tests

Context: user reported "text not copyable in Firefox", "a single touch on Bazaar's app description selects the whole text", and asked how to paste a selection in Ghostty. Checked on the device (touch.py below), not by reading docs.

**Firefox (firefox-esr 140, Wayland) copy - works, measured.**
- Keyboard: Ctrl+A then Ctrl+C in the page put the text on the clipboard (`wl-paste` returned it) and it survived an app switch (still there after Ghostty took focus).
- Touch: a long-press on the page shows the selection handles and a context menu with **Copy / Select All / Print Selection / Translate Selection**; tapping Copy put the page text on the clipboard (verified with wl-paste before/after).
- So the "cannot copy" report is not a broken clipboard here. The likely cause is expectation: on Linux/Wayland, selecting text does **not** copy it (selection is the PRIMARY selection, a separate buffer), and Phosh has no GNOME-Shell-style selection toolbar. Copy must be an explicit action (long-press menu, or Ctrl+C). There is a known upstream Firefox async-clipboard bug (bugzilla 1722118/1831755: wl-paste can read an empty string while the types list is full), but it did not reproduce in this test.

**Bazaar (bazaar 0.9.10) selects its whole description on focus - app bug, root cause found.**
- `src/bz-appstream-description-render.c: text_focus_cb` is connected to `notify::has-focus` and, when the `GtkTextView` has focus, sets the accessible label and then calls `gtk_text_buffer_select_range (buffer, &start, &end)` - i.e. **select all**. That is an accessibility feature (screen readers read the focused text); on a touchscreen any tap on the description focuses it and selects everything.
- Reproduced with an injected touch tap: opening the app page leaves the whole description selected (screenshot 14:00).
- Not a GTK/phoc bug and nothing the OSK or the compositor can fix. Upstream fix would be to drop the `select_range` call (or only do it for non-pointer focus). Also present in bazaar master at 2026-11-07.

**Ghostty 1.3.2-dev paste - works, keybinds confirmed.**
- `ctrl+shift+c` copy (mixed), `ctrl+shift+v` paste from clipboard, `ctrl+insert` copy, `shift+insert` paste from the PRIMARY selection (i.e. the text you just selected in another app, no Copy needed).
- Verified: with text in the clipboard, ctrl+shift+v into `ghostty -e sh -c 'read x; ...'` pasted the whole block.
- Phone-friendly route: tap the clipboard icon in the Glissando toolbar and tap an entry; `PanelHit::Paste` -> `Op::Commit` -> `im.commit_string` inserts it into the focused app without any shortcut.

**New tool: touch injection (VNC cannot do touch).** `~/violet-ios/work/touch.py` (on the phone: `/home/user/touch.py`, run with `sudo python3 touch.py tap|long|drag x y ...`) creates a uinput touchscreen (`INPUT_PROP_DIRECT`, MT slots, BTN_TOUCH) and injects taps/long-presses/drags. Required for anything that GTK only does on touch (`gtk_event_treat_as_touch`), e.g. the OSK show path and text selection handles. Note the EV_SYN capability must not be set (uinput rejects it).
## 2026-11-07 12:35 - OSK phantom keyboard ROOT CAUSE and FIX: phoc 0.57 predates the "text-input-v3 v2" GTK 4.24 workaround; upgraded to phoc 0.58

**Symptom**: the OSK opened on screens with no text field, in several GTK4 apps - Settings (tap anything), Nocturne (swiping the album carousel), g4music (before it was removed). Not app-specific, not Glissando's fault.

**Measured**: with `WAYLAND_DEBUG=client`, GTK 4.24 enables text input on window focus, with no editable widget focused: `zwp_text_input_v3.enable()`, `set_surrounding_text("",0,0)`, `set_content_type(0,0)`, `set_cursor_rectangle(0,0,0,0)`, `commit()` (captured for Settings 12:07). phoc 0.57's relay turned `enable` into `wlr_input_method_v2_send_activate()` unconditionally (`src/input-method-relay.c: handle_text_input_enable`), so the OSK opened. zwp_input_method_v2 carries no caret rectangle, so no input method (Glissando or stevia) can filter this on its own.

**Upstream fix (prior art)**: phoc 0.58.0 NEWS: *"text-input-v3: Add basic support for version 2 to work around an issue in GTK 4.24"*. phoc 0.58 embeds wlroots 0.20.x with `subprojects/packagefiles/wlroots/text-input-v2/000{1,2,3,4}-*.patch`, advertises `zwp_text_input_manager_v3` version 2, and adds `show_input_panel`/`hide_input_panel` handling: for v2 clients `handle_text_input_enable` returns early and the IM is activated only from `show_input_panel`. GTK 4.24 has the matching side: `gtk/gtkimcontextwayland.c` sends `zwp_text_input_v3_show_input_panel()` when the compositor offers v2 - and only from a touch click on a text widget (`gtk/gtktext.c: gtk_text_click_gesture_released`) - otherwise it falls back to `enable()`.

**Change**: `apk add phoc=0.58.0-r0 phoc-schemas=0.58.0-r0 phoc-lang=0.58.0-r0` (was 0.57.0-r1), then reboot. phosh stays 0.57.0 (phosh_private went to v8, only additive: `add_thumbnail_view` + `phosh_private_thumbnail`). Backup of the 0.57 files: `/home/user/phoc-0.57.0-backup.tar.gz` on the phone. Do NOT use `apk add -u phoc`: it drags in llvm23-libs/glycin/mesa updates (~100 MB); pin the version.

**Verified after reboot**: `wayland-info` shows `zwp_text_input_manager_v3 version: 2`; the phosh session and glissando came up unchanged. Settings open on a page with no text field: `sm.puri.OSK0 Visible = false` and the client sends no `enable()`. The GTK key-capture test window (the g4music pattern) now sends **zero** `enable()` requests and the OSK stays hidden (was 1 request + keyboard). **Confirmed by the user 2026-11-07 13:40: the fix works.** A real text field opens the keyboard on touch and it hides again when tapping away. (GTK only requests the panel from an actual **touch** click, which VNC pointer events cannot simulate, so this last step had to be checked on the device.)

**Side note**: glissando upstream (1.0.0-rc.1, 00b650a = what is installed) has no caret handling at all; the "don't show without a caret" heuristic I was about to add to Glissando is unnecessary now.
## 2026-11-07 10:15 - OSK phantom keyboard is GTK key-capture (app-side), not Glissando; per-app block removed; the 31 s app-open splash was g4music-only

Follow-up to the 09:10/09:20 entries after the user rejected the `no_auto_show` block as a hack. **No phone-side workaround remains**: `~/.config/glissando/config.toml` deleted (Glissando defaults, Calculator only), g4music and amberol uninstalled.

**Symptom 1 (keyboard with no text field) - root cause is GTK's key-capture, triggered by g4music. Measured.**
- Instrumented GTK4 test windows on the phone (`~/violet-ios/work/osk2.py`, run with `WAYLAND_DEBUG=client`): a window with `Gtk.SearchBar` + `set_key_capture_widget(content)` sends `zwp_text_input_v3.enable()` at window focus **while the focused widget is a Button** (`REPORT focus=Button ... visible=True mapped=True`); the same window without key capture sends nothing; a hidden `Gtk.Entry` sends nothing. So the app asks for the keyboard with no editable on screen.
- Code path in GTK 4.24.1: `gtk_text_set_input_interceptor()` (`gtk/gtktext.c`) puts a `GtkEventControllerKey` carrying the search entry's IM context on the **capture widget**; `gtk_event_controller_key_handle_crossing()` (`gtk/gtkeventcontrollerkey.c`) then calls `gtk_im_context_focus_in()` for any focus inside that widget - i.e. GTK tells the compositor "text input is active". GTK main (4.25/4.26, file fetched 2026-11-07) still has the same code, so it is a live upstream quirk. Glissando and phoc do exactly what text-input-v3 says.
- g4music 4.6 does this from `src/ui/store-panel.vala:77` (`search_bar.key_capture_widget = win.content`) at window construction, so every focus change in the window (player page included) re-enables text input and it never sends `disable` while focused.
- Fix shape verified, then dropped with the app: arming the capture only while the search bar is open gives `enable=0` with the bar closed and `enable=1` when it opens (`gated` variant). User decision: do not patch g4music; the player will be replaced, so g4music/amberol were uninstalled (10:05) and the config block removed.

**Symptom 2 (keyboard does not go away after Enter)** is the same app-side cause: Enter leaves focus in the search entry, the app sends no `disable()`. Nothing to fix in the keyboard.

**App-open time: the 31 s Phosh splash was g4music-only. Measured from the app grid (screen frames over VNC).**
- Files (Nautilus): real UI at **~2.7 s** after the icon tap, splash gone.
- Web (Firefox): real UI at **~2.2 s** (its address-bar OSK opens - correct, it is a text field).
- g4music: splash stayed **~31 s** (measurements in the 09:10 entry).
- Why 31 s: Phosh removes a splash only on `PhoshAppTracker::app-ready`, which fires when phoc relays the startup id the app activates with (`src/splash-manager.c`, `src/app-tracker.c:315`; phoc `src/xdg-activation-v1.c` -> `src/seat.c:1354` -> `phosh-private.c`). If an app never completes that round trip, the tracker keeps extending the timeout for a live PID up to `0.9 * APP_TRACKER_MAX_INITIAL_TOPLEVEL_TIMEOUT` (~31.5 s) and then removes the splash anyway (`on_startup_timeout`). That is exactly the observed 31 s: g4music was the only app failing the handshake, Files and Firefox complete it. No systemic fix needed.

**Housekeeping**: Amberol was installed and removed (it needs "Open folder"; the user wants automatic scanning, and will install a player by hand later). gnome-music was considered and dropped (user decision). `tinysparql`/`localsearch` are dependencies of nautilus and stay. Laptop-side: `/etc/ssh/ssh_config.d/20-systemd-ssh-proxy.conf` is a symlink owned by `nobody:nobody`, so plain `ssh` fails with "Bad owner or permissions"; `ssh -F /dev/null` is the workaround (wrappers `~/violet-ios/work/prssh`, `~/violet-ios/work/vncshot.sh`, repro tool `~/violet-ios/work/osk2.py`).

Repro for the GTK behaviour if it comes back: put `~/violet-ios/work/osk2.py` on the phone and run `WAYLAND_DEBUG=client python3 osk2.py plain|searchbar|nocap|gated|hiddenentry`, then grep `text_input_v3#.*\.enable`.

## 2026-11-07 09:10 - OSK shows with no text field / stays up: not a Glissando or phoc bug; trigger measured (GtkSearchBar key capture)

Task: why does the keyboard appear on screens with no text field and sometimes not go away. **Nothing was changed on the phone** (no config, no restart, no flash); test processes were stopped.

**Prior art (web search, 2026-11-07)**
- Glissando upstream (x-vlad-x/glissando): README says the keyboard is driven by input-method-v2 + `sm.puri.OSK0`, per-app "do not auto-open" list exists (default only `org.gnome.Calculator`); 11 open issues, none about show/hide; closest is #7 "Check text input against newer GTK and phoc". Nothing found about the symptoms.
- Phosh/squeekboard trackers: squeekboard#298 (GTK4 apps fail to show keyboard until minimized - the opposite symptom), phosh#706 (keyboard re-opens on volume keys, app-specific), phosh#560 (keyboard stuck on lock screen with focused search field). GTK MR 4397 / commit "Save context even when text_input isn't around yet" (Guido Guenther, 2022): GTK's Wayland IM context sends `enable` from `focus_in`, i.e. the OSK is purely app-driven.
- "Nothing found" for an issue that names GtkSearchBar key capture + OSK; I did not find a GTK bug for it.

**How Glissando decides (source `crates/glissando/src/wl.rs`, read on the phone at `~/glissando`, upstream `00b650a`)**: `want_visible = forced_visible || (im_active && auto_show && !user_hidden && !app_blocked)`. `im_active` is set only by the compositor's `activate`/`deactivate` (phoc relays the app's `zwp_text_input_v3.enable/disable`). `forced_visible` only by a D-Bus `SetVisible(true)` (home-bar long press) and is cleared on deactivate/Hide. Glissando therefore never shows by itself.

**Measured (WAYLAND_DEBUG=client on apps started by me on the phone; D-Bus monitor on `sm.puri.OSK0` showed no `SetVisible` call at any time)**
| App / test | text-input requests | keyboard |
|---|---|---|
| Loupe, Snapshot, Papers, Settings, Nautilus | `enter` only, no `enable` | none (correct) |
| Calculator | `enable` | shown (it has an entry; it is on glissando's default block list) |
| **g4music 4.6** (player page, song list - what the user hit) | `enable()` the moment the window gets keyboard focus (`set_content_type(0,0)`, empty surrounding text, cursor rect 0,0,0,0), `disable()+enable()` again 2 s later, never a `disable` while the window keeps focus | **shown on the player page and on the plain list; stays** (screenshots) |
| g4music search: tap search, type, Enter | normal field traffic (`preedit`/`commit_string`, cursor rects); Enter produces nothing, focus stays in the live search entry | stays - correct for the protocol |
| minimal GTK4 window (`tools/osk-imtest.py plain`) | none | none |
| same + hidden `Gtk.Entry` (`hiddenentry`) | none | none |
| same + `Gtk.SearchBar` with `set_key_capture_widget(window content)` (`searchbar`) | **`enable()` at window focus, never disabled** | would show |
| same SearchBar without key capture (`nocap`) | none | none |

**Root cause of symptom 1 (measured):** an app that sets a `GtkSearchBar`/`GtkSearchEntry` key-capture widget (g4music does: `search_bar.key_capture_widget = win.content`) makes GTK 4.24.1 enable text-input for the whole window as soon as it has focus, with no field on screen. Glissando and phoc do exactly what the protocol says. (Hypothesis, not verified in GTK source: this is the `gtk_editable_set_input_interceptor` path that GtkSearchEntry uses for key capture in GTK main; I could only read part of `gtktext.c`.) Other apps with a search-as-you-type bar (Software, Contacts, Settings search...) may do the same; the sweep above only covered the apps installed that I could start (Clocks, Decibels, Showtime, Software are not installed).

**Symptom 2 (does not go away after Enter):** two measured causes, both app-side. (a) Enter in a search entry only `activate`s it; the entry keeps focus, so there is no `disable` and the OSK must stay. (b) Any window of case 1 never sends `disable` while focused, so the keyboard cannot go away until the user hides it by hand (chevron / home bar) or the app loses focus (then `leave` + `disable`, seen at app switch). `user_hidden` is cleared on the next `activate`, so touching the window again after an `disable+enable` re-opens it.

**Side effect found in Glissando:** GTK sends `disable()+enable()` back to back on every focus move between widgets (e.g. every tap in g4music). Glissando handles `deactivate` by destroying the layer surface and `activate` by creating it again, so `Visible` on `sm.puri.OSK0` flaps `false,true` within <1 ms (D-Bus monitor) - a flicker/relayout risk. Upstream-able fix idea (not written): in `wl.rs::im_done`, delay `destroy_surface` by a short timer (~100-200 ms) and cancel it on the next `activate`.

**Fix / workaround proposals - NOT applied, need the user's decision**
1. *Workaround* (config only, live, no OSK swap): add `com.github.neithern.g4music` to `no_auto_show` in `~/.config/glissando/config.toml` (file is watched live; needs `wlr-foreign-toplevel`, which phoc advertises - verified in the registry). Cost: the keyboard no longer opens automatically in g4music's search; the home-bar long press still shows it. Must be repeated per affected app.
2. *Root-cause fix*: g4music (drop the key-capture widget or only set it while the search bar is revealed) and/or GTK (do not enable the IM when the interceptor widget, not the entry, has focus). Report upstream; not filed.
3. *Glissando improvement*: the hide debounce above.
Repro/tools for later: `tools/osk-imtest.py <plain|searchbar|nocap|hiddenentry>` (run on the phone with `WAYLAND_DEBUG=client`), `tools/wl-debug-run.sh`.

**UPDATE 2026-11-07 09:20 - workaround 1 APPLIED with the user's OK ("Apply block")**: `~/.config/glissando/config.toml` on the phone now contains only `no_auto_show = ["org.gnome.Calculator", "com.github.neithern.g4music"]` (Calculator kept because setting the key replaces the default list; every other key falls back to defaults via `#[serde(default)]`). Glissando watches the file: no restart, no OSK swap. Measured effect: g4music's search entry was focused with text-input enabled and the keyboard stayed hidden (screenshot 09:13). Cost as stated above: no automatic keyboard in g4music search; home-bar long press still opens it. Revert: delete that file. This is a workaround, not a root-cause fix (proposals 2 and 3 remain open).

**g4music slow start via the Phosh icon (user report: 10+ s) - REPRODUCED 2026-11-07; the delay is NOT in the app.** Tapping Gapless (Media folder) in the Phosh grid: Phosh's splash (app icon + spinner) stayed for **~31 s** (press at +1.0 s, real UI first seen at +32.5 s; earlier runs still on the splash at +12 s and +18 s). The same app launched without Phosh's splash shows its UI in **~3.4-3.7 s**: direct `/usr/bin/g4music` over ssh, `gtk-launch`, and the exact D-Bus call (`org.freedesktop.Application.Activate`) all measured ~3.4-3.7 s (screen polling; the VNC capture can return a stale frame when nothing redraws, so only runs whose pre-check was dark are strictly valid: the D-Bus run at +3.7 s; the others agree within 0.4 s). D-Bus monitor of an icon launch: Phosh calls `Activate` after 0.84 s with `desktop-startup-id` = `activation-token`; the service starts at +1.1 s, replies at +1.9 s, window actions appear at +2.1 s, then g4music is quiet on the bus. Process threads were idle during the splash (not CPU- or IO-bound). `GST_PLUGIN_FEATURE_RANK` (set in the session, not in ssh) was tested and is NOT the cause (UI ~3.4 s with it set). Reading: the app is ready in ~3.5 s but Phosh keeps its splash until ~30 s, i.e. it does not get/accept the "app ready" signal for this startup-id (phosh issue #811 describes slow splashes covering the app until they time out; Phosh's `splash-manager.c` removes a splash on `app-ready`/`app-failed`/closed, source of the signal not read). Not verified: what exactly Phosh waits for, and whether the splash is cut by a timeout (the ~31 s hints at one). Next, if wanted: Phosh logs with `G_MESSAGES_DEBUG=phosh-startup-tracker` need a Phosh restart (not done); compare with another DBusActivatable GTK4 app's splash time (Loupe/Papers) to see if it is g4music-specific (`DBusActivatable=true`, `StartupNotify=true`).
(old note kept below for the measurements: strace breakdown etc.)
**g4music slow start (user report: 10+ s) - NOT reproduced, cause not established.** Library is 3 files (11 MB), caches present, so scanning is not it. Measured: isolated D-Bus session (theme differs: white window, not representative) window at +2.0 s; real session via `gtk-launch com.github.neithern.g4music` content on screen by +3.3 s; under `strace -f` ~7 s, spread over libgstreamer/GStreamer init (~1.9 s before the Wayland connect), GTK init (fonts, vulkan pipeline cache), GStreamer plugin loads (typefind, isomp4, libav, ...) while opening the current track, then cover decode through glycin/bwrap; after load it renders at a constant ~60 fps (rotating cover). Phone load average was 1.7-3.3 (WebKit/epiphany/sound-recorder running, plus my own debug loggers). A tap on the Gapless icon in the Phosh app grid shows Phosh's splash (app icon + spinner) while the app starts; I did not get a clean timed run of that path. To do: time the first launch after a reboot (cold page cache) by tapping the icon, with nothing else running. Note for drivers of the UI over VNC: a plain `click 1` on a Phosh grid icon did nothing; `mousedown`/`mouseup` with a short pause works.
## 2026-11-04 (morning) - front camera fixed (driver) + libcamera soft-ISP tuning started

Full details, state and next steps: **`docs/HANDOFF-2026-11-04-camera.md`**. Summary:

- **Front camera darkness FIXED in the driver.** `ov13855_init_controls()` defaulted `V4L2_CID_VBLANK` to 82 and `ov13855_start()` rewrites `0x380e` from it after the mode table, so the frame length became 1650 lines (~49 fps) instead of the vendor's `0x0c8e` = 3214 (30 fps). Max exposure is `VTS-8`, so the sensor got exactly half the light. Now `OV13855_VBLANK_DEFAULT = 0x0c8e - 1568` = 1646: max exposure 3206, 28 fps, 2.05x more light at the ceiling (raw signal 16 % -> 33 %). Module installed and verified across a reboot.
- **Gain ceiling measured**: `0x3508/0x3509` at `0x0f80` (15.5x) changes nothing; the real OV13855 maximum is `0x07c0` (7.75x), so the control range stays 128..1984.
- **Build trap**: `make M=drivers/media/i2c ov13855.ko` compiles without `-DMODULE` (no `CONFIG_VIDEO_OV13855` in .config) -> `U init_module` -> "Unknown symbol init_module" on load. Use `CONFIG_VIDEO_OV13855=m` on the make line and check `nm`.
- **libcamera 0.7.2 built natively on the phone into `/usr/local`** (system libcamera untouched, desktop unaffected) and patched: adaptive AWB smoothing (kills the startup green flash, G/R 4.00 -> 1.30), highlight-weighted AGC (inert until >2 % of pixels are in the top histogram bins), and a tone shoulder at knee 0.85 in both the packed/unpacked shaders and the CPU debayer LUT. Patch + tooling in `patches/proposed/libcamera-*`. A/B over 8 frames: no flash, settled cast 1.09 vs 1.03, mean 160 vs 165, 0 % clipped.
- **Still open**: the shoulder is unproven against a genuinely clipped object; the residual grey-world cast needs CCM/tuning work; nothing decides yet whether the desktop should use the patched libcamera; autofocus still has no VCM driver (i2c 0x0c undriven).
- **Backups**: `device-backup/phone-userspace/quick-20261104-0803.tar.gz` (678 MB) and `device-backup/camera-fix-20261104-0803.tar.gz` (driver/docs/cap.sh).

## 2026-11-04 07:30 - front camera too dark: frame length overrode the vendor 30 fps timing (driver FIXED)

- **Symptom**: the front OV13855 preview was unusably dark, while libcamera's AGC sat pinned at *both* limits (`exposure 1642/1642`, `analogue_gain 1984/1984`) - starved of light, not mis-tuned. Raw frames confirmed it: at max exposure+gain the scene only reached 16 % of full scale above black level (64).
- **Root cause**: `ov13855_init_controls()` created `V4L2_CID_VBLANK` with default **82**, and `ov13855_start()` calls `__v4l2_ctrl_handler_setup()` after the mode table, so `0x380e` was rewritten to 82+1568 = **1650 lines** at every stream start. The vendor mode table's own frame length is `0x0c8e` = **3214 lines** (30 fps). Max exposure is `VTS-8`, so the sensor integrated 1642 lines at ~49 fps instead of 3206 at ~28 fps - **exactly half the light (1 stop)**.
- **Proof** (same scene, minutes apart): vblank 82 -> mean 221 (signal 157); vblank 1646 -> mean 371.5 (signal 307) = **1.96x**; 60 frames in 1.22 s vs 2.18 s. Registers read back from the chip: `0x380e = 0x0672` before, `0x0c8e` after.
- **Fix** (`kernel/linux-7.2.10/drivers/media/i2c/ov13855.c`): new `OV13855_VBLANK_DEFAULT (0x0c8e - OV13855_HEIGHT)` = 1646, used as the VBLANK control default, for `s->vblank` in probe, and for the exposure range (max is now 3206). Module rebuilt and installed in `/lib/modules/7.2.10-sm6150/extra/ov13855.ko`.
- **Gain ceiling measured**: writing `0x0f80` (15.5x) produces *no* change in the captured signal - `0x07c0` (7.75x, `analogue_gain` 1984) is the real OV13855 maximum, so the range stays 128..1984 (a wider range would only let the AGC push a gain that does nothing).
- **Verified after a reboot** (module autoloaded from disk): `0x380e = 0x0c8e` at stream start, exposure max 3206, 60 frames in 2.18 s (~28 fps), signal at max exposure+gain **321/959 = 33 %** of full scale (was 16 %).
- **Build gotcha**: `make M=drivers/media/i2c ov13855.ko` alone compiles the object WITHOUT `-DMODULE` (there is no `CONFIG_VIDEO_OV13855` in .config), giving a .ko with `U init_module` that fails to load with "Unknown symbol init_module (err -2)". Use `make ARCH=arm64 LLVM=1 M=drivers/media/i2c CONFIG_VIDEO_OV13855=m ov13855.ko` and check `nm ov13855.ko | grep " T init_module"`.
- **Reload gotcha**: the module refcount is held by v4l2-async, so `rmmod ov13855` fails with "in use" even with no open fds. `echo 3-0036 > /sys/bus/i2c/drivers/ov13855/unbind`, then rmmod/modprobe (or just reboot - the .ko is on disk). Killing `wireplumber` first is still required (`fuser /dev/media0`).
- **Rear harness bug found**: rear captures fail with `Failed to start media pipeline: -32` (link validation) when the pads are set to `SBGGR10` - the imx586 subdev's mbus code is **`SRGGB10`** (video pixelformat `pRAA`). `/var/tmp/cap.sh` was fixed and a copy is now in `phone/cap.sh`.

## 2026-11-03 19:35 - backup profile for fast restore + scripted restore

- `host/phone-backup.sh quick` now keeps the compiled things as they are (Glissando install + dictionaries, ATL build tree, NewPipe APK, launchers, kernel module tree 7.2.10-sm6150) and drops personal folders, recordings and caches: `quick-20261103-1932.tar.gz`, 298 MB, 7628 entries. `full` is unchanged (whole rootfs, ~1 GB).
- `host/phone-restore.sh check|flash|files|finish` (flash base rootfs, give the phone USB internet, extract the backup, reinstall the saved apk list); `check` was run against the real backup, `flash`/`files` have not been run end to end (that needs a wipe). Procedure and the verification list: `docs/RESTORE.md`.

## 2026-11-03 19:10 - Glissando OSK, ATL master (+ our fixes) and NewPipe rebuilt after the userdata wipe

- **Glissando** (upstream master `00b650a`, no local patches): built on the phone (`tools/phone-build-glissando.sh`: `cargo build --release -p glissando`, `tools/build-dicts.py` for en/de/ru from the pinned-checksum word lists), installed under `~/.local/opt/glissando`, `~/.local/share/applications/sm.puri.OSK0.desktop` overridden. Our hardened launcher (`phone/glissando-launch-hardened.sh`) replaces upstream's `glissando-launch`: `sm.puri.OSK0` is a required session component, so every exit path must end in a keyboard. After a reboot (never swap the OSK live): `glissando` is the running OSK, stevia is not, the session is intact.
- **ATL master + fixes**: `tools/phone-build-atl.sh`. Base `37b8ed08` (2026-11-02), `patches-atl/atl-phone-fixes.diff` applies cleanly, three-step JDK dance (JDK 8 ninja fails at the upcall generator -> `ninja upcalls.h` under JDK 17 -> ninja under JDK 8), binary in `~/atl-master/builddir/`. The phone cannot reach gitlab.com (connect timeout), so the source was cloned on the laptop and copied over.
- **NewPipe 0.29.1** from the official GitHub release (signing cert SHA-256 `CB:84:06:9B:...:5C:AB`, same as the one published in NewPipe's README) -> `~/atl/NewPipe.apk`; launcher `phone/newpipe-atl.desktop`, `atl-run`/`atl-run-master`, `libatl-swipe-back.so` (built from `phone/atl-swipe-back.c`).
- **Test**: `atl-run-master` NewPipe for 100 s: window focused, network sockets opened, no crash, no GPU fault/hangcheck. Confirmed by the user: NewPipe works (2026-11-03 19:15).
- **Pitfall found**: `KillUserProcesses=yes` (logind.conf.d, restored with the other settings) kills every process started from an ssh session when that session ends, including detached `nohup`/`setsid` jobs; keep the ssh session open for long jobs (`~/violet-ios/tools/phlong`).
- **Slip**: my source swap ran `rm -rf atl` and deleted `~/atl` (the NewPipe APK); re-pushed.

## 2026-11-03 18:10 - after the restore: orientation rule, notch overlay, GPU compositing back on

Three leftovers of the userdata wipe, found by the user:
- **UI upside down.** Measured with the phone held upright by the user: raw accelerometer Y = +8.8 m/s2 and `AccelerometerOrientation` = `bottom-up` (libssc 0.4.4 / iio-sensor-proxy 3.9-r2 on the rebuilt rootfs). On 2026-10-30 the raw frame was already correct (upright Y = -9.92) and the mount-matrix rule was the bug (retraction 21:55); on this install the frame is rotated 180 degrees about Z, so the rule is needed: `phone/90-violet-accel-mount-matrix.rules` (`ACCEL_MOUNT_MATRIX="-1,0,0;0,-1,0;0,0,1"` on `fastrpc-adsp-secure`) -> `/etc/udev/rules.d/`, `udevadm trigger`, restart iio-sensor-proxy. Confirmed by the user: UI upright. Rule of thumb stays: re-measure upright before touching it.
- **Notch.** libgmobile has no cutout data for xiaomi,violet: `phone/gmobile/xiaomi,violet.json` -> `/usr/local/share/violet-gmobile/`, selected by `export G_RESOURCE_OVERLAYS=/mobi/phosh/gmobile/devices/display-panels=/usr/local/share/violet-gmobile` in `/home/user/.phoshdebug` (sourced by phosh-session). Env confirmed in phoc's environment; confirmed by the user: the status bar clears the notch.
- **Software rendering.** The base rootfs carries `/etc/profile.d/90-violet-pixman.sh` (`WLR_RENDERER=pixman`, an Oct-25 bring-up workaround from before the memory fix). It was active after the restore, so phoc composited in software. Renamed to `.disabled` (as before); after a reboot phoc logs `Using OpenGL ES 3.2 Mesa 26.2.4, GL vendor: freedreno, GL renderer: FD612`; `devfreq 5000000.gpu` ramps to 845 MHz; 0 hangcheck/fault/iommu/dpu-timeout lines.
- Also: `host/phone-backup.sh full` over a USB link stalls when the cable is pulled; it now falls back to WiFi and was restarted over WiFi.

## 2026-11-03 18:00 - userdata wiped by an Android flash; phone rebuilt from the repo (restore + verification)

**What happened.** Another session flashed an Android image and wiped `userdata` (the pmOS rootfs lives there; our own flashes only ever wrote the `boot` partition). The `modem`, `dsp`, `persist` and `vendor` partitions were intact (still mounted by msm-firmware-loader with adsp/modem/bdwlan firmware). The kernel work (patches, DTS, boot images, docs, `phone/` scripts) lives on the laptop and was not affected. `userdata` was reflashed with the base `rootfs-r9.img`, the 7.2.10 module tree installed; the boot image is the shared-tree build #188 (camera work on top of 0038-0040).

**Rebuilt from the repo (all verified on the phone, 2026-11-03, build #188):**
| Item | How restored | Evidence |
|---|---|---|
| Packages | `apk add rmtfs hexagonrpcd(+openrc,udev) qrtr iw alsa-utils gnome-sound-recorder gnome-console py3-evdev` (phone got internet over USB-NAT through the laptop) | `apk info -e` |
| GPU firmware | `a612_zap.*`, `a612_rgmu.bin`, `a630_sqe.fw` from the Oct-18 extras tarball into `/lib/firmware/qcom` | dmesg: SQE + RGMU loaded at 19 s, no zap error, `devfreq 5000000.gpu` 435 MHz |
| Modem + WiFi | `phone/rmtfs.initd`, `violet-modem.initd`, `/var/lib/rmtfs`, `ath10k/WCN3990/hw1.0/{firmware-5.bin,board-2.bin}` (violet board data) | modem up in 1 s, `queued 52 B received before probe` (patch 0038 path), `wlan0` UP <lan-ip>, internet OK, associated to <home-ssid> |
| Sensors | `phone/install-sensors.sh` + `fw/sensors/violet-sensors.tar.gz`, `hexagonrpcd-adsp-sensorspd.initd` | `ssccli`: accelerometer live (8.5, -0.18, 5.06 m/s2), light live (105 lux), proximity FAR |
| Audio | `violet-audio-setup` + autostart, `modprobe.d` `no_rca_mode=2` | `violet_speaker` + `violet_mic` created at session start; speaker->mic loopback of a 440 Hz tone: 440 Hz peak found in 3 of 13 half-second windows |
| Touch | kernel 0040 (panel follower) | `Detected 1080x2340 touchscreen` at 6.0 s |
| Autologin | `/etc/phrog/greetd-config.toml` `[initial_session]` -> `phosh-session-logged` | phosh session starts at boot |
| Suspend/resume | `/etc/elogind/system-sleep/no-hexagonrpcd-on-suspend.sh` (patches/0036), `sleep-inhibitor.conf` `is-alsa-playing`, `logind.conf.d` (HandlePowerKey=ignore, KillUserProcesses=yes) | `loginctl suspend` + RTC wake: hook ran, USB `configured` (0039), hexagonrpcd restarted, ADSP `running`, WiFi reassociated, no `ep0out`/sensor_process errors |
| Charging | `violet-vbat` module in the restored module tree | battery 100 %, Full |
| Misc | NM `wifi.cloned-mac-address=stable`, IPv6 off on wlan0 sysctl, `tap.py`/`taps.py`/`key.py` in `/usr/local/bin` | files present |

**NOT restored (lost with userdata or not re-done):**
- `tas2563_coef.bin` (vendor `tas2563_uCDSP.bin` came from the Android ROM's vendor image; it is not on any partition of the phone). The amp runs in ROM mode (`no_rca_mode=2`); the tone loopback shows the speaker plays.
- (ATL master build, NewPipe and the Glissando keyboard were rebuilt later the same day, see the 19:10 entry above.)
- The `violet-screenshot-keys` service, `displayboot`, the `modem-trace` diagnostic.
- gsettings that were customised: Phosh lock screen `require-unlock` is back to `true` (the earlier setting was `false`; left for the user to decide), caffeine, idle timers.
- Personal data in `/home/user` and the Sound Recorder recordings.

**Lesson / fix:** no routine backup of the rootfs existed. Added `host/phone-backup.sh` (`quick`: configs + scripts + firmware + home + apk list, 7 MB; `full`: whole root filesystem) writing to `device-backup/phone-userspace/`. The archives contain secrets (the WiFi profile with its key): keep them out of any public export. First snapshots taken 2026-11-03 17:50 (quick) and 17:51 (full, running).

## 2026-11-03 17:55 - camera: three cameras noted; vendor init table not in the module data

- Hardware note: violet has **two rear cameras and one front camera** (CAMX lists 5 camera devices; the IMX586 is
  the rear main, cameraId 1). The vendor ships per-module data for ofilm / semco / sunny IMX586 variants.
- Checked all three `com.qti.sensormodule.*_imx586.bin`: every one has an **empty `sensorDriverData`** (24 zero
  bytes), so the init sequence is not in the module data - it is code in `camera.qcom.so` (or built at runtime).
- The vendor kernel (Elixir's) has no per-sensor driver symbols; only the generic `cam_sensor_*` stack, so the
  kernel cannot supply the table either.
- kprobes on `cam_cci_i2c_write_continuous_table` did not fire during a camera start in this test.

State: Android remains the working oracle; mainline still cannot capture. The immediate question remains
whether the IMX586 uses the 0x3000 register block (our current table) or the SMIA block (0x0100/0x0114/0x0340),
which the vendor's own writes would settle.

## 2026-11-03 17:40 - camera: direction check (external review) + a likely register-map error

External review of the mainline symptoms flagged a real possibility: **the IMX586 may not use the 0x3000-block
register map** that the public Raspberry-Pi table writes. Evidence in our own data supports this:

- The chip ID reads correctly at **0x0016** (`0x0586`) - that is the SMIA-style ID register, and our driver's
  own exposure code already uses SMIA (`0x0202`).
- The kprobe captures of the *vendor* CCI writes showed small register addresses (values like 0x0112, 0x000a),
  i.e. SMIA-space addresses - not 0x30xx.
- So `0x3014`/`0x3040` reading back 0x00/0x01 on mainline is probably *not* a lane strap; those addresses may
  simply not be the registers we think they are, and the "2-lane module" conclusion is now doubtful.
- The vendor's DT (read from `/proc/device-tree` on Android) gives `cci-master = 1`, `csiphy-sd-index = 0`,
  `cell-index = 1` for `qcom,cam-sensor@1`, and no lane property - so lane count must come from the sensor's own
  settings, not the DT.

Recommended order (cheap first):
1. On mainline, read the SMIA frame counter (`0x0005`) before/after the stream-on write. If it does not start
   incrementing, the sensor never streamed and the init table/map is the problem, not the CSI link.
2. Get a real init sequence from the vendor side (sensor library / XML / CAMX), not by guessing 0x3000 values.
3. Only then revisit CSI PHY/settle/lane configuration.

State: Android 15 (Elixir) is installed and its camera works (the oracle). Root adb, kernel CAM debug, CAMX
verbose logs, kprobes and a 103 MB dump of the camera provider's anonymous memory are all in place
(`~/violet-ios/cam/memdump`). Scans of that dump for an SMIA table did not find a clean one yet.

## 2026-11-03 17:20 - Android: CAMX verbose logs on, sensor module identity, register-table access still partial

Progress on the oracle:
- `setprop persist.vendor.camera.logInfoMask/logVerboseMask/logWarningMask 0xFFFFFFFF` turns on full CAMX
  userspace logging (VERB level). Logcat then shows the sensor module data and EEPROM parsing.
- Camera modules for cameraId 1: **ofilm_imx586 / semco_imx586 / sunny_imx586**; at one point the HAL logged
  `ProbeImageSensorModules() lxl Sensor not detected for sensor_name = imx586` (after repeated provider kills -
  needs a clean reboot to be trustworthy).
- CAMX looks for `/vendor/etc/camera/camxoverridesettings.txt` (absent); that file is the lever for deeper
  overrides if we need them.
- Kernel side: `debug_mdl=0xFFFFFFFF` logs CAM-CCI / CAM-SENSOR / CAM-EEPROM (reads and EEPROM bursts are
  visible, writes are not).
- kprobe nested fetchargs work but only one level deep (`+0(+0(%x1))`), which is enough at
  `cam_cci_i2c_write_table_cmd` but the values there look like CCI queue words, not sensor registers; at
  `cam_cci_i2c_write` the reg-setting is two indirections away.

Next: reboot Android for a clean camera state, then attack the capture from the CAMX side (it is the component
that owns the register table) - either via an overridesettings file with a settings/dump key, or by capturing
the ioctl payload the HAL hands to /dev/v4l-subdev.

## 2026-11-03 17:00 - Android captured: Elixir installed, camera works, CCI tracing live

After the failed in-place attempts, the ROM was installed properly and this is now a working oracle:

- Elixir 5.7 (Android 15) installed via TWRP (**recovery partition**, not boot - that was the bootloop cause;
  `fastboot flash recovery`, then the PON `recovery` magic from pmOS: syscall 142 with "recovery").
  Data formatted, ROM sideloaded (`adb sideload`), booted.
- Camera works: `dumpsys media.camera` shows 5 devices, CamX logs ZSLPreviewRaw frames, and it needs
  `input keyevent 224` + `wm dismiss-keyguard` + camera permission before it will open (otherwise
  "disabled by policy" = app not foreground).
- **Kernel camera debug**: `echo 0xFFFFFFFF > /sys/module/cam_debug_util/parameters/debug_mdl` makes the vendor
  camera stack log CAM-CCI / CAM-SENSOR / CAM-EEPROM lines to dmesg (thousands of them).
- **kprobes work** on the vendor kernel (arm64 4.14): `kprobe_events` accepts register fetchargs (`%x0..`), and
  memory fetchargs (`+8(%x1):u32`). Absolute/symbol fetches (`@sym`) return 0 on this kernel.
- Captured `cam_cci_i2c_write` / `cam_cci_i2c_write_table` traffic and decoded the reg-setting struct from the
  driver's own code (disassembly of `cam_cci_i2c_write_table_cmd`):
  `+0x00` = pointer to the u16 register-address array, `+0x08` = u16 size, `+0x0c` = data_type,
  `+0x10` = addr_type, `+0x14` = delay. Call sizes seen: 1, 8, 11, 51 entries.
- Open item: reading the register array itself. The pointer is runtime-mapped (vmalloc/KASLR-affected), and
  `/proc/kcore`, `/dev/mem` and kallsyms addresses are unavailable/obfuscated, so the contents need a helper
  module built against the vendor kernel (or KASLR resolution).

Artifacts: `~/violet-ios/cam/{camera.qcom.so, stockboot/, romkernel/, ctab.txt}`, `~/violet-ios/camregs/`
(register dumper, built for the mainline kernel - not usable on Android).

## 2026-11-03 16:20 - camera: CSIPHY/CSID/VFE register dump while streaming

Built a small out-of-tree module (`~/violet-ios/camregs`, `camregs.ko`) that ioremaps and prints the camera
register blocks during an active stream (`/dev/mem` is blocked, so this is the only read path).

Observed with the sensor streaming (2-lane, SBGGR10 3856x2180):

- CSIPHY1: lane blocks at 0x0000/0x0200/0x0900 are programmed (0xd7, 0x08, 0x11, 0x50, 0xb8...), and a
  PLL-ish block at 0x08b0-0x08fc is live (`0x08b8=0x80`, `0x08dc=0x85`). The 0x0A00 block that the driver's
  table mentions is **all zero** - either it belongs to another PHY variant or the PLL enable lives elsewhere.
- CSID0: `0x0100=0x00100101`, `0x0114=0x10081188`, `0x0118=0x124813c8`, `0x021c=0xffff0000`,
  `0x0220=0x3fff0000` (RDI frame config written).
- VFE0: `0x0000=0x10010000`, `0x0004=0x15800000`, `0x0008=0x000035fe`, `0x000c=0x1ff`, `0x0014=0x0000fdb1`
  (modules configured).

So every block believes it is configured, yet no frame ever completes and the VFE interrupt fires only once at
stream start. Either the sensor is not emitting (its own PLL/stream state cannot be read back - the timing
registers are write-only), or the PHY never locks on the transmitted rate.

Tooling kept for later: `camregs.ko` + source (only prints non-zero registers; add blocks/offsets as needed).

## 2026-11-03 16:00 - camera: writes land, module is strapped to 2 lanes, still no frames

Direct register experiments on the running sensor (driver probes, then streams):

```
CAMTEST 3000 w0 r0=01 | 3028 w0 r0=0000 | 3014 w0 r0=00 | id=0586
```

- **Writes do reach the sensor**: writing `0x3000 = 0x01` reads back `0x01`.
- **`0x3014` and `0x3040` are read-only straps** on this part: they read 0x00 and **0x01** regardless of what we
  write. `0x3040 = 0x01` means the module is **2-lane**, not 4 - so all previous 4-lane attempts were wrong.
- Timing registers (`0x3028` VMAX, `0x302C` HMAX, `0x3050` SHR) read back 0 even after byte-wise writes; they are
  probably write-only on this sensor, so that readback is not evidence either way.
- The DT and driver now both use **2 lanes** (`data-lanes = <1 2>` / csiphy `<0 1>`, `IMX586_NUM_DATA_LANES 2`);
  the driver probes and `STREAMON` is accepted, but still **no frames** and no CSI interrupts.

Also done: an Android capture detour was attempted (TWRP flash) but the device boot-looped; pmOS boot was
restored from `boot-mainline-cam.img` and `userdata` was never touched. The Android partitions turned out to be
**empty** (`vendor` mounts empty, `system` is zeroed), so there was nothing to boot - the whole ROM would have to
be installed to capture CCI traffic that way.

Next: dump the CSIPHY registers from a small kernel module while streaming (PLL lock?), then sweep lane order;
the module being 2-lane narrows the permutations a lot.

## 2026-11-03 15:45 - camera: deeper RE on the vendor blobs (kernel symbols, HAL, sensor libs)

Tooling built this round (kept):
- `vmlinux-to-elf` in `~/violet-ios/reenv` recovers kallsyms from a raw ARM64 Image: produced
  `vmlinux-vendor.elf` (the pmOS r10 downstream kernel) and `vmlinux-stock.elf` (the **stock Xiaomi** kernel from
  `~/violet-backup/boot.img`; that kernel is gzip-compressed - decompressed to `stockboot/kernel.raw`).
- Ghidra 12.1.4 headless project for `camera.qcom.so`, scripts in `tools/ghidra-scripts/`.

What that established:
- The **stock Xiaomi kernel** uses the generic `cam_sensor_*` stack (`cam_sensor_core_power_up`,
  `cam_sensor_power_up`); there are **no per-sensor symbols or tables** in it - the only IMX586 string is a log
  message. Per-sensor register programming is userspace (CAMX).
- The vendor blobs we have are from **LineageOS 22** (`ro.vendor.build.fingerprint = Xiaomi/lineage_violet/...`),
  where the camera works, so the init sequence *is* in `camera.qcom.so`.
- `com.qti.sensor.imx586.so` is a 1.2 KB shim (exports only `GetSensorLibraryAPIs`); the module bin's
  `sensorDriverData` is empty; no flat register table exists in the HAL under any layout tested
  (LE/BE, 3/4/8-byte records, masked, packed, every alignment).
- CSI routing matrix (csiphy0/1/2 x csid0/1/2 -> vfe0_rdi0) tried live: VFE0 IRQ increments by exactly 1 per
  attempt (stream setup), never per frame. The sensor is not emitting.
- `/dev/mem` is blocked (`Bad address`, STRICT_DEVMEM), so the CSIPHY PLL cannot be read directly.

Conclusion: the init sequence is produced by CAMX code (likely computed per mode) and is not extractable as
data in a reasonable time. The decisive route is now **capture the real I2C traffic from a working Android
install** (LineageOS 22 userdebug is on disk; it allows `adb root`), logging CCI transfers to a file during a
camera start, then replay that sequence in our driver.

## 2026-11-03 15:40 - camera: Ghidra pass over camera.qcom.so (ROM route continued)

Ghidra 12.1.4 (`/opt/ghidra_12.1.4_PUBLIC`) headless, ARM64 ELF auto-analysis of `camera.qcom.so` (5.9 MB,
project at `~/violet-ios/ghidra/camproj`). Helper scripts saved in `tools/ghidra-scripts/`:
`ImxHunter.java` (string -> xref -> function), `ImxRegs.java` / `ImxRegs2.java` (instructions referencing
sensor register constants), `DecompFunc.java` (decompile any function by address).

Findings (observations):
- IMX586 code paths in the HAL: `EEPROMData@0x5b5210`, `get_otp_info_from_imx586@0x5c1c60`,
  `FillExposureArray@0x5af3d0`, `CamX::SensorNode::CreateSensorSubmodules@0x5099c0`. All of these are
  EEPROM/OTP, exposure or node plumbing - none is the init-register writer.
- The only function referencing several distinctive IMX registers at once (`Initialize@0x4b7008`) decompiles to
  `CamX::CAECStatsProcessor::Initialize` - a false positive (the constants are sizes/resolutions).
- The 15 KB `com.qti.sensor.imx586.so` is only a `GetSensorLibraryAPIs` shim; it contains no table.
- `com.qti.sensormodule.ofilm_imx586.bin` is a "QTI Chromatix Header" container (properties: sensorDriverData,
  PDConfigData, cameraModuleData, actuatorDriver, EEPROMDriverData...) and its **sensorDriverData is empty**
  (24 zero bytes).
- Table scans over the HAL (LE/BE, 3/4/8-byte records, masked addresses, packed reg<<16|val) found only
  coefficient tables - **no flat register array exists**.

Inference: the init sequence is produced by code at runtime (sensor lib API / `ImageSensorData`), not shipped
as a flat array, which is why byte scanning failed. Extracting it needs decompilation of the sensor settings
path, not a data scan.

## 2026-11-03 15:30 - camera bring-up: final state of this effort

Summary of what stands after the session, all verified on the phone:

| Milestone | State |
|---|---|
| M0 CAMSS + CCI | **Done** - `/dev/media0`, `msm_vfe{0,1}_video*`, camcc feeding them, no boot hang |
| M0.5 sensor responds | **Done** - IMX586 answers at 0x1a on **CCI master 1** (bus 0 is electrically silent), ID `0x0586`; needs reset-assert -> rails -> MCLK -> release -> 20 ms, plus vendor TLMM 94 |
| M1 driver | **Done** - `drivers/media/i2c/imx586.c` probes, detects the ID, registers a V4L2 subdev |
| M2 capture | **Not achieved** - graph links end to end and `STREAMON` is accepted, but csiphy/csid/vfe IRQ counts stay flat: no CSI data. Tried 4-lane/2-lane, csiphy0/csiphy1. The public init table does not suit this **Ofilm IMX586** module |
| M3 userspace | Not reached |

Hardware facts that were hard-won and are worth keeping (all from measurement or the vendor binary):
- The sensor is on **CCI master 1** and CSIPHY is still unconfirmed (vendor indices are off by one for CCI).
- Camera rails: PM6150L gpio 3 (1.2 V), gpio 9 (2.8 V), gpio 4 (2.8 V), plus PM6150L L3 for CSI 1.2 V and L13A for 1.8 V.
- TLMM 94 (`CAM_DVDD1_2V`) must be driven high; TLMM 98 is already high (owned elsewhere).
- Reset TLMM 47 is active-low; MCLK0 (TLMM 28) at 24 MHz.
- The ROM gives wiring and module identity only: the init table lives in `camera.qcom.so` (CAMX), not in a flat
  array, so recovering it needs disassembly or Xiaomi's tree.

To continue: `docs/CAMERA-PLAN-2026-11-03.md`, `patches/proposed/imx586.c`, and the vendor init-sequence
question above. The phone is left running `boot-mainline-cam.img` (4-lane baseline, sensor node on csiphy1) and
is otherwise healthy: WiFi, audio, modem all normal.

## 2026-11-03 15:20 - camera M2: 2-lane test negative; ROM/HAL mining started

**2-lane test**: sensor table switched to `0x3040 = 0x01` and DT `data-lanes = <1 2>` / csiphy `<0 1>`, flashed.
`STREAMON` returns EPIPE (link/format rejected) and no CSI interrupts; not a path forward as-is.

**Where the camera data actually lives (ROM anatomy, measured)**: `~/violet-rom-extract/vendor.img` is an ext4
image and `debugfs` reads it without mounting:
- `/lib64/camera/com.qti.sensor.imx586.so` is a **15 KB stub** - it does not contain the init table.
- `/lib64/camera/` has no large sensor libraries; the real implementation is `/lib64/hw/camera.qcom.so`
  (**5.9 MB**), which does contain the IMX586 code: strings `lxl eeprom lijun++ imx586 vendor_id`,
  `FormatWBData_Ofilm_IMX586`, `get_otp_info_from_imx586` - so the rear module is an **Ofilm IMX586**.
- `/etc/camera/*` is ISP tuning (face models, `.cng`), not sensor init.
- The vendor kernel in `boot-r10.img` has **no** sensor tables (they are userspace HAL data); a scan found only
  the DSI panel init sequence (147 records starting `0x3002`, which is the panel, not the sensor).
- Pattern scans over `camera.qcom.so` for a dense 0x3000-0x5FFF register table did not find a clean cluster:
  CAMX keeps these in compiled structures reached through functions, so recovering them needs disassembly
  (Ghidra) around the imx586 init path, not a byte scan.

So yes - the ROM is a real source, but for *hardware wiring* (already used: CSI PHY, CCI master, rails, GPIOs)
and for *identifying the module* (Ofilm IMX586). The init sequence itself needs either CAMX disassembly or
another IMX586 port's table.

## 2026-11-03 15:15 - camera M2: CSIPHY1 tried, no CSI activity at all; stale-DTB trap found

Two concrete results this round.

**1. A stale-DTB trap that cost a cycle.** Editing `violet-sm6150-camera.dtsi` and running
`make ARCH=arm64 LLVM=1 qcom/violet-sm6150.dtb` did **not** rebuild the DTB: the dependency on the included
`.dtsi` is not tracked, so the flashed image still carried the previous graph and the media topology looked
unchanged. `touch arch/arm64/boot/dts/qcom/violet-sm6150.dts` before the make forces it (verified by checking
the DTB timestamp and decompiling it). Always confirm the DTB mtime changed before flashing.

**2. The vendor index is off by one for CSI too - but CSIPHY1 gives the same silence.** Since the vendor's
`cci-master = <0>` actually meant hardware CCI master 1, the sensor endpoint was moved from `&camss port@0`
(csiphy0) to `port@1` (csiphy1) and the image rebuilt properly. The graph now shows `imx586 -> msm_csiphy1 ->
msm_csid0 -> msm_vfe0_rdi0 -> msm_vfe0_video0`, formats aligned, `STREAMON` accepted - and the capture still
times out with zero bytes.

Interrupt sampling during a stream attempt settles it:

```
t0: csiphy1=0  csid0=2  vfe0=3
t1: csiphy1=0  csid0=2  vfe0=3
```

Nothing increments on either side, so **the sensor is not transmitting** (or the PHY is not receiving at all) -
this is upstream of the VFE. The sensor itself is configured and reports streaming (`0x3000` = 0x00).

Remaining suspects, in order:
- The public Raspberry Pi init table may not suit a Xiaomi IMX586 module (different PLL/datarate/lane mapping).
  A vendor-derived init sequence (Xiaomi's published kernel source) would be the reference.
- The sensor may need its MIPI lane order rearranged (module-specific), or 2 lanes instead of 4.
- CSIPHY programming (its `HW Version` reads 0) - a register dump while streaming is still to be done.

## 2026-11-03 15:10 - camera M2: sensor streams and is configured, no CSI data reaches the VFE

State after this round (all measured on the phone):

- Driver loads (default mode) and the graph is fully linked; `v4l2-ctl --stream-mmap` no longer EPIPEs.
- Sensor side is proven configured: 242 common + 18 mode registers written, `0x3000` reads back 0x00
  (streaming). Register readbacks during streaming are now logged by the driver.
- Phone-side enables all check out: PM6150L rail pads high while probing, TLMM 94 driven high by the driver,
  **TLMM 98 is already high** (owned by another consumer, so not the blocker), MCLK0 muxed as `cam_mclk`.
- **No frames**: `msm_vfe0` IRQ count stays at 8 (init), so nothing arrives from CSID/CSI PHY.
- `CSIPHY 3PH HW Version = 0x00000000` is still odd; the CSIPHY register block may not be programmed the way
  we assume.
- A 2x2-binned (1928x1090) alternative mode table was added for a lower-datarate test, but switching modes at
  probe makes control init fail with -ERANGE (hblank/vblank ranges are derived from the mode), so the test was
  not completed. The code path is behind the `use_binned` module parameter and defaults off.

Working hypothesis, in order: (a) CSI PHY PLL/lane programming vs the sensor's actual datarate/lane map,
(b) lane order (Xiaomi modules frequently reorder pairs), (c) the sensor table's PLL values not matching this
module's clocking.

Next experiments for M2:
1. Dump CSIPHY/CSID registers during streaming (no debugfs for camss - needs a temporary print in
   `camss-csiphy-3ph-1-0.c` or `camss-csid.c`) to see whether the PHY PLL locks.
2. Try lane permutations on the csiphy endpoint (`data-lanes`) - cheap DT change, 2-3 candidates first.
3. If the PHY is fine, try CSIPHY1 (`msm_csiphy1:1 -> msm_csid0:0`) in case the vendor's sd-index is not the
   physical one.

## 2026-11-03 15:00 - camera M2 in progress: full pipeline linked, sensor streams, no frames yet

The media graph is now wired end to end and every entity agrees on the format:

```
imx586 3-001a -> msm_csiphy0 -> msm_csid0 -> msm_vfe0_rdi0 -> msm_vfe0_video0
all pads: SBGGR10_1X10 3856x2180;  video node: pBAA 3856x2180
```

Links enabled with media-ctl; `v4l2-ctl --stream-mmap --stream-count=1` no longer returns EPIPE, but no buffer
ever completes (the command times out). `VFE0` interrupt count stays at 8 (init only), so no CSI data arrives.

Four real bugs were found and fixed in the driver on the way (each measured, not guessed):

1. **Inverted power mode**: imx412's `MODE_STANDBY`/`MODE_STREAMING` are 0x00/0x01, IMX586 is the opposite
   (0x01 standby, 0x00 streaming). The sensor was being put into standby at "stream on".
2. **Wrong mode-select register**: inherited 0x0100 (IFP) instead of IMX586's 0x3000.
3. **Missing common init**: only the 18-register 4K mode table was written; the 242-register common set (PLL,
   lanes, datarate, timing) was never applied. Now written first, and `0x3000` reads back 0x00 afterwards.
4. **Bayer order vs CAMSS formats**: the sensor reported `SRGGB10` while CAMSS's only 10-bit RDI format is
   `pBAA` (BGGR); the mode code is now `MEDIA_BUS_FMT_SBGGR10_1X10` and EPIPE disappeared.

Also changed: link frequency 600 MHz -> 891 MHz (the init table sets DATARATE_SEL for 1782 Mbps/lane, 4 lanes),
in both the DT and the driver constant.

Open questions for the next attempt (all cheap to test, one boot each):
- Is the sensor really producing? Read its status/PLL registers while streaming, or try the 1080p 2x2-binned
  table (much lower datarate) as a sanity check.
- `CSIPHY 3PH HW Version = 0x00000000` is suspicious (other platforms print a non-zero version) - check whether
  the CSIPHY registers are being programmed at all.
- Lane count: vendor DTS does not state it; the table assumes 4 lanes. Try 2 lanes (`data-lanes = <1 2>`) if the
  sensor is wired for two.

## 2026-11-03 14:45 - camera M1 DONE: imx586 driver probes and detects the sensor

New `drivers/media/i2c/imx586.c` (copy in `patches/proposed/imx586.c`), derived from the in-tree imx412 driver
(mainline V4L2 shape: one mode, controls, async registration) rather than from the Raspberry Pi driver found
upstream, so it matches this tree's APIs. DT node now says `compatible = "sony,imx586"`.

Result on the phone:

```
imx586 3-001a: IMX586 detected (id 0586)
```

and the subdev appears as `/dev/v4l-subdev10` alongside the CAMSS subdevs (16 subdev nodes total).

What the driver had to get right, each found by measurement and now encoded:

1. **Power order**: XCLR asserted -> 20 ms -> AVDD -> 1 ms -> DOVDD -> 1 ms -> DVDD -> 1 ms -> MCLK 24 MHz ->
   1 ms -> XCLR released -> 20 ms. imx412's order (rails, release, clock) never ACKs on this board.
2. **A second enable line**: the vendor's `CAM_DVDD1_2V` TLMM line (gpio 94, exposed in the DT as
   `camtest-gpios`) must be driven high. Without it the ID read returns -EIO every time. TLMM 98
   (`CAM_AVDD1_8V`) is claimed by another driver (-EBUSY), so it is not requested.
3. **Register tables**: IMX586 common + 4K-linear init sets extracted from the public
   `youjunl/imx586-v4l2-driver` tables (242 + 18 registers), with the ID read at 0x0016 == 0x0586.

Temporary DT scaffolding that must be cleaned before this is upstreamable: `camtest-gpios`,
`camera_vana1_2_ldo` marked `regulator-always-on`, and the rail/supply split (the gpio4 rail is really the
sensor's third supply).

Next (M2): wire the graph - `camss` port -> `csiphy` -> `imx586` endpoint - then bring up an RDI capture and
grab a frame with `v4l2-ctl`/`libcamera`.

## 2026-11-03 14:35 - camera M0.5 DONE: IMX586 answers on CCI bus 1 (ID 0x0586)

The rear sensor is alive and identifiable. Evidence from the phone, driver at `3-001a`
(i2c bus 1 = `cci_i2c1`), with `violet-sm6150-camera.dtsi` carrying the sensor node:

```
CAMTEST ordered power: avdd=1 dovdd=1 dvdd=1 clk_en=1
CAMTEST 0x1a ACK id=0586 at logical reset 0
CAMTEST 0x1a no-ack at logical reset 1
CAMTEST 0x1a ACK id=0586 at logical reset 0
CAMTEST 0x1a no-ack at logical reset 1
```

`0x0586` is the IMX586 chip ID, read from register 0x0016 with 16-bit register addressing.

What had to be true, each established by measurement:

1. **Wrong bus**: the sensor is on **CCI master 1** (`cci_i2c1` -> i2c-3), not master 0. A full 0x08..0x77
   scan shows master 1 alive (VCM at 0x0c, EEPROM at 0x50/0x51) and master 0 completely silent. The node was
   moved from `&cci_i2c0` to `&cci_i2c1`; both buses are correctly muxed (TLMM 32/33 and 34/35, `cci_i2c`,
   matching the vendor DTB), so this is not a pinmux bug.
2. **A third rail is required**: with only avdd/dovdd/dvdd (vana0 gpio9, l13a, camera_ldo gpio3) the sensor
   stayed silent; it answered once `camera_vana1_2_ldo` (PM6150L gpio 4) was also on. It is temporarily
   marked `regulator-always-on` in the DT - the proper home for it is a supply the driver controls.
3. **Power sequence matters**: the working recipe is reset **asserted** -> rails up (avdd, dovdd, dvdd, with
   ~1 ms spacing) -> MCLK 24 MHz on -> **reset released** -> 20 ms -> read. imx412's own order
   (rails -> reset released -> clk) is not enough: the sensor does not ACK.
4. **Reset polarity is as declared** (`GPIO_ACTIVE_LOW`, TLMM 47): logical 0 = released = ACK,
   logical 1 = asserted = no ACK.

Also measured on the way: the PM6150L rail pads DO switch (`pinconf-groups` shows `pin output (1 level)`
for gpio3/gpio9 while the driver is probing); earlier "out low" readings were just the post-probe teardown.
A vendor TLMM line (94, labelled `CAM_DVDD1_2V` in the stock dtbo) is driven high in the harness; TLMM 98
returned -EBUSY, so whether either is actually required is still open.

Next: M1 - write the IMX586 driver (this power recipe + ID check + one 4-lane mode) instead of bending imx412.

## 2026-11-03 14:20 - camera M0.5: CCI buses characterised, IMX586 still silent

Measured on the phone (build with `violet-sm6150-camera.dtsi`, sensor node at `cci_i2c0` 0x1a,
rails on PM6150L gpio 3/9, MCLK0 24 MHz, reset TLMM 47):

- **CCI master 1 (i2c-3) is alive**: a 0x08..0x77 scan of 16-bit register reads ACKs at **0x0c**
  (id 0xf207 - a VCM/actuator-style device), **0x50** and **0x51** (id 0x0105 / 0x516f - the camera EEPROM).
- **CCI master 0 (i2c-2) is completely silent**: no ACK at any address. The rear-main sensor node sits on it.
- **The IMX586 never ACKs**: 0x1a on both masters, and the scan found nothing else on either bus.
  Tried with the reset line at both logical levels (physical high and low), 15-20 ms settle each: no ACK.
- Regulators report enabled (`camera_ldo` 1.2 V, `camera_vana0_ldo` 2.8 V, `vreg_l13a_1p8`), MCLK0 is at 24 MHz,
  and the driver runs a full power-on before the read - but `/sys/kernel/debug/gpio` shows PM6150L
  **gpio3/gpio9 still "out low"** while the regulators say enabled. So the *rail GPIOs may not actually be
  switching*, which would explain a silent rear module while the EEPROM (VIO-powered) still answers.
- Vendor DT detail that matters: in the stock dtbo the rear **eeprom** node uses `cci-master = <1>`
  while `qcom,cam-sensor@0` uses `<0>` - i.e. the vendor puts the rear module's EEPROM on CCI master 1
  and the sensor on master 0, which is exactly the pattern measured above.
- Debug harness: a patched `imx412.c` (kept at `patches/proposed/imx412-camtest-debug.c`) is used as the
  probe vehicle - it powers the rails, enables MCLK, then reads IDs at several addresses and dumps GPIO state.
  It must not be shipped; the real driver is M1.

Next: (a) prove whether PM6150L gpio3/9 switch (request them from the driver via a DT `*-gpios` property and
read the line back, or measure the pads), (b) settle which CCI master the rear sensor really sits on, and
(c) only then write the imx586 driver.

## 2026-11-03 14:05 - camera M0.5 in progress: sensor node, rails, driver probe; reboot freeze hit again

- Sensor node added to `violet-sm6150-camera.dtsi`: IMX586 on `cci_i2c0` addr 0x1a, reset TLMM 47, MCLK0 24 MHz,
  rails `avdd` = camera_vana0_ldo (PM6150L gpio 9, 2.8 V), `dvdd` = camera_ldo (PM6150L gpio 3, 1.2 V),
  `dovdd` = vreg_l13a_1p8. Initially bound with `compatible = "sony,imx577"` so the in-tree imx412 driver does
  the power-up and ID read without new driver code.
- Built `imx412.ko` standalone (`make M=drivers/media/i2c CONFIG_VIDEO_IMX412=m modules`) because
  `CONFIG_VIDEO_IMX412` is not set in this kernel; loaded with insmod.
- Probe result: rails + MCLK + reset sequence runs (`cam_cc_mclk0_clk` at 24 MHz; no regulator/enable errors),
  then `imx412_read_reg(IMX412_REG_ID)` returns -EIO, so **the sensor does not ACK at 0x1a on CCI bus 0**.
  First attempt with link-frequency 720 MHz was rejected by the driver's hw-config check (it only accepts the
  EVK's 600 MHz); with 600 MHz the probe reaches the ID read.
- Two things to try next: the IMX586 may answer at a different 7-bit address (0x10 is the usual alternative),
  and/or the CCI bus at the dtsi's 1 MHz may be too fast for this part.
- A kernel-side bus scan (arbitrary addresses through `i2c_transfer`) oopsed in the CCI driver (NULL deref at
  0x18), so address probing was moved into the driver via `client->addr` overrides instead; that load then
  faulted in `__arm64_sys_finit_module`, most likely fallout from the first oops (same boot). Rebooted to retry.
- **The reboot froze**: the phone never came back on USB or WiFi (the known intermittent shutdown/reboot freeze,
  STATUS.md "Open (no fix at all)"). Recovery needed a 15 s power-button hold. `need-hands.sh power` used.

## 2026-11-03 13:43 - CAMERA M0: CAMSS + CCI probe on violet (no sensor yet)

- Prior art: SM6150 CAMSS is already merged upstream (series "media: qcom: camss: add sm6150 camss support", Wenmeng Liu, v4 2026-01-12, tested on the Talos EVK; lwn.net/Articles/1053829). `talos.dtsi` already carries `cci@ac4a000`, `isp@acb3000` and `camcc@ad00000` (`qcom,qcs615-camcc`) - they were simply `status = "disabled"` in violet, which is why no camera device existed.
- New `arch/arm64/boot/dts/qcom/violet-sm6150-camera.dtsi` (copy in `dt/`): `&camss { vdd-csiphy-1p2-supply = <&vreg_l3e_1p2>; vdd-csiphy-1p8-supply = <&vreg_l13a_1p8>; status = "okay"; }; &cci { status = "okay"; };` - no sensor nodes yet.
- Rails taken from the vendor DTB (unpacked from `~violet-pmos/images-r9/boot-r10.img` with `unpack_bootimg`): `cam_csiphy0..2` have `csi-vdd-voltage = <0x124f80>` and `mipi-csi-vdd-supply` = `pm6150l_l3` -> `vreg_l3e_1p2` (the same PM6150L L3 the DSI analog block uses). The vendor described no 1.8 V CSI rail; mainline's sm6150 resources also ask for one, so the camera IO rail (vendor `pm6150_l13`) is used for 1.8 V.
- Camera power switches are **PM6150L GPIOs, not TLMM**: `camera_ldo` = pm6150l gpio 3, `camera_vana0_ldo` = gpio 9, `camera_vana1_2_ldo` = gpio 4 (vendor dtbo `gpio-regulator@0..2`; phandle 0x280 resolves to `pm6150l_gpios`). So TLMM's `gpio-reserved-ranges = <0 4>` does not block them.
- Flashed `boot-mainline-cam.img` (existing Image + new DTB, built by `mk-bootimg.sh`). Boot clean, no hang, no new dmesg errors.
- Verified on the phone: `/dev/media0` exists; `video0..4` = `msm_vfe0_video0/1/2`, `msm_vfe1_video0/1`; `camcc-qcs615 ad00000.clock-controller: sync_state() pending due to acb3000.isp` and `ac4a000.cci` (camcc registered, and CAMSS/CCI are its consumers); two new i2c adapters (i2c-2/3) = the CCI buses. No sensor bound (no IMX586 driver exists in 7.2.10 - `imx412.c` only claims `sony,imx577`).
- Next (M0.5): IMX586 on `cci_i2c0`, addr 0x1a; rails dovdd = `vreg_l13a_1p8`, avdd = camera_vana0, dvdd = camera_ldo; reset TLMM 47; MCLK0 24 MHz; then read chip ID at 0x0016 and expect 0x0586 before writing the driver. Plan: `docs/CAMERA-PLAN-2026-11-03.md`.

## 2026-11-02 19:45 - touch panel-follower (0040), audio knobs removed (0016), 0005 dropped (#186/#187)

- **Touch** (hack: 30 s polling): replaced by the DRM panel-follower mechanism (same as i2c-hid/goodix): touchscreen node gets `panel = <&panel0>`, init runs from `panel_prepared()`. #187: `Detected 1080x2340 touchscreen with 10 max touches` at 5.96 s, input device registered. Confirmed with a real finger by the user (2026-11-02).
- **Audio knobs** (`violet_popp`, `violet_wlen`, `violet_copp_topo`, `violet_island`, `violet_slave`, `clk_mode`, `violet_hw_vote`): removed, defaults kept as constants; q6afe-dai.c and sm8250.c pristine. #186 clean boot: card + capture present, `paplay` and mic `parecord` run, no AFE errors. (A 0-byte `snd-soc-sm8250.ko` I copied by mistake briefly made the card disappear; the kernel change was not the cause.)
- **0005** spmi stale-IRQ patch dropped: kexec-only, 0 'spurious spmi irq' lines on normal boots, #186/#187 boot fine without it.
- **aggre1_noc**: searched; upstream QCS615 QoS series (v3, 2026-03) proposes clocks UFS PHY AXI, USB2 SEC AXI, USB3 PRIM AXI, RPMH IPA for aggre1_noc; the sc7280 series makes the clocks optional because some firmware blocks QoS. Not tested here: needs a boot attempt that can hang.
- Rollback image of #186 kept as `boot-mainline-186-rollback.img`.

## 2026-11-02 19:30 - dwc3 post-resume USB death: ROOT CAUSE + fix (patch 0039); udc-repair removed (#185)

- Searched first: no report of this exact failure; only generic 'failed to enable ep0out' causes (PHY SUSPHY bit, EP command timeouts), which did not apply (GUSB2PHYCFG SUSPHY clear).
- Reproduced with the cable attached (repair service stopped, no hexagonrpcd): dwc3 trace events showed, on resume, ep0out `Start New Configuration` Successful, then `Set Endpoint Configuration` **Timed Out** 3.4 ms later. Register dump before/after: all dwc3 core registers sane, GUSB2PHYCFG SUSPHY clear.
- Qualcomm glue QSCRATCH (phys 0x0a6f8800) read via /dev/mem: `GENERAL_CFG` 0x0d before suspend, **0x04 after resume** (PIPE_UTMI_CLK_SEL bit0 and PIPE3_PHYSTATUS_SW bit3 lost). `dwc3_qcom_select_utmi_clk()` only runs at probe; the resume path never restores it, so without the UTMI clock the controller answers one command and times out on the next.
- Fix: `dwc3_qcom_pm_resume()` calls `dwc3_qcom_select_utmi_clk()` before `dwc3_pm_resume()` when `qcom,select-utmi-as-pipe-clk` is set (patch 0039). #185: with `violet-udc-repair` stopped and no rebind: `GENERAL_CFG` 0x0d after resume, UDC `configured`, no `ep0out`, `usb0` UP. End to end through elogind (`loginctl suspend`, real hook): hook pre ran, PM suspend/exit, UDC configured, hexagonrpcd restarted, card present, ADSP running, 0 sensor_process/sns_sig crashes. One sample each (no statistics loop, as asked).
- Removed: `violet-udc-repair` service + script (kept in `patches/proposed/`, files moved off the phone to /root/old), and the dwc3-qcom rebind loop in the sleep hook.
- #185 also showed the qrtr-smd early-packet path (patch 0038) firing on two consecutive boots (`queued 52 B received before probe`) with the modem registering and WiFi up both times: the race is frequent, not 1 in 3.
- Not fixed: the no-cable case (`dwc3_gadget_suspend` -EAGAIN; the hook still unbinds the UDC there) - needs the cable unplugged to reproduce.

## 2026-11-02 19:00 - modem first-start fatal: ROOT CAUSE + fix (patch 0038); 0012/0015 cleanups (#184)

- Prior art searched first: no report matched; related only: glink version-ACK race (interrupt enabled after probe), fastrpc drvdata-before-init NULL deref.
- Instrumented boot (`phone/modem-trace.start`, cmdline already had `trace_event=qcom_glink,qrtr_ns_*`). Bad boot: modem edge handshake fine (VERSION, IPCRTR open/ack/intents), modem TX_DATA 52 B (the QRTR HELLO) at 28.2840, RX_DONE by us, but NO `qrtr_ns_message: hello from 0` and no reply; QRTR shows 11 services (AP only) until the fatal at 40.03 s. Good boot: 53 services 5 s after 'up'.
- Mechanism (read in source): the rpmsg core installs the callback before ->probe(); `qcom_smd_qrtr_callback()` returns -EAGAIN while drvdata is unset; `qcom_glink_rx_data()` RX_DONEs regardless. The modem sends the HELLO once and waits. Fix: `net/qrtr/smd.c` queues early packets and replays them in order under the callback's lock (patch 0038, module only).
- Verified on #184 + new qrtr-smd.ko: on that boot the early path fired (`queued 52 B received before probe` at 27.94 s), the modem registered 55 services by 40 s, wlan0 up 5 s later, 0 fatals. One boot where the race actually occurred; the race is ~1 in 3, so keep an eye on the next boots.
- `0012` cleanup: removed `tx_with_rcid` (0 'no open_ack' on #183), the `violet_intent_req_reuse` knob (now unconditional) and a debug print. `0015` cleanup: removed all `violet_*` module params, the vdev-start retry, the placeholder SSID, vdev-min, skip knobs and the WMI hexdump/channel-power/TLV knobs (wmi.c, wmi-tlv.c now pristine). #184 boots, audio card up, WiFi associates. Old versions kept in `patches/proposed/`.
- Housekeeping: removed a stale second elogind hook (`variant-A.bak`, executable, ran on every sleep) from `/etc/elogind/system-sleep`; deleted my superseded `0035` file (0036 is the live hook).
- Still open: dwc3 resume (`violet-udc-repair`, hack), hexagonrpcd stop around suspend (pmaports does the same), reboot freeze (CPU stall), aggre1_noc clock removal, touch/panel/DSI-PHY magic values, 0005 spmi (kexec-only), 0016 knobs, NewPipe live 403.

## 2026-11-02 11:20 - suspend/resume: hexagonrpcd stop hook + UDC unbind (patch 0035, userspace)

Research first: postmarketOS hit the same bug on the Pixel 3a - a hexagonrpcd sitting in a FastRPC call while the SoC sleeps crashes the ADSP on resume; their fix is an elogind system-sleep hook that stops hexagonrpcd before sleep (pmaports MR 5400; Debian hexagonrpc README). No upstream kernel fix found.

- Hook `/etc/elogind/system-sleep/no-hexagonrpcd-on-suspend.sh` (copy: `patches/0035-userspace-elogind-sleep-hook-hexagonrpcd-udc.sh`, `phone/`): pre = bounded `rc-service stop` + SIGKILL, post = start again.
- Second blocker found: with no USB cable `dwc3_gadget_suspend()` cannot soft-disconnect and returns -EAGAIN (`dwc3_qcom_pm_suspend returns -11`, `failed to enable ep0out`), aborting suspend (2/2 attempts). The hook unbinds the configfs UDC around sleep. This is a workaround for dwc3, not a dwc3 fix; root cause in dwc3 is not investigated.
- Manual s2idle 16 s + RTC wake with the hook: no ADSP crash, no oops, no D-state tasks, WiFi reassociated.
- Suspend unmasked: removed `/etc/elogind/sleep.conf.d/10-violet-no-suspend.conf`; dconf `sleep-inactive-{ac,battery}-type=suspend`, timeout 30 s (set with the phoc session bus; a plain ssh `gsettings set` goes to a different bus and does not persist).
- UI idle test: power key (uinput) blanks the screen (Phosh only blanks); after 30 s idle the phone suspended by itself (`PM: suspend entry`), exit 5.5 s later with success=1, hexagonrpcd running again, sound card present, no D tasks. The wake was NOT a power-button press by the user (cause of that early wake not established), so a real power-button wake is still untested.
- Modem fatal (item 1): one reboot sample without the fatal; the earlier boot showed it exactly 40.03 s after 'modem is now up'. No prior art found online. Not fixed.
- NewPipe: 0.29.1 is the latest release; its notes have no YouTube live/403 fix.

## 2026-11-02 11:00 — session summary: audio boot race fixed (0030 v2), suspend NULL-deref fixed (0034), launcher + IPv6 fixes, test-tooling lessons

**Fixed and verified**
- **Audio boot race** (no sound card on ~1 in 2 boots; silent recording, flat waveform): `q6afe-clocks` now waits until the AFE answers a harmless clock-off request (patch 0030 v2). #182/#183: card + both WCD937x slaves + 0 AFE errors on every boot checked; Sound Recorder record -> live waveform -> save -> play verified through the UI (Recording 4).
- **Suspend/resume oops** (the 10-31 "never comes back"): `q6dsp_clock_dev_probe()` called `dev_set_drvdata()` after registering the clocks; after an ADSP restart the re-parenting prepared the new clock first -> NULL deref (cc->desc @0x348). Patch 0034. Re-test on #183: s2idle 15 s + RTC wake -> DSP crash/restart but **0 oops, card + mic back, no D-state tasks** (before: wedged root fs). Remaining: the ADSP sensor service crashes on resume (`sensor_process ... frpc_dsp`, `sns_sig_remote_`); stopping hexagonrpcd around sleep was tried but `rc-service stop` hangs (needs SIGKILL) - not solved.
- **GPU**: from #181 the phone uses mainline's own A612 power path; the local RGMU port (and patches 0026/0027) is obsolete. NewPipe VOD plays with 0 GPU errors.
- **NewPipe launcher** missing from the Phosh grid: needed `X-Purism-FormFactor=Workstation;Mobile;` in `~/.local/share/applications/newpipe-atl.desktop` (copy in `phone/`). Search "newpipe" now finds it; it starts in 2-5 s.
- **IPv6 off on wlan0** (router advertises a v6 default route with no uplink; YouTube answers AAAA first): `nmcli connection modify <home-ssid> ipv6.method disabled` + `/etc/sysctl.d/60-violet-no-ipv6-wlan.conf`. Did not by itself cure NewPipe "Network error" on one video page (cause not found; WiFi signal was -89 dBm).
- Mic gain persisted (ADC1 20, TX_DEC0 88), measured with a laptop-played sweep (in-band SNR ~20 dB).

**Open**
- Modem: first start after boot fatals once at ~67 s in roughly 1 of 3 boots (documented in `/etc/init.d/violet-modem`); WiFi recovers ~70 s. Root cause unknown (QRTR_SMD/Q6V5_PAS/GLINK_SMEM are modules; making them built-in is an untested idea).
- NewPipe live streams: HTTP 403 after ~1 min (needs WebView/PoToken). NewPipe + audible audio not acoustically verified (a sink-input existed while muted).
- The "recording restarted the phone" report was never reproduced; the likely cause was the boot race (no card).
- Suspend remains masked in the UI.

**Process lessons (cost ~1 h of the user's time today)**
1. Every ssh command over WiFi costs ~2.6 s -> chains looked "hung". Use `ControlMaster` and size waits to the expected duration.
2. The Phosh screenshot D-Bus call stalls intermittently (first call after a touch); retry once (`see.sh`). `grim`/`wtype` on the phone are 0-byte files. wayvnc capture fails ("No supported buffer formats").
3. Do not wait >30 s on anything without checking why; verify through the UI, not by proxy; never `pkill -f` a pattern that matches your own shell.
4. Blind tap sequences land on the wrong screen; look at the screen before each step.

## 2026-11-02 09:20 — #181 (upstream A612 power path) user-flow tests: recorder OK, NewPipe no longer crashes; audio boot race found

Tests driven through the real UI over uinput taps (`phone/tap.py`, `phone/taps.py`, `phone/key.py`; the phone has autologin + caffeine now):
- **Boot animation** back on #181 (user-confirmed). Cause of its absence on #180 unknown.
- **Sound Recorder:** boot 1 of #181 had **no sound card at all** (`--- no soundcards ---`): at 19.95 s the ADSP answered the first AFE
  commands (clock set 0x100f3, core vote 0x100f4) with error 0x16 / no response (`AFE failed to vote (3)`), 10-30 ms after APR added
  the service - the DSP's AFE is not ready when APR/PDR announces it. That is why the user saw a flat waveform and a silent recording
  (file 1107 B, -91 dB). Boot 2: card present, mic + speaker fine: Record -> live waveform -> Stop -> Save -> Play all OK;
  recording is the played sweep (matched-filter 812x, in-band SNR 14.8 dB, corr 0.59). Boot race ~1 in 2 boots: **needs a real fix**
  (wait/retry for AFE readiness, not just q6core ready).
- **The restart during recording:** not reproduced (record 12 s, playback, app launch, full UI flow: no reset). pstore was empty
  on that boot, i.e. a cold PMIC-level reset, not a kernel crash.
- **NewPipe on #181:** video decoded and rendered (live stream), 0 GPU errors (hangcheck/fault/RGMU), app alive >1 min. It then stopped
  with **HTTP 403 from YouTube** ("IP ban or URL deobfuscation") - NewPipe 0.29.1 vs YouTube, not a phone fault. Not yet tested: a
  normal (non-live) video, longer runs. (#180 = my RGMU port + fixes: GPU hangs under NewPipe; so mainline's path is better.)
- **Modem** crashed 3x in the first 3 min after boot (72/113/196 s, "fatal error without message") on both #181 boots; was 0 on #176-#180.
- Phosh does not list "NewPipe (ATL)" although `~/.local/share/applications/newpipe-atl.desktop` exists; `wtype`/`grim` on the phone are
  0-byte files (type via the OSK instead).
- Mic gain persisted: ADC1 20, TX_DEC0 88 (`phone/violet-audio-setup`).

## 2026-10-31 04:10 — P1 suspend: s2idle sleeps and RTC-wakes; resume crashes the ADSP -> APR oops -> I/O wedge

- `CONFIG_PM_DEBUG` on (#179+). `pm_test` freezer/devices/platform all pass (every driver OK; ath10k key removal
  -110 adds 3 s).
- **Real s2idle works** with CPU idle limited to WFI: manual `echo +15 > /sys/class/rtc/rtc0/wakealarm; echo freeze
  > /sys/power/state` slept 17 s and woke on the PMIC RTC (suspend_stats success=1). `rtcwake` itself is unusable
  from ssh (killed with the session before it writes the state) - use the manual sequence.
- **The real failure is on resume, not wake:** right after "PM: suspend exit" the ADSP reports a fatal error
  (`sensor_process ... frpc_dsp`, then `EX:kernel:sns_sig_remote_`) -> remoteproc recovers the ADSP -> PDR reports the
  audio PD up -> `of_register_apr_devices` -> **NULL deref oops (addr 0x348) in an APR service probe** in the
  pdr_notifier kworker. Afterwards root-fs I/O wedges (jbd2/loop0p2 and many tasks in D; the next suspend hangs in
  `pm_sleep_fs_sync`). That matches the 10-26 "never comes back".
- **Next:** (1) find the NULL deref in the APR re-probe after ADSP restart (q6afe/q6asm/q6adm or the macros/q6afecc
  re-registration; sm7150-mainline has "survive ADSP restart" patches for wcd937x/macros/soundwire); (2) why the
  sensor PD (hexagonrpcd sensors) crashes the ADSP on resume - try stopping `hexagonrpcd-adsp-sensorspd` before
  suspend; (3) then re-enable deep idle states one by one. Phone force-rebooted (SysRq-b) after the wedge.
- Suspend stays masked (gsd-power, autosleep off, HandlePowerKey=ignore).

## 2026-10-31 03:35 — MICROPHONE WORKS (M1 closed): AMIC1 -> WCD937x -> TX macro -> MultiMedia2, PulseAudio `violet_mic`

**Last blocker found:** the WCD937x slaves enumerated at boot and dropped off the bus the instant the sound card
finished registering. Isolated by A/B (no capture link: stays attached; MBHC disabled: still drops; regmap trace: no
codec writes at the detach) to `soc-core.c` "deactivate pins to sleep state": ASoC selects every idle component's
*sleep* pinctrl state, and the codec's sleep state drove the LPI reset line low -> codec held in reset. Fixed by
giving the codec node a default-only pinctrl state (reset stays with the driver's reset-gpios), as sm7150-mainline.

**Verified on #178:** both slaves `Attached` after boot and after capture; `phone/mic-test.sh 1 3` (hw:0,1):
AC RMS ~778, DC -219, ~168 zero crossings/s (room ambience) - real signal; ADC2 (headset/AMIC2) mostly silent with
nothing plugged in. PulseAudio: `violet_mic` source (module-alsa-source hw:0,1) loaded + default by
`/usr/local/bin/violet-audio-setup` (`phone/violet-audio-setup`), `parecord` AC RMS 2534. Recordings in
`logs/mic-2026-10-31/recordings/`. Patches 0029-0032; config saved as `configs/config-7.2.10-sm6150-2026-10-31`.

Not done: by-ear check of the recordings; secondary mic (AMIC3) / headset mic routing presets; UCM profile.
Note: the PulseAudio speaker sink is left **muted** (it was muted for the overnight NewPipe test) - unmute with
`pactl set-sink-mute violet_speaker 0`.

## 2026-10-31 03:30 — overnight: G1 fixed (ordering), mic path unblocked to SoundWire attach, modem/PDR race fixed

### G1 (GPU "RGMU GX failed to power up" -> SoC reset under NewPipe video) — FIXED
- Captured live (dmesg stream + console ramoops at loglevel 8): NewPipe video -> GPU runtime-PM cycling several
  times/s -> `RGMU GX failed to power up: status=000000c0 ... pwr_counter=deafbead` -> ~7 s later silent watchdog reset.
- **Root cause (downstream comparison, Xiaomi violet kgsl_rgmu.c / adreno.c):** downstream stop order is GX retention
  off -> release GPUSTART -> `wait_for_lowest_idle` (RGMU collapses GX; needs the GBIF running) -> only then halt CX GBIF.
  We halted the GBIF first (incl. GX-side RBBM_GBIF_HALT), so the RGMU could never collapse GX and the CPU forced the
  GX GDSC off on *every* suspend - downstream's GMU_SUSPEND error path. `patches/0026`.
- **Death after the failure:** `msm_gpu_submit()` ignored `pm_runtime_get_sync()` and ran hw_init with clocks off
  -> bus stall -> watchdog. `patches/0028` fails the job with -EIO instead (no upstream fix exists). `patches/0027`
  adds downstream's RGMU fault recovery (halt PCC, force GX off, CX power cycle, cold boot) and returns -EAGAIN so
  runtime PM does not latch `runtime_error`.
- **Verified:** #171 946 swipe-driven resumes + #172 927 resumes: 0 GX failures, 0 hangs (old rate ~1/90).
  `host/g1-swipe-stress.sh` drives phosh lock-screen animations (no unlock). NewPipe video itself not re-tested
  (needs the user to unlock).

### Microphone (M1) — LPI + SoundWire attach unblocked; capture not yet working
- **LPI hang root cause:** LPI TLMM pads 0-17 (0x62b40000 + 0x12000) belong to the SSC; an AP access stalls the CPU
  (that was the 10-26 wedge and a fresh one tonight: modprobe -> CPU2 stuck -> soft-lockup panic). The AP owns pads
  18-31: node now `pinctrl@62b52000` (14 pins, gpio0..13 = vendor gpio18..31), as sm7150-mainline does.
  New `pinctrl-sm6150-lpass-lpi.c` (table from sm7150-mainline, same LPASS) + `LPI_FLAG_CHECKED_CLOCKS` in the common
  driver: vote clock via clk_bulk, a refused vote fails runtime resume (-EAGAIN) instead of a hanging access
  (pm_clk_resume() ignores clk enable errors). Verified: logged "LPASS vote failed, not touching LPI registers" when
  the DSP refused early, no hang.
- WCD937x reset = vendor LPI gpio24 = gpio6 here (was TLMM 24, a different pad). `gpiod_set_value_cansleep()` fix
  in wcd937x_reset() (LPI gpiochip can sleep).
- With LPI right, **both WCD937x slaves attached** (first time ever; #173 manual load).
- Boot race: va_macro's first AFE clock set / the LPI core vote hit the AFE before the audio PD was up (DSP error
  0x16). Fixed properly with PDR (`qcom,protection-domain` on q6afe/q6asm/q6adm) **plus CONFIG_QCOM_PD_MAPPER=y**:
  with pd-mapper as a module, PDR made the modem crash-loop ("fatal error without message" every 40 s, no WiFi) -
  upstream "remoteproc: qcom_common: load pd_mapper before booting the DSP" (Loic Poulain, 2026-09). Built in: 0
  modem crashes, WiFi up, va_macro probes first try. q6afe-clocks also defers until q6core reports the ADSP ready.
- Controller is SWRM **v1.5.0** (reg 0x0 = 0x01050000) -> compatible `qcom,soundwire-v1.5.1`.
- **Open:** with the capture link in the card the slaves attach at boot (card instantiates), then drop off
  (`MCP_SLV_STATUS` 0x1090 = 0, no pending IRQ); capture fails `-5` "trf on Slave 1 failed". Next: dyndbg on
  soundwire_bus/soundwire_qcom to see the detach, compare wcd937x DAPM/bias power-down with downstream.

### Other
- BOB: vendor init-mode is pass-through; ours forced HPM. Mainline has no PASS for BOB -> AUTO.
- Modem crash-loop under PDR was NOT BOB (A/B'd: crashed with BOB unused).

## 2026-10-31 00:47 — boot splash working (plymouth `pmos-spin`), user-confirmed

- Installed `phone/plymouth.initd` (boot runlevel, `after udev-settle localmount`, `before greetd`) and
  `phone/plymouth-quit.initd` (default runlevel, `before greetd`, `plymouth quit --retain-splash`). The staged draft
  had the quit `after greetd`, which would let phoc race plymouthd for DRM master.
- First attempt drew nothing: plymouth's debug log said `renderers are being explicitly skipped` - plymouthd only
  creates graphical renderers when `splash` is on the kernel cmdline, and `mk-bootimg.sh` had dropped it together
  with `quiet`. `splash` re-added (kernel unaffected; `quiet` stays off). Same kernel `#169`.
- Result: short console lines -> pmOS spinner -> lockscreen, no black gap. Boot 7 on `#169`: dsi_err=0, rcg=0.
- Rollback: `rc-update del plymouth boot; rc-update del plymouth-quit default`.

## 2026-10-31 00:25 — D1 FIXED for real: MDSS core reset + pclk0 parent-enable (patches 0024/0025); retry removed

**Root cause.** Two upstream-known gaps in the QCS615 display clock support, both already fixed on sister SoCs:
1. **No MDSS core reset.** Since v6.17 the MDSS GDSC stays on through boot until `sync_state()`, so ABL's splash
   configuration survives into drm/msm. msm8916/8939, sdm630/660, sm6115/6125 and sm7150 all added
   `resets = <&dispcc …MDSS_CORE_BCR>` for exactly this ("video mode panel initialization appears to be broken"
   without it). `qcom,qcs615-dispcc.h` defines `DISP_CC_MDSS_CORE_BCR` but `dispcc-qcs615.c` had no reset map and
   talos.dtsi no `resets`.
2. **`disp_cc_mdss_pclk0_clk_src` lacked `CLK_OPS_PARENT_ENABLE`** (upstream sm7150 fix, Jens Reidel, applied
   2025-10-27; same on sdm845). Every failing boot logged `disp_cc_mdss_pclk0_clk_src: rcg didn't update its
   configuration` at 5.370 s — the swallowed `-EBUSY` the probe comment predicted — then FIFO error (status=4) and
   `wait for video done timed out`.

**Fix.** `patches/0024` (reset map at 0x2000, same layout as sm6115/6125/7150; parent-enable flag) and `patches/0025`
(DT reset). The stall-retry/reprogramming block in `msm_dsi_host_power_on()` is **deleted** (logs only now) — the
fix is verified without the crutch.

**Verified, build `#169`:** 4/4 boots clean (flash boot + 3 `host/d1-boot-cycle.sh` reboots): `rcg didn't update`=0,
`dsi_err`=0, `video done timed out`=0, stalled=0; lockscreen visible on first power-on (user-confirmed). Before: every
boot failed.

**Leftovers:** the `dsi_link_clk_set_rate_6g` probe print fires on every DCS transfer (~20 lines at boot) — remove it
with the other DSIDBG diagnostics. pclk1 does not exist on qcs615 dispcc, so no second flag is needed.

## 2026-10-31 00:01 — D1 ordering probe: PLL was locked (`pll_unlocked=0`); the ordering hypothesis is not supported

Build `#168` (probe in `msm_dsi_link_clk_set_rate_6g`) flashed via `host/d1-flash-when-ready.sh` once the cable
was moved; full log `logs/displayboot-2026-10-30/d1-flash.log`. **This boot failed with the usual D1 signature**
(`dsi_err_worker: status=4` at 5.57 s and 5.95 s, `wait for video done timed out` at 5.72 s), so the data covers the
failing case.

- Both rate programmings (5.37 s and the 5.64 s retry): `req pclk=183257000 byte=137442750 | ccf_pclk=183257000 |
  clk_status=00000000 pll_unlocked=0`.
- Second, independent check: `dsi_err_worker` status is **4 = `DSI_ERR_STATE_FIFO`**, never `0x20 =
  `DSI_ERR_STATE_PLL_UNLOCKED`. The upstream `dsi_clk_status()` reads the xml `REG_DSI_CLK_STATUS` (0x11c) on that
  same error IRQ and did not see bit 16. Both register views agree: no PLL unlock.
- Caveat: our 0x120 view reads **all zero** this boot, including `after video enable` (classed `unreadable`),
  whereas the earlier stalled link read 0x343 there. At set-rate time the link clocks are off, so zero is plausible;
  after video enable it is not. Trust the 0x120 decode less than the upstream FIFO-only verdict.
- `ccf_pclk` simply echoes the request (expected; CCF ignores the RCG `update_config()` -EBUSY) — no proof either way.

**Conclusion (per the handoff rule):** not an enable-order bug → do not reorder. The next suspect is the dispcc
pixel/byte RCG not taking the new config (the swallowed `-EBUSY`); a FIFO error at video enable fits a link
clock running at the wrong rate. Next probe: read the RCG's own `CMD_RCGR`/`CFG_RCGR` (UPDATE/ROOT_OFF bits, M/N/D)
right after `clk_set_rate`, rather than CCF's view.

**Not captured:** the after-DPMS comparison. `wlopm --off/--on "*"` returned
`Setting power mode for output 'DSI-1' failed` twice, so the "after power cycle" section only repeats the boot lines.
The capture script needs another way to cycle the output (e.g. the power key via `evemu`/`wtype`, or phoc's own
output-power protocol under the right user).

## 2026-10-30 22:17 — D1 fix staged but deliberately not flashed (no USB recovery path)

Built and verified, not flashed:

- `patches/0021-dsi-drop-swreset-on-fifo.patch` — reverse-applies cleanly against the tree (`PATCH_MATCHES_TREE`).
- `Image` rebuilt `BUILD_RC=0`; `strings Image | grep -c "sw reset after FIFO error"` = **0** (the hack is gone) and
  `grep -c "RGMU GX failed to power up"` = **1** (the G1 fix is still in). `boot-mainline.img` rebuilt, md5 differs
  from the currently-flashed image, which is kept as `boot-mainline-flashed-0804.img`.

**Why not flashed tonight:** the USB port on the laptop fails enumeration (`Device not responding to setup address`,
`error -71`), so `fastboot` has no device to talk to. With no fastboot there is **no recovery path** if a new
`boot` image does not boot — the documented fallback `fastboot flash boot ~/violet-pmos/images-r9/boot-r10.img`
(verified present, 66,621,440 B) needs that same USB link. Flashing is therefore blocked until the cable/port
enumerates and someone can reseat it.

Two incidental findings from the same window, both recorded so they are not re-derived:

- **`wlopm` lies about failure.** `wlopm --on DSI-1` prints `ERROR: Setting power mode for output 'DSI-1' failed`
  while `phoc`'s own log (`/tmp/user-session.log`) shows `connector DSI-1: Turning off` followed by
  `connector DSI-1: Modesetting with 1080x2340 @ 60.000 Hz` — i.e. the output *did* come back. Judge display state
  from phoc's connector lines, not from `wlopm`'s exit status, and not from `ScreenSaver.SetActive` (which is a
  no-op when phosh already thinks the screen is awake).
- **The boot probe's screenshots were all failing on permissions** (`phosh` runs as `user`,
  `/var/log/displayboot/shots` was `root:root 0755`): `Failed to create screenshot … Permission denied`, which is
  why `shots/` was empty. The script now does `chmod 1777` on that directory. Screenshot capture for the next boot
  should work for real.

## 2026-10-30 23:50 — D1: what is a fix and what is a mitigation (no retry-loop "fix" will be shipped)

The user asked the right question — **"is this a hack or a proper fix"** — about the idea of replaying the panel power
cycle inside the driver when the first power-on stalls. Recording the answer so the tree does not drift into
workarounds:

**Genuine, keep:**
- Removing the DSIDBG `dsi_sw_reset()` on every FIFO error (`patches/0021`). Our own debug code turned a transient
  overflow into a wrecked video-mode FIFO. That is a defect being deleted, not a behaviour being tuned.
- Detecting the stalled link (`CLK_STATUS` AON-up/DYN-missing, the measured `0x343`) and **failing the power-on
  instead of handing the DPU a dead link**. Fail-clean is correct regardless of where the rate bug lives.

**Mitigation, explicitly not the fix:**
- The disable/reprogram/re-enable retry in `msm_dsi_host_power_on()`, and any "automatically replay the two power
  presses" logic. Both hide the unknown from every future log. The user's two presses are themselves the hardware
  workaround; automating it would make the bug invisible while leaving it in place.

**Root-cause hypothesis, and the single measurement that decides it.** `update_config()` (`clk-rcg2.c:130`) returns
`-EBUSY` when the RCG will not take its config; CCF's `clk_change_rate()` discards it, so `dsi_link_clk_set_rate_6g()`
returns 0 with the rate never applied. The 10-29 note already suspected the reason: the pixel/byte rate is programmed
**before the DSI PHY PLL is locked**. If so the fix is ORDERING (program the RCG only once its parent PLL is locked),
which also explains why the second power-on always works.

`CLK_STATUS` bit 16 is `PLL_UNLOCKED` (latched, `0x00010000`, already defined in the generated header). The probe
added to `dsi_link_clk_set_rate_6g()` logs, at the exact moment of the rate set:

```
msm_dsi_link_clk_set_rate_6g: req pclk=<req> byte=<req> | ccf_pclk=<ccf view> | clk_status=<reg> pll_unlocked=<0|1>
```

- `pll_unlocked=1` → ordering is the root cause → implement ordering, delete the retry.
- `pll_unlocked=0` → the PLL was locked and the RCG still refused → the problem is in the clock controller and needs
  a different investigation entirely (at which point the retry goes too).

Also fixed tonight, both found by the instrumented boots rather than assumed:
- The one-time "link clocks active" log proved its worth immediately by exposing that the check **itself** was wrong:
  `CLK_STATUS` reads `0x00000000` for tens of ms after `link_clk_enable()` (still 0 after a 20 ms poll), so a
  single-shot or short-poll check reports a false stall and fails an otherwise fine boot. It now distinguishes
  UNREADABLE from STALLED and only acts on STALLED — the value the failing boot actually showed (`0x343`).
- `log_buf_len=4M` added to the boot cmdline. The default ring here is ~133 KB and had rotated past the t=5 s DSI
  lines within a minute, which cost this investigation two windows.

**Blocker:** the phone is sitting in **fastboot** and the laptop cannot enumerate it (`usb 3-4: USB disconnect` with
nothing re-enumerating; the same cable has failed enumeration three times tonight with `error -71`). Flashing needs
a physical reseat, so the staged image and `host/d1-flash-when-ready.sh` watchdog are waiting for that.

## 2026-10-30 22:45 — D1 second fix: verify the link clocks actually run (the sw-reset removal alone was NOT enough)

User confirmed the state directly — "u can see screen in last analyzed screenshot, but i can see black screen with
backlight" — on the boot that had **only** the sw-reset removal (`patches/0021`). So that change reduced the error
burst (8 → 2) but did not fix the panel. It was a necessary cleanup, not the fix.

The `DSIREG` dump that `dsidbg_dump()` writes on the first error was captured in the probe's dmesg snapshot
(`logs/displayboot-2026-10-30/dmesg-2219-t30.txt`, 257 DSI + 24 INTF registers) and gives the broken state:

| register | address | stalled value | healthy reference |
|---|---|---|---|
| CLK_STATUS | `0x120` | `0x00000343` | `0x009047c3` |
| LANE_STATUS | `0x0a8` | `0x00001f0f` | `0x1f00` |
| LANE_CTRL | `0x0ac` | `0x11000000` | — |
| CLK_CTRL | `0x11c` | `0x0000023f` | — |
| FIFO_STATUS | `0x0c` | `0x11111010` | `0x1010` |

Decoded with the field table in `postmarketos-device-bringup → references/mainline-dsi-video-mode.md`:
`0x343` has the AON byte/pixel clocks up but **DYN_BYTECLK (0x80) and DYN_PCLK (0x400) missing**, and LANE_STATUS
`0x1f0f` means all four data lanes are parked in STOPSTATE and never leaving — the documented "DPU feeding a link
that is not draining" state. `LANE_CTRL 0x11000000` shows the clock lane forced continuous HS, so the controller is
asking for a clock that is not toggling.

**Register-offset trap, worth recording:** the tree's generated `dsi.xml.h` puts CLK_STATUS at `0x11c` and
FIFO_STATUS at `0x08`, but on this 6G DSI both sit **+4** (`0x120`, `0x0c`) — the reference file says so and the
measured values confirm it (`0x11c` = `0x23f` is CLK_CTRL's core-clock bits, `0x08` reads 0 while `0x0c` holds
`0x11111010`). Anything that reads CLK_STATUS through the generated macro is reading CLK_CTRL.

**Fix (`patches/0022-dsi-verify-link-clocks.patch`, flashed 22:28):** `msm_dsi_host_power_on()` now requires
`DYN_BYTECLK|DYN_PCLK` in CLK_STATUS after `link_clk_enable()`; if they are missing it logs the status and FIFO,
disables/reprograms/re-enables the link clocks once, and if they still are not toggling returns `-EAGAIN` instead
of handing the DPU a dead link. This is the honest complement to mechanism (1): `clk_set_rate()` cannot report the
RCG failure, so the driver has to look at the hardware.

**Result on the first boot with it (22:30):** `dsi_err_worker=0`, `sw reset=0`, `0xdddd1019=0`, no DSIDBG dump,
no "link clocks stalled" message — i.e. the link came up inside spec, cleanly, with the check silently satisfied.
Compare the boot before it (22:19, sw-reset removal only): 2 × `dsi_err_worker`, 1 × `0xdddd1019`.

**Open:** whether the panel is visibly on — `screenshots` only prove the compositor renders, and the user had gone
quiet. `host/d1-boot-cycle.sh` reboots and records the signature per boot so this is counted over several boots
rather than concluded from one.

## 2026-10-30 22:20 — D1 root cause narrowed to our own DSIDBG sw-reset; fix built

The controlled reboot at 22:05 reproduced the black panel and the probe caught the whole window (files saved in
`logs/displayboot-2026-10-30/`, plus `/var/log/displayboot/` on the phone):

```
5.374946  WARNING clk-rcg2.c:136 update_config        <- msm_dsi_host_power_on+0xf0 (link_clk_set_rate)
5.376426  WARNING update_config                        (second)
5.399099  DSIDBG fifo_status=0x99991018
5.399307  dsi_err_worker: status=4   (DSI_ERR_STATE_FIFO)
5.399315  DSIDBG sw reset after FIFO error
5.779778  DSIDBG enable_video
5.800714  DSIDBG intf1 timing engine 1
5.800720  DSIDBG fifo_status=0xdddd1019               <- repeats every ~33 ms, 8x total
5.817846  fb0: sys_fillrect: framebuffer is not in virtual address space
```

`0xdddd1019` is the same value as the 2026-10-29 dead-panel boot, and per the ginkgo prior art it means MDP
overflow + 4-lane HS underflow — the DPU is feeding a link that is not draining. Two mechanisms, both measured:

1. **The failed RCG update cannot be seen by the DSI driver.** `update_config()` (`clk-rcg2.c:130`) polls
   `CMD_UPDATE` for 500 µs, then `WARN()`s and returns `-EBUSY` — but CCF's `clk_change_rate()` calls
   `core->ops->set_rate()` and **discards the return value**, so `clk_set_rate()` returns 0 and
   `msm_dsi_host_power_on()` walks on to `enable_video` with a link clock that never took the new rate. This is
   the same silent-drop pattern as `a6xx_flush()` on the GPU side.
2. **Our own debug hack then finishes the job.** `dsi_err_worker()` ran
   `else if ((status & DSI_ERR_STATE_FIFO)) { pr_info("DSIDBG sw reset after FIFO error"); dsi_sw_reset(); }`,
   and `PROGRESS.md` item (3) of the 2026-10-23 list already says *"a sw reset in video mode wrecks the FIFO"*.
   Eight FIFO errors therefore meant eight software resets against a running video-mode FIFO, after which the
   panel never scanned — exactly the "black screen with backlight, power button does nothing" state, which only
   a fresh power-on cycle (the two power-button presses) recovers.

**Fix applied** (`patches/` to be generated): the DSIDBG sw-reset arm is removed — video-mode FIFO overflow is now
counted and left to the DPU to re-sync, which is the upstream behaviour; only a genuine
`DSI_ERR_STATE_MDP_FIFO_UNDERFLOW` still triggers `dsi_sw_reset()`.

**Side effect found and fixed:** `displayboot.start` originally ran its 3-minute sampling loop in the foreground,
so the `local` service delayed later default-runlevel services and the phone took ~6 minutes to re-associate WiFi
after the reboot. The loop is now backgrounded (`( … ) &`); WiFi came back in ~40 s on the earlier flashes.

**Not yet proven:** whether removing the reset is sufficient, because the failed RATE remains unfixed (mechanism
1). The next boot tells us: if `dsi_err_worker` still bursts `0xdddd1019` **and the panel still comes up black**,
the sw-reset was not the whole story and the link-clock retry becomes the next change. Panel state itself still
needs eyes on the device — the screenshot proxy only proves the compositor is healthy.

## 2026-10-30 22:05 — user reports the D1 black-screen is happening on *every* reboot; boot probe installed

User report (verbatim intent): on reboot they get a **black UI with the backlight on**, the **power button does
not turn the display off**, and after a while the lock screen appears **after two power-button presses**.

That is the 2026-10-29 20:55 failure (see that entry): panel powered but never scanning, compositor healthy,
"power button does nothing" because the presses go to a compositor nobody can see. Evidence from the boot that
was running at 21:24–22:00 (sampled at 22:00, uptime 2211 s):

```
t=5.844888 … 6.182240   dsi_err_worker: status=4     (x8)
t=5.984830             [drm] fb0: msmdrmfb frame buffer device
card0-DSI-1: dpms=On status=connected   backlight actual=141/4095  bl_power=0
phoc started +29s   phosh +33s   greetd +28s
```

- `status=4` is `DSI_ERR_STATE_FIFO` (`dsi_host.c:91`) — **not** an underflow, so `dsi_err_worker()`'s
  `MDP_FIFO_UNDERFLOW` branch is not taken; the `FIFO` branch runs `dsi_sw_reset()`.
- The errors are entirely inside the **kernel's own first modeset** (fbdev, `fb0` at 5.98 s), 23 s *before*
  phoc exists. Whatever state that leaves the link in, the compositor inherits it.
- This boot has **0** `update_config` warnings, unlike the 10-29 failure (8 × `update_config` +
  19 × `dsi_err_worker` + two power-on attempts). So the two boots share the symptom but **not** the
  `clk-rcg2` signature — do not merge them into one root cause without evidence.
- **The 8 error lines were already rotated out of the dmesg ring by 22:07** (re-counting gave 0 of everything).
  That is the documented trap in the skill: a probe that reads dmesg late keeps nothing.

Consequence: installed `/etc/local.d/displayboot.start` (`local` runlevel) — from t=0 it writes panel/compositor
state every 2 s to `/var/log/displayboot/state.log`, snapshots **dmesg at t=10/20/30/45/60/90/120/150/180 s**, and
takes screenshots every 10 s once phoc's session bus exists. A *good* screenshot on a dark panel means the fault
is DSI/link (D1); no session bus or a black screenshot means the compositor never came up (D2). Source kept at
`phone/displayboot.start`.

Next: one deliberate reboot to capture the window, then read the log rather than guessing (reboot is justified
here — this is a reproducible boot-time fault, not "reboot and see if it helps").

## 2026-10-30 21:58 — verification pass over WiFi: UI upright, sensors publishing, the settings panel is the liar

USB is not usable right now — the host keeps failing enumeration on port 3-4 (`new high-speed USB device
number 58/59`, `Device not responding to setup address`, `error -71`), which is a cable/port/device fault, not a
configuration problem. Everything below was verified over WiFi instead.

- **UI orientation: upright.** Screenshot after relaunching `phosh-mobile-settings`: status bar at top, gesture
  bar at bottom, all text readable. Taken twice (21:51 and 21:55/21:57) with the phone in a fixed upright pose.
- **Orientation value: `normal`**, from `AccelerometerOrientation` on the system bus, in the same pose that raw
  accel reads `X=0.40 Y=-9.92 Z=0.00` — i.e. the identity matrix is correct and the retracted udev rule was
  indeed the cause of the earlier upside-down UI.
- **All five sensors publish:** `LightLevel = 0.0` (dark room at night), `ProximityNear = false`,
  `HasAmbientLight = true`, `HasAccelerometer = true`, and `ssccli` returns live accel/light values.
- **The Sensors panel shows `Updating...` for all three rows while all of the above is true.** It is a
  panel-side quirk (it also produced the two earlier false alarms: `Bottom up`, then `No Sensors found`), so it
  is now documented in `references/snapdragon-sensor-core-mainline.md` as decoration only — values come from
  `ssccli` / the SensorProxy D-Bus properties, and a screenshot is only good for judging layout.

Skill knowledge written this session: new `postmarketos-device-bringup` reference
`references/snapdragon-sensor-core-mainline.md` (hardware discovery from vendor JSON, `hexagonrpcd -s` against
`/dev/fastrpc-adsp-secure`, faking Android socinfo, `-R` root layout, value-level verification, the
no-mount-matrix rule with its evidence, and the busybox/`--line-buffered` and detached-process pitfalls).

## 2026-10-30 21:55 — RETRACTION: the accelerometer mount-matrix "fix" was the bug; orientation needs no rule

User reported the **UI upside down** this evening. Measured in one fixed pose (raw accel identical both times,
`X=0.40, Y=-9.93`):

| udev `ACCEL_MOUNT_MATRIX` | `AccelerometerOrientation` | UI |
|---|---|---|
| `-1,0,0;0,-1,0;0,0,1` (the rule I installed at 07:02) | `bottom-up` | upside down |
| none (identity) | `normal` | upright |

So **the SSC already delivers data in the device frame** and the vendor `.orient` does not need re-applying.
Retracting the 07:15 entry above: that "Orientation: Normal" screenshot was taken off a panel that had not
refreshed, so it did not prove anything. The earlier `face-up → face-down` result with a Z-inverting matrix only
established that the udev property *is* honoured on the SSC backend — which was true but beside the point.

Actions: rule removed from the phone and deleted from the repo (`phone/90-violet-accel-mount-matrix.rules` gone,
step 4 of `phone/install-sensors.sh` is now a retraction note), `CHECKLIST.md` §6 rewritten with the corrected
table above. Lesson recorded both places: read `ssccli --sensor accelerometer` **and** `monitor-sensor --accel`
in the same pose before believing any orientation complaint, and never trust the Sensors panel right after an
`iio-sensor-proxy` restart.

## 2026-10-30 08:12 — G1 fix flashed and running; sensors survive a real reboot; boot-time G1 watcher installed

**Flashed at 08:04** (`fastboot flash boot boot-mainline.img`, 44932 KB OKAY, `dtbo` untouched), phone back up in
40 s on `7.2.10-sm6150`. The image carries the G1 fix (`a6xx_rgmu_start()` now retries GPUSTART once and then
**returns `-ETIMEDOUT` instead of letting `hw_init` write into an unpowered GPU**) plus both diagnostic sets.

**Sensor persistence is now proven across a real reboot** — nothing was started by hand:
`rc-service hexagonrpcd-adsp-sensorspd status → started`, `ssccli --sensor light` returns lux,
`ssccli --sensor accelerometer` returns live values, and `iio-sensor-proxy` reports
`HasAccelerometer = true` on the system bus. The mount-matrix udev rule also survived (orientation was already
verified as "Normal" before the reboot).

**The ath10k flood is gone for real:** `ath10k_core.debug_mask` is absent from `/proc/cmdline` and
`dmesg | grep -c "htt rx netbuf"` is 0 — the ring now holds ~1500 useful lines instead of 94 % spam.

**G1's intermittent leg was not re-hit, and that is reported rather than glossed:** an ATL/NewPipe launch after
the reboot and a 40-cycle rapid `power/control` auto↔on storm with a GL submit each (60 logged resumes) both
came back clean — 0 `hangcheck`, 0 GX power-up failures. The earlier capture stands at roughly 1 failure in 90
resumes, so the fix is *in place and unexercised*, not *proven*.

**Because of that, a boot-time watcher is installed** (`/etc/local.d/g1watch.start`, `local` runlevel, verified
firing with a probe line): it appends
`RGMU GX (not up|failed)|cp_init:|hangcheck|adreno_idle|offending task|fenced register|gpu fault` to
`/var/log/g1-events.log` (rotated at 1 MB, `awk`+`fflush()` because busybox `grep` has no `--line-buffered`).
So the next natural occurrence is captured even if nobody is watching dmesg.

**Open, in priority order:** (1) *why* GX fails to power up on that 1-in-90 resume — the retry may paper over a
real RGMU/IFPC race; the second resume in the captured failure came 130 ms after a healthy one with
`suspend_count=3832`, which points at a collapse/power-up race rather than a random fault. (2) Whether the
`-ETIMEDOUT` path behaves well in use (submit fails, next submit retries) instead of killing clients. (3) D1 and
D2 remain untouched this session.

## 2026-10-30 08:00 — G1 ROOT CAUSE FOUND: GX fails to power up, and `hw_init` writes into a dead GPU anyway

Reproduced on demand, after ~90 clean resumes: **the trigger is launching an ATL/Android app (NewPipe)**, not
GPU idling as such. With the `patches/0019` telemetry live, the failure is unambiguous — two consecutive
resumes:

```
6323.208826  RGMU GX after GPUSTART: status=00000100 gx_on=1 poll_ret=0      <- healthy resume
6323.209212  RGMU hw_init: suspend_count=3832 rbbm_status=00c00015 cp_sqe_cntl=00000001

6323.338500  RGMU GX after GPUSTART: status=000000c0 gx_on=0 poll_ret=-110  <- GX DID NOT COME UP
6323.338974  RGMU hw_init: suspend_count=3833 rbbm_status=00000000 cp_sqe_cntl=00000000
6324.338673  adreno_idle: timeout waiting to drain ringbuffer 0 rptr/wptr = 0/C
6324.338701  cp_init: CP_ME_INIT not consumed (rptr=0 wptr=0 rbbm_status=00000000 cp_sqe_cntl=00000000)
6325.133712  hangcheck detected gpu lockup rb 0!  → hangcheck recover!  offending task: phoc
```

Reading of the evidence, all of it measured rather than assumed:

- `poll_ret = -110` is `-ETIMEDOUT`; `status = 0x000000c0` still has `RGMU_GX_GDSC_POWER_OFF` (bit 6) set, so
  **GX never powered up** on that resume. The healthy line before it shows what "up" looks like: `0x100`.
- `hw_init` ran **regardless**: `rbbm_status=00000000`, `cp_sqe_cntl=00000000`. A live GPU never reads zero —
  every healthy resume here reads `00c00015` / `00000001` — so the block was unclocked/unpowered and every
  register write was dropped, including the `CP_RB_WPTR` doorbell (`CP_RB_WPTR` reads 0, not the 0xC written).
- That is why the ring sat at `rptr/wptr = 0/C`: the CP never fetched `CP_ME_INIT` because it never received
  the doorbell. `fenced_write()`'s AHB-fence check cannot catch it — a dead/zeroed GMU reads back "no
  writedropped" and looks like success (see the 07:25 entry).

**So G1 is two defects, in order:**
1. **GX power-up fails intermittently** on the RGMU resume path (the `RGMU_SPTPRAC_PWR_CLK_STATUS` handshake
   times out with GDSC still off).
2. **The failure is not propagated**: `a6xx_pm_resume()`/`hw_init` continue into a powered-down GPU, turning a
   recoverable "resume failed, retry" into a ringbuffer hangcheck + `recover_worker` that kills the offending
   client (phoc, control-center, ATL — matching every field crash).

Evidence kept: `logs/g1-2026-10-30/{dmesg-repro.txt,dmesg-full.txt}`.

Two hypotheses from earlier in this session are now **dead**, recorded so they are not retried: "GPUSTART is
acked before GX is powered" (no — the ack is honest, the poll times out *because* GX never came up) and
"IFPC keepalive missing" (already present in 7.2.10).

Next step is a fix for (2) first — retry the GX power-up and propagate `-ETIMEDOUT` instead of writing to a
dead block — then attack (1), the handshake itself.

## 2026-10-30 07:25 — G1: the doorbell write was silent by construction; instrumentation v2 staged (not flashed)

Prior art first, per the standing rules:

- **IFPC is ruled out.** Our 7.2.10 tree already carries the Qualcomm keepalive work
  (`a6xx_gpu_keepalive_vote()` set around `a6xx_irq()` and preemption, `a6xx_preempt.c:68/119/248`), so
  "GPU power-collapses mid-register-access" is already mitigated here.
- **The Mar-2026 `adreno_idle()` recovery patch is not our bug.** It fills the old TODO by calling
  `recover()` when the drain times out; our hangcheck already recovers (`hangcheck recover!` /
  `offending task: main`). It addresses the missing recovery, not the cause.

What the code *does* explain is why the failure leaves no trace. `fenced_write()` treats a **clear**
`GMU_AHB_FENCE_STATUS` bit as success (`fence_status_check()`: "Success if !writedropped0/1"), and a collapsed
GMU reads back as 0 — so a lost write looks healthy. And `a6xx_flush()` **discards the return value** of
`a6xx_fenced_write(REG_A6XX_CP_RB_WPTR, …)` entirely. That is consistent with the observed state: ring holds
exactly `CP_ME_INIT` + 1 packet (`wptr = C`), CP never fetched (`rptr = 0`), and dmesg contains no
`fenced register write … fail` line.

`patches/0020-ringbuffer-doorbell-diagnostics.patch` (built, `BUILD_RC=0`, string verified in `Image`,
reverse-applies cleanly, **not flashed** yet):

1. `a6xx_flush()` now checks the fenced write and logs `flush: CP_RB_WPTR=%u fenced write failed (%d)`.
2. The `cp_init` failure path additionally logs raw `AHB_FENCE_STATUS`, `GMU_SPTPRAC_PWR_CLK_STATUS` and the
   ring's own wptr, next to the existing `not consumed` line — that is what distinguishes "write lost" from
   "CP wedged".

It stays unflashed until the running long-idle test reports: flashing reboots the phone and would throw away
the observation window.

## 2026-10-30 07:15 — orientation fixed: mount matrix via udev, verified as "Orientation: Normal"

Field report: the Sensors panel read **"Bottom up"** while the phone was held normally, and `left up` where it
should have been `right up` — a clean 180° error in the XY plane. Cause: the SSC firmware reports an **all-zero
mount matrix** (that is `.placement`, 12 zeros by design in the vendor configs), so `iio-sensor-proxy` fell back
to identity, while the actual rotation lives in `.orient` (`x=-x, y=-y, z=+z`).

Fix, one udev rule (`phone/90-violet-accel-mount-matrix.rules`):

```
SUBSYSTEM=="misc", KERNEL=="fastrpc-adsp-secure", ENV{ACCEL_MOUNT_MATRIX}="-1,0,0;0,-1,0;0,0,1"
```

Why this works and how it was proven: iio-sensor-proxy's `setup_mount_matrix()` (`src/accel-mount-matrix.c`)
reads `ACCEL_MOUNT_MATRIX` from udev *for the SSC backend as well* — confirmed empirically by temporarily
setting a Z-inverting matrix, which flipped `monitor-sensor` from `face-up` to `face-down` and back. The
`libssc` warning "Mount matrix provided by firmware is all 0" is firmware-level and orthogonal to the udev
property, which is what misled me at first. End state, read off the panel: **Proximity Far / Light 12.0 lux /
Orientation Normal**.

Dead ends recorded: writing `.placement` = diag(-1,-1,1) into the JSON changes nothing (still zeros; reverted
to the pristine vendor file), and `nmcli` refuses a wildcard `ifname` for the USB link, so `172.16.42.2/16`
still has to be re-added after each re-plug.

Verification technique (user's correction, and it is the right one): the Sensors panel does **not** refresh
when `iio-sensor-proxy` restarts — it sticks on "No Sensors found" — so restart `phosh-mobile-settings` and
screenshot, rather than asking a human to tap through the UI.

## 2026-10-30 06:31 — SENSORS WORK: all five read live values and iio-sensor-proxy exposes them

`hexagonrpcd` was already installed (0.4.0-r3); what was missing was the *content* it serves and the right
device node. Everything below is verified on the phone over USB:

```
ssccli --sensor accelerometer → X=-0.63 Y=0.10 Z=9.90 m/s²    (flat: gravity on Z, correct)
ssccli --sensor light         → 5 / 7 / 0 lux
ssccli --sensor gyroscope     → 0.000 0.000 0.000 m/s         (stationary, correct)
ssccli --sensor proximity     → FAR
ssccli --sensor magnetometer  → 188.3 / 281.1 / 21.0 µT
monitor-sensor --accel        → "Has accelerometer", "Tilt changed: face-up"
monitor-sensor --light        → "Has ambient light sensor", "Light changed: 5.000000 (lux)"
```

`iio-sensor-proxy` is what Phosh reads for auto-rotate and auto-brightness, so the UI side is done as well.

**How it works, and the three things that were actually wrong:**

1. **The device node is `/dev/fastrpc-adsp-secure`** — this port has no plain `/dev/fastrpc-adsp`, which is
   what the packaged init script hardcodes. `hexagonrpcd -f /dev/fastrpc-adsp-secure -d adsp -s -R <root>`
   attaches to the sensors PD (`Starting hexagonrpcd (INIT_ATTACH_SNS) on /dev/fastrpc-adsp-secure`) and the
   DSP immediately starts asking for files.
2. **Every missing file is logged verbatim**, which made this a mechanical exercise: `Could not open
   /sys/devices/soc0/{hw_platform,platform_subtype,platform_subtype_id,platform_version,soc_id,revision}` and
   `/mnt/vendor/persist/sensors/registry/{sns_reg_version,file1,file2}`. Mainline has no Android socinfo, so
   the values are faked from the vendor configs (`hw_platform=MTP`, `soc_id=355`) and served from the `-R`
   root together with the vendor's `sensors/{config,registry,sns_reg.conf}`.
3. **Persistence**: init script patched to honour `hexagonrpcd_dev`,
   `/etc/conf.d/hexagonrpcd-adsp-sensorspd` sets `hexagonrpcd_dev=/dev/fastrpc-adsp-secure` and
   `hexagonrpcd_fw_dir=/usr/local/share/violet-sensors`, service added to the `default` runlevel. Only
   `iio-sensor-proxy` needed a restart afterwards.

Artefacts: `phone/install-sensors.sh` (idempotent end-to-end recipe, also re-fakes socinfo),
`phone/hexagonrpcd-adsp-sensorspd.initd` (patched init script), `fw/sensors/violet-sensors.tar.gz` (staged
configs + registry dirs). No kernel change, no DT change, no flash — the earlier `sdsp` DT idea stays dead.

**Known cosmetic issue:** `Mount matrix provided by firmware is all 0, falling back to identity matrix` — the
vendor configs have `.orient` (x=-x, y=-y, z=+z) but a zero `.placement`, so whether rotation direction is
correct is untested (needs someone holding the phone). Fix via the config's placement or an iio-sensor-proxy
mount matrix.

Camera remains untouched; only the sensor subsystem is done.

## 2026-10-30 06:20 — telemetry kernel flashed and running: S6 verified, a second flood found, and the GX hypothesis is rejected

**Flashed at 06:03** (`fastboot flash boot boot-mainline.img`, serial `cb0bdec5`, "Sending 44928 KB OKAY,
Writing OKAY, 1.27 s"; `dtbo` untouched). Boot came up first try, `./host/flash-g1.sh --verify` passed:
`7.2.10-sm6150`, GPU `control=auto`, battery 73 %.

**S6 is verified in the field.** Right after boot: dmesg **1445 lines with `Handover signaled` = 1** — the
same-size ring that previously held 1131 spam lines (94 %). Boot-time lines now survive; that is what made the
rest of this possible.

**A second flood was hiding behind it** — `ath10k_snoc … htt rx netbuf pop: <16 bytes>` hex dumps, from
`ath10k_core.debug_mask=0x7fffffff` in `mk-bootimg.sh`'s cmdline. It evicted the ring again within **6 minutes**
(first surviving line was at t=382 s). Two fixes: runtime `echo 0 > /sys/module/ath10k_core/parameters/debug_mask`
(the param is 0644, no reboot, done at 06:10) and the flag is now **removed from `mk-bootimg.sh`** with a comment
explaining why. Anyone re-enabling it for WiFi work should set it at runtime and reset it afterwards.

**The GX-power hypothesis is rejected for ordinary resumes.** The new telemetry ran on ~40 resumes (boot + 12
scripted resume/suspend cycles + a manual burst):

```
RGMU GX after GPUSTART: status=00000100 gx_on=1 poll_ret=0      (every single time)
RGMU hw_init: suspend_count=0…39 rbbm_status=00c00015 cp_sqe_cntl=00000001
```

`RGMU_SPTPRAC_PWR_CLK_STATUS` reads `0x00000100` with `RGMU_GX_GDSC_POWER_OFF` (bit 6) already clear, and
`poll_ret=0` means the very first poll succeeded — **GX is up before `hw_init` writes anything, in every observed
resume**. So "GPUSTART acked before GX powered, CP writes dropped" does not explain G1. (`rbbm_status=00c00015`
= `CP_BUSY|CP_AHB_BUSY_CX_MASTER|bit4|GPU_BUSY_IGN_AHB{,_CP}`, i.e. the snapshot is taken before the CP finishes
init, as expected.)

**Short idles do not reproduce it.** 12 scripted `eglprobe` resume→GL→suspend cycles all returned
`[64, 128, 191, 255]` (the correct pixel), 0 `hangcheck`, 0 `adreno_idle` timeouts. Combined with the field
data, the remaining untested variable is the **duration** of the suspended state (the field hangs followed
~100 min of suspend, not 6 s). Long-idle repro is running: `tools/g1-longidle-repro.sh` blanks the panel, holds
the GPU suspended for 40 min (verified `runtime_status=suspended`, `suspended_time` delta reported), then fires
25 surfaceless-GL bursts and dumps the telemetry.

**Method note:** the `cp_init: CP_ME_INIT not consumed (rptr= wptr= rbbm_status= cp_sqe_cntl=)` diagnostic has
not fired yet — it is the line that will identify the failing state if any of these runs reproduces the hang.

## 2026-10-30 04:55 — sensors: no kernel work needed after all — the packaged daemon attaches to `/dev/fastrpc-adsp`

Read the actual Alpine `hexagonrpcd` package (`0.4.0-r3`, aarch64, fetched and unpacked locally) instead of
reasoning about it. Its `/etc/init.d/hexagonrpcd-adsp-sensorspd` runs:

```
command_args="-f /dev/fastrpc-adsp -d adsp -s"
```

`-s` = attach to sensorspd, applied to the **plain ADSP FastRPC device** that this port already has (the audio
`allocpd` path runs through it). **Retracting my earlier framing:** no `sdsp` DT node, no compute-cb SID
hunting, no kernel rebuild — `patches/proposed/0020-sensors-sdsp-fastrpc.md` now carries a SUPERSEDED banner.

The same package pins the file layout: `-R <dir>` serves `<dir>/sensors/config/`, `<dir>/sensors/registry/` and
`<dir>/sensors/sns_reg.conf`, default root `/usr/share/qcom/<soc>/<vendor>/<device>`; `10-fastrpc.rules` sets
`/dev/fastrpc-*` to `fastrpc:fastrpc` 0600 and `.pre-install` creates that user/group.

So the first sensors attempt is **userspace only**. Staged for it: `fw/sensors/violet-sensors.tar.gz`
(2.8 KB) = `sensors/config/talos_{lsm6ds3c,ak991x,stk3x3x,power}_0.json`, `sensors/sns_reg_config` (also as
`sns_reg.conf`), `sensors/registry/` and `mnt/vendor/persist/sensors/registry/registry/` (the output path named
inside `sns_reg_config`), all with the `fastrpc` user as owner once unpacked. Procedure is in `CHECKLIST.md` §6.

Still unverified, and it needs the phone: whether the sensorspd on this ADSP firmware accepts mainline's
FastRPC session at all, and whether `iio-sensor-proxy` in Alpine carries the libssc backend (if not, `ssccli`
still proves the data path, but Phosh rotation would need that backend or a small bridge).

## 2026-10-30 04:05 — sensors: hardware identified from the vendor configs; the missing piece is a known, packaged daemon

Answering "can we read ambient light / gyro / etc. and use them?" — **yes in principle, and the path is now
concrete**, but nothing is implemented yet.

**The hardware, read out of the vendor's own sensor configs** (`vendor.img:/etc/sensors/config/talos_*.json`,
codename "talos" = SM6150; staged in `fw/sensors/`):

| Sensor | Part (SNS module) | SSC bus | addr | DRI irq |
|---|---|---|---|---|
| Accel + gyro | ST **LSM6DS3-C** (`sns_lsm6ds3c`) | SPI inst. 2 | — | 81 |
| Magnetometer | AKM **AK0991x** (`sns_ak0991x`) | I²C inst. 1 | 0x0C | 83 |
| Ambient light + proximity | Sensortek **STK3x3x** (`sns_stk3x3x`) | I²C inst. 1 | 0x47 | 92 |

The STK3x3x config carries both `.als` and `.ps` groups, so auto-brightness and proximity are in scope, not
just rotation. IMU orientation is `x=-x, y=-y, z=+z`; rails `/pmic/client/sensor_vdd`, `sensor_vddio`.

**Why an AP driver cannot be used:** `bus_instance` indexes the **SSC's own** I²C/SPI controllers, and the
vendor DTB has no accel/ALS node on any AP bus — so mainline's `st_lsm6dsx` or `stk3310` cannot be pointed at
these parts. Everything must come through the SSC (QRTR service 400, protobuf in QMI).

**Correction to the 2026-10-28 scoping:** `sns_reg_config` is **not** a registry. It is 553 B of instructions
mapping sysfs attributes (`hw_platform`, `soc_id`, `revision`, …) and naming the *output* path
`/mnt/vendor/persist/sensors/registry/registry`. The ADSP **generates** the registry from the JSON configs plus
`soc_id`. So there is no registry blob to push — the missing capability is runtime *file access* for the sensor
PD, which is what `hexagonrpcd` provides.

**The dependency is packaged already:** Alpine community has `hexagonrpcd` 0.4.0-r3 (aarch64 built) shipping
`hexagonrpcd-adsp-rootpd`, **`hexagonrpcd-adsp-sensorspd`** (sensors PD on ADSP — exactly violet's topology,
since QRTR node 5 is the ADSP and it advertises service 400), `hexagonrpcd-sdsp`, `10-fastrpc.rules` and an
OpenRC service. `libssc 0.4.4` + `ssccli` are already installed on the phone and already reach service 400;
only enumeration fails.

**Remaining unknowns, in order:** (1) the config path the `adsp-sensorspd` init script expects, and whether the
sensors PD is exposed by *mainline* fastrpc at all — `talos.dtsi` declares only `adsp` and `cdsp` fastrpc nodes,
while `fastrpc.c` already understands the `sdsp` domain and the binding allows `label = "sdsp"`. A candidate node
is written up in `patches/proposed/0020-sensors-sdsp-fastrpc.md` and is deliberately **not applied** to the
pending boot image (untested DT that could disturb the working audio `allocpd` path). (2) a writable persist
path for the generated registry, which mainline does not mount.

**Cost split:** step (a) — install `hexagonrpcd`, serve `fw/sensors/`, run `ssccli`/`monitor-sensor` — is
**WiFi-only, no kernel change**. Only if the sdsp PD turns out to be missing does this need the cable.

**Usable today: nothing for motion or light.** The PMIC ADCs are the only IIO consumers, and there is no
software substitute for an IMU or an ALS.

## 2026-10-30 03:40 — G1 telemetry kernel built and staged; flash blocked (phone left USB and WiFi)

**Built and verified, nothing flashed yet.**

- `make ARCH=arm64 LLVM=1 Image dtbs` → `BUILD_RC=0`; `Image` 36313096 B at 03:16. The three G1 telemetry
  strings are present in the built `Image` (checked with `strings`): `RGMU GX after GPUSTART`,
  `cp_init: CP_ME_INIT not consumed`, `RGMU hw_init: suspend_count`.
- `boot-mainline.img` rebuilt at 03:21 from that Image + DTB + the r9 initramfs.
- **S6 gate built as a module**: `CONFIG_QCOM_Q6V5_COMMON=m` / `CONFIG_QCOM_Q6V5_PAS=m`, so the handover-spam
  change is in `qcom_q6v5.ko`, not the Image. Rebuilt, stripped (16 KB), installed to
  `/lib/modules/7.2.10-sm6150/kernel/drivers/remoteproc/qcom_q6v5.ko` on the phone and `depmod`-ed, so it takes
  effect on the next boot without another flash cycle. The change reports the first handover repeat and then
  every 6000th instead of once a second (≈1 line/100 min instead of 94 % of the log ring).
- Instrumentation saved as **`patches/0019-rgmu-g1-telemetry.patch`** (2 files, +60 lines) and verified to
  reverse-apply cleanly against the tree (`patch -R --dry-run -p1` → both files OK), so the patch and the built
  Image agree. Content: (a) `a6xx_rgmu_start()` polls `RGMU_SPTPRAC_PWR_CLK_STATUS` for GX-on after the
  GPUSTART ack and logs `status/gx_on/poll_ret`; (b) `a6xx_hw_init()` logs
  `suspend_count/rbbm_status/cp_sqe_cntl` just before `cp_init`; (c) `a6xx_cp_init()` logs
  `rptr/wptr/rbbm_status/cp_sqe_cntl` when `CP_ME_INIT` is not consumed instead of silently returning `-EINVAL`.
- **`host/flash-g1.sh`** — one command: brings the USB link up, asks for fastboot, flashes **`boot` only**
  (`dtbo` untouched, hard-coded rule in the comments), reboots, waits for the phone, then prints the kernel,
  the dmesg line count, the `Handover signaled` count, the RGMU boot lines and the G1 signature. `--verify`
  checks without flashing, `--wait` waits for the phone first.

**U1 (USB networking) is solved as a side effect** — `enp0s20f0u4` with `172.16.42.2/16` reaches the phone's
`172.16.42.1/16` at **4 ms RTT** with no loss, which is what made the module push and (intended) flash practical.
The interface name can change after the gadget re-enumerates, so `flash-g1.sh` discovers
`enp0s20f0u[0-9]` each time and re-adds the address if missing.

**BLOCKED — no flash happened.** At ~03:30 the host logged `usb 3-4: USB disconnect, device number 26`
(a clean disconnect, not a device error) and the phone then disappeared from USB, from `fastboot devices`
and from WiFi (ARP `INCOMPLETE`, gateway still reachable, so the laptop's network is fine). Whether the cable
was unplugged or the phone powered off cannot be determined remotely. **No partition was written**: if the phone
is running at all, it still runs the old kernel with the GPU pinned and the new module staged for the next boot.

**Resume with one command:** `./host/flash-g1.sh` (phone plugged into the laptop).

## 2026-10-30 23:05 — G1 reproduced with attribution: `CP_ME_INIT` is left unconsumed at a resume

**First clean capture of the G1 hang with the offending task named, and with the ringbuffer content decodable.**
NewPipe (ATL, Vulkan renderer) was launched at 23:00:18 while the phone sat on the lock screen, then unlocked;
the first rendering pass produced two hang/recover rounds inside 3 s:

```
[ 8023.194646] [drm:adreno_idle] *ERROR* 06010200: timeout waiting to drain ringbuffer 0 rptr/wptr = 0/C
[ 8023.695652] [drm:hangcheck_handler] *ERROR* 06010200: hangcheck detected gpu lockup rb 0!
[ 8023.707274] [drm:hangcheck_handler] *ERROR* 06010200:     completed fence: 27630
[ 8023.718079] [drm:hangcheck_handler] *ERROR* 06010200:     submitted fence: 27632
[ 8024.206643] [drm:adreno_idle] *ERROR* 06010200: timeout waiting to drain ringbuffer 0 rptr/wptr = 0/C
[ 8024.216146] [drm:recover_worker] *ERROR* 06010200: hangcheck recover!
[ 8024.225993] [drm:recover_worker] *ERROR* 06010200: offending task: main (android-translation-layer …NewPipe.apk…)
[ 8025.703646] [drm:hangcheck_handler] *ERROR* 06010200: hangcheck detected gpu lockup rb 0!   (fences 27631/27633)
[ 8026.261460] [drm:recover_worker] *ERROR* 06010200: hangcheck recover!
```

**The ring content identifies the stuck command.** `devcoredump` captured the state as `/sys/class/devcoredump/devcd2`
(saved as `logs/g1-2026-10-29/devcd2.txt`); decoding its ascii85 ringbuffer (byte order: u32 big-endian) gives
`70c80008 0000002f 00000003 20000000 00000000 00000000 00000000 00000000 00000000` at dword 0 — i.e. the
**`CP_ME_INIT` packet with payload `0x2f, 3, 0x20000000, 0, 0, 0, 0, 0`**, which is exactly `a6xx_cp_init()`'s
8-dword payload — followed by one more packet (`70620002`, the secure-mode switch). Header + payload + the next
packet = **12 dwords = 0xC**, which is precisely the `wptr` in `rptr/wptr = 0/C`.

So the state at hang is: **`a6xx_hw_init()` was running, it wrote `CP_ME_INIT` into a fresh ring (rptr still 0),
and the CP never fetched it.** A client job (fences 27630→27632) was waiting behind it, hangcheck fired 500 ms
later, and recovery re-ran `hw_init`, whose `CP_ME_INIT` also went unconsumed (second identical timeout).
Therefore the failing step is *"the CP does not start"*, not the job itself and not the ringbuffer bookkeeping.

**What this rules out and what it does not:**
- It is **not** "every resume leaves the CP dead": 8 resume/suspend cycles in the same hour (idle-triggered,
  `tools/g1-cycle-test.sh` predecessors) ran `hw_init` → `cp_init` with **no** drain timeout at all.
- The trigger correlates with the *first real client submission* after a long GPU idle (~100 min suspended at
  the time), which is what the 06:56–07:31 field data said too.
- The devcoredump's `registers:`/`registers-gmu:` sections are **empty** (`gpu-initialized: 0`, `rbbm-status: 0`),
  so it carries no RBBM/CP/GMU register values: post-hoc dumps cannot show the GX power state at fault time.
  Kernel-side telemetry around `a6xx_rgmu_start()` and `a6xx_hw_init()` is required to see whether GX is up
  when `CP_ME_INIT` is written.

**Doc correction:** the 2026-10-18 **MILESTONE** entry's "Remaining" list ("on 2nd+ cycles the first submitted
job locks the GPU up") is **superseded** by the same-day **(night) — repeat-power-cycle bug FIXED** entry
(verified with 5 consecutive EGL clears) and by `RULED-OUT.md` §134 (AHB fence / GPUSTART OOB). It must not be
cited as live evidence; the only live G1 evidence is the 2026-10-29 captures.

**Holding measure applied (userspace, reversible, not a fix):** GPU runtime PM pinned on
(`power/control=on` on `5000000.gpu`, `506d000.gmu`, `card0`) so `hw_init` does not re-run between jobs.
Revert with `power/control=auto`; costs battery because GX stays powered.

**Repro recipe that works without a compositor or an unlocked session:** `python3 tools/eglprobe.py`
(surfaceless EGL + `glClear` + `glReadPixels`) in a loop — it submits real command streams to the GPU while the
phone is locked. `tools/g1-cycle-test.sh` wraps that into resume/suspend cycles.

## 2026-10-30 00:55 — A1 done: the driver now loads itself with the SMB5 init

`/etc/modprobe.d/violet-vbat.conf` -> `options violet_vbat smb5_init=1 debug_state=1`
`/etc/modules-load.d/violet-vbat.conf` -> `violet_vbat`

Verified **without a reboot** by reloading from config alone (`modprobe violet_vbat`, no arguments):

```
smb5_init param = 1   debug_state = Y
SMB5 after: icl_options=0x01 (mode_chg=1) icl=1800 mA status5=0x99
```

So the input-path fix survives a reboot without manual intervention; the only thing not yet observed is a
cold boot (deliberately not taken, reboots are expensive).

**B1 armed:** `/tmp/rest-anchor.sh` runs under `setsid` (5 269) for ~3 h, appending any sample with
|I| < 150 mA to `/tmp/rest-anchors.txt` as `epoch vbat ibat capacity status`. Whenever the phone is
unplugged and idle, real rest anchors accumulate and B1 can be computed from that file.

## 2026-10-30 00:40 — rate study, 17.5 min at 1.58 A: counter and OCV agree to 45 %, per-minute OCV is useless

19 dmesg state lines (1/min) analysed independently of the driver, recomputing both estimators from raw `v`
and `i` rather than trusting the logged `soc_ocv`:

| estimator | dSoC over 1052 s at 1.58 A mean |
|---|---|
| Coulomb integration (i·dt / 3.58 Ah) | **+12.94 points** |
| OCV model (`V - I*122 mOhm` through the vendor table) | **+8.93 points** |
| published `capacity` | 66 % -> 78 % (**+12**) |

- The counter and the published value agree to 0.9 points, so the integration path is doing exactly what it
  claims.
- Counter vs OCV differ by **1.45x** over the window. Crucially the **per-minute ratio scatters from 0.5x to
  5.4x, and two windows came out negative** (OCV falling while charging at 1.6 A). That is the quantitative
  proof that OCV is usable as a LEVEL but not as a RATE under load - which is why the 00:25 patch stopped
  correcting toward it continuously and why the earlier "4x" reading of a single 48-min window was an artefact.
- The residual 1.45x is attributable to (a) polarisation growth during charge that a constant Rbatt cannot
  capture, and (b) the vendor OCV table's plateau slope for a 3.58 Ah FCC assumption. Neither is separable
  without a rest measurement, and neither is a scale error.

**Net position of the gauge:** correct current sign; coulomb counting owns the rate (validated against
physics); OCV owns the level, applied only when resting or when the two disagree by 20+ points; SoC persisted
in SDAM with an `0xA5` marker; monotonic clamp against 1-point jitter. Absolute accuracy ~+/-5-8 %, limited by
the OCV table and the 25 degC assumption, not the code.

## 2026-10-30 00:25 — SMB5 input path was in SDP-current mode; prior art found; one hypothesis retracted

**Research first, then the conclusion — this entry supersedes the 23:15 "4x current scale" claim, which is
RETRACTED.**

Prior art found for the exact PMIC: **asidko/pm6150-charger-mainline** (postmarketOS, PM6150, miatoll/sunfish)
plus its `docs/REGISTER_SEQUENCE.md` and `docs/DESIGN_DECISIONS.md`. It documents that stock mainline leaves
SMB5 on the bootloader's SDP fallback (~500 mA) and names the bit that silently enforces it:

> `USBIN_ICL_OPTIONS_REG` (0x1366): BIT(0) = `USBIN_MODE_CHG` (0 = SDP-current mode, 1 = high-current).
> With BIT(0) cleared the PMIC stays in SDP-current mode and silently ignores the ICL just programmed.
> Registers read back correctly, the state machine reports FAST_CHARGE, but actual VBUS current never
> exceeds ~500 mA.

**Our device matched that exactly** (measured, not inferred):

```
apsd=0x10 (float)  icl_options=0x02 (mode_chg=0 usb51=1)  icl=1500 mA  status5=0x99 valid_vin=1 chg_en=1
```

Correction to my own earlier note: `USBIN_CURRENT_LIMIT_CFG` 0x1e = 30 x 50 mA = **1500 mA**, not "~3 A".

**Fix applied** — `smb5_init` module param (0 = read-only snapshot, 1 = write) implements the documented
9-register sequence in this order: AICL off (0x1380=0) → ICL 1.8 A (0x1370) → FCC 2 A (0x1061) →
`mode_chg=1, usb51=0` (0x1366) → ICL_OVERRIDE (0x1342) → ICL_OVERRIDE_AFTER_APSD (0x1365) → unsuspend
(0x1340) → master enable (0x1042). JEITA, float voltage, safety timer, OTG and watchdog are deliberately not
touched. Verified after load:

```
SMB5 after: icl_options=0x01 (mode_chg=1, usb51=0)  icl=1800 mA  status5=0x99 valid_vin=1 chg_en=1
```

Three minutes of monitoring afterwards: no VBUS collapse, `valid_vin` stays 1, `status=Charging`,
capacity 76 -> 77 %, current 1.28-1.58 A.

**Retracted hypothesis — the QG current is NOT demonstrably 3x overstated.** That claim rested on assuming the
input was capped at 500 mA. It is not: `ap sd=0x10` is **FLOAT** (dedicated-charger class), and with the init
applied the energy balance closes — battery 1.3-1.6 A x 4.23 V = 5.5-6.7 W plus ~2 W system against
1.8 A x 5 V = 9 W of input. A 3x scale error cannot fit that. The current reading is therefore consistent with
physics, and the 23:15 entry's "4x" conclusion was wrong.

**Still open, honestly:** one 48-minute window (21:20-22:08) where OCV rose +6.7 points while the integrated
charge implied ~+25. Candidates, none yet eliminated: the input source class changed mid-window (the cable was
physically moved and replugged around then), or OCV-rate error in the 50-60 % plateau. A 30-minute 5 s-interval
study is now collecting on the phone (`/tmp/rate-study.txt`, started 22:15, setsid so it survives SSH exit —
the first attempt silently died after one sample because plain `nohup` did not survive).

## 2026-10-30 00:05 — K1 verified (glissando won the seat) and the current reading settled to a physical value

**K1 passes, confirmed by the user unlocking with glissando.** In the real user session
(`greetd --session=phosh`, `user` session bus):

- `sm.puri.OSK0` served by `/usr/local/libexec/glissando/bin/glissando --allow-replacement` (pid 12350)
- `phosh-osk-stevia` process count: **0**

That closes the 22:10/22:55 seat-race work: the launcher fix holds at a genuine session bring-up, not just
when stevia is removed by hand.

**The current reading looks physical once the session is up.** With the same module loaded, `current_now`
fell from **1.26 A** (during the greeter session) to **0.55 A** (after the user session started), with
`status=Charging` and `capacity=64 %`. 0.55 A is exactly what a laptop USB 2.0 port can deliver into the pack
after the phone's own load, so the earlier 1.1–1.3 A figures are now looking like a *greeter-session*
artefact rather than a wrong LSB — plausibly the charger re-negotiated its input limit when the session
changed (ICL was read as ~3 A earlier, which a USB 2.0 SDP port never supplies).

**Consequence for the 4× discrepancy (23:15 entry):** the OCV rate said ≈0.30 A, QG said ≈1.26 A. If the
true current during that window was ~0.55 A and fluctuating, the residual disagreement is ~2× rather than 4×,
and the prime suspect becomes the burst-average register not tracking sudden input-limit changes rather than
a scale error. Still not proven — B1 (unplug for 60 s, or a wall charger) remains the test.

**Display note (00:00):** the black screen the user hit was **not** D1 — `dsi_err_worker` count 0, no
`clk-rcg2` warnings, no GPU faults, compositor and connector both healthy. A greeter restart restored it.

## 2026-10-29 23:15 — the QG current scale is inconsistent with the pack's own OCV rate (open)

Chasing the SoC *rate* discrepancy turned into a concrete, bounded open question. All of the following are
measured, not inferred:

**The driver is internally consistent.** Register `PERPH_SUBTYPE` (`QG_BASE+0x05`) reads `0x04` =
`QG_ADC_IBAT_10A`, so the 305.176 µA/LSB scale is the correct branch, and the decode matches the vendor
byte-for-byte (`sign_extend32(raw, 15)`, `qg_iraw_to_ua()` in `qg-util.c`). Both available current
registers agree with each other: `QG_LAST_BURST_AVG_I` (`0xc6`) = **-3142** raw, `QG_S2_NORMAL_AVG_I`
(`0x82`) = **-3610** raw (~1.1 A at 10 A scale, ~0.55 A at 5 A scale). The `BURST_AVG_HOLD_FOR_READ` sequence
the vendor uses is already implemented, so that is not the cause either.

**The pack disagrees with it.** Two independent zero-current extrapolations (`V = a + b·I`, intercept = rest
OCV, done by stepping an 8-thread load on/off at 1 Hz):

| time | R | OCV(I=0) | SoC from OCV |
|---|---|---|---|
| ~21:20 | 121.9 mΩ | 3.8644 V | 51.4 % |
| ~22:08 | 116.7 mΩ | 3.9107 V | 58.1 % |

That is **+6.7 points in 48 min**, i.e. ≈ 0.30 A average into a 3.58 Ah pack. The driver integrates
**≈ 1.1–1.3 A** over the same window, which would be ≈ +29 points (OCV +200 mV). The two estimators
disagree by **~4×**, and the OCV one matches the physics: the phone is on a **laptop USB port** (device
`1d6b:0103`, `bMaxPower` 2 mA, USB 2.0 data link at 425 Mb/s), which cannot deliver 1.1 A *into the pack*
after the phone's own load.

**Not the cause (checked and excluded):** LSB branch (subtype says 10 A, and the code follows it), byte
order, sign (both registers negative while charging), missing hold sequence, and the vendor formula.

**Two candidates left, and the test that separates them is physical:**
1. *Current is inflated* (~4×) — i.e. `QG_LAST_BURST_AVG_I` on this PMIC does not scale as documented for
   this subtype. Test: unplug for 60 s and compare `vbat` against the last charging reading; or put the
   phone on a wall charger and compare the OCV-derived SoC gain per hour against the integrated charge.
2. *The vendor OCV table is ~4× too flat* in the 50–60 % plateau (72 mV per 10 points per the table). Test:
   the same rest measurement anchors one true (OCV, SoC) pair and settles it.

**Interim behaviour, deliberately chosen:** because the current scale is unverified, the gauge does **not**
trust the integrator — the OCV model is primary and the counter only smooths between samples (fast
correction >10 points off, slow otherwise). So a wrong current scale can no longer push the percentage
away from the pack's own voltage. Published SoC tracks **58.8 % (OCV)** vs **63 % (counter)**.

## 2026-10-29 22:55 — OSK launcher hardened: bounded retry instead of one shot

Follow-up to the 22:10 seat race. A single `pkill` before one start only covers the ordering where
stevia is already up when we come up; phosh can (re)start its own OSK at any point during bring-up, so the
launcher now retries:

```
attempt=0; rc=1
while [ "$attempt" -lt 3 ]; do
    attempt=$((attempt+1))
    for rival in phosh-osk-stevia squeekboard; do pkill -f "$rival" && sleep 1; done
    "$PREFIX/bin/glissando" --allow-replacement; rc=$?
    [ "$rc" -eq 0 ] && break                       # ran a whole session, exited normally
    [ $(( $(date +%s) - start )) -gt 10 ] && break  # survived a while then died = real crash, stop retrying
    sleep 2
done
```

The `>10 s` guard is what keeps this from being a restart loop: a seat race kills glissando within
milliseconds, while a genuine crash happens later — only the former is worth retrying. The `fallback`
path below is unchanged, so a keyboard still always exists. Installed and syntax-checked
(`sh -n` OK).

**Live race simulation was attempted three ways and failed for tooling reasons, not product reasons:**
`pgrep -x phosh` returns empty (the greeter session runs **phrog**, not phosh), `/proc/<phoc>/environ` is
not readable as `user`, and the greeter has **no `/run/user/108`** bus socket (uid 108, socket missing) —
so the DBus env of that session cannot be reconstructed from outside. Process-level verification is what
was available, and it answers the question that matters: **glissando (pid 24324, user `greetd`) is the only
OSK running; no `phosh-osk-stevia` process exists**. Full confirmation still needs one real session start
(K1).

## 2026-10-29 22:40 — battery percentage rewritten as a gauge (coulomb counting + verified IR + OCV anchoring)

Goal was a real state-of-charge, not a voltage lookup. What the gauge does now, and the measurement behind each part:

| Piece | Implementation | Evidence |
|---|---|---|
| Current sense | QG `LAST_BURST_AVG_I`, sign **positive = charging** | Charger registers prove charging while the raw value is negative; the old code flipped it and counted down |
| Coulomb counting | `charge += I·dt`, 5 s poll | Capacity rises 60→61 % while charging at 1.3 A |
| Pack resistance | `Rbatt` = **122 mΩ measured** (fallback; SDAM's learned 120 kept when sane) | Load step: 8 busy loops, 540 mA swing, 50 samples at 1 Hz, least squares **dV/dI = 121.9 mΩ** |
| IR compensation | `OCV = V − I·Rbatt` | — |
| Overpotential | **removed**: the measured dV/dI already includes fast polarisation, so adding a separate constant double-counted it and biased SoC ~8 points low (target moved 49 % → 58 % when removed) |
| Absolute reference | OCV table (vendor Alium 3600 mAh, 25 °C) → SoC, re-anchored continuously: fast (1/20/poll) when >10 points off, slow (1/200) otherwise | counter and model now agree within ~3 points (61 % vs 57.6 %) |
| Persistence | SoC + our marker `0xA5` written to SDAM (`0xb646/0xb647`) | capacity stayed 80 → 80 across a double module reload |
| Monotonic clamp | SoC only moves in the direction current implies, released by rest anchor, charger termination, or a ≥2-point model correction | stops the 1-point twitching without locking in a wrong anchor |

**Hardware check first:** the PMIC does **not** maintain SoC itself — `QG_SOC_MONOTONIC_REG` (`0x48bf`) reads `0xff` — so computing it is not a choice.

**Remaining uncertainty:** the vendor OCV table and 25 °C assumption (±5–8 %), and Rbatt is measured at one current. Both are refined by a rest measurement (unplugged, no current for a few minutes), which needs hands on the device.

## 2026-10-29 22:10 — the keyboard on the lock screen was stevia: glissando lost a seat race at session start

Symptom the user reported: the lock screen shows the **stevia** keyboard, not glissando.

**What was actually running:** `/usr/bin/phosh-osk-stevia --allow-replacement` (pid 5529) owning
`sm.puri.OSK0`, and **no glissando process at all**. glissando was not crashing on its own — our own launcher
(`/usr/local/bin/glissando-launch-system`) is written to fall back:

```
for osk in /usr/bin/phosh-osk-stevia /usr/bin/squeekboard; do exec "$osk" --allow-replacement; done
```

so the fallback firing is the *symptom*; the cause is in glissando's stderr:

```
glissando: another input method is already running on this seat
glissando: lost sm.puri.OSK0 (replaced by another keyboard or no session bus)
```

phosh 0.58 (Alpine edge) starts its own OSK from the shell. It owns the input seat before the
`sm.puri.OSK0` service (our glissando launcher) comes up, glissando refuses to start, and the session ends up
on stevia for its whole lifetime.

**Two false leads worth recording:** (1) the `symbols.toml: TOML parse error … missing field 'layers'` I hit
first was self-inflicted — I ran the binary by hand *without* `GLISSANDO_DATA_DIR`, so it read an empty
default path; all three installed `symbols.toml` copies hash-match upstream `d1d407d`
(`1204f1c3d1aa68c5e0ea27fe0c2479c7`). (2) The installed `en.toml` is byte-identical to upstream too. The
layout data was never broken.

**Fix:** the launcher now frees the seat before starting glissando —

```
for rival in phosh-osk-stevia squeekboard; do
    if pkill -f "$rival" 2>/dev/null; then sleep 1; fi
done
```

Installed to `/usr/local/bin/glissando-launch-system`. phosh restarts the `sm.puri.OSK0` service when the
keyboard is needed, so killing the rival does not leave the session without a keyboard.

**Verified:** with stevia stopped, the launcher brings glissando up and it keeps the seat —
`pid 24324 /usr/local/libexec/glissando/bin/glissando --allow-replacement`, stevia gone. Still to confirm at
the next real session start (K1 in CHECKLIST).

**Also observed:** `phoc` is currently owned by **`greetd`**, i.e. the phone is sitting in the *greeter*
session, not the user session — which is why the OSK in front of the user is the system one
(`glissando-launch-system`, the variant meant for the greeter/lock screen) and why `/proc/<phoc>/environ` is
not readable as `user`.

## 2026-10-29 21:20 — charging was never broken: `violet-vbat` had the current sign inverted

After the battery died and the phone came back on cable, the gauge reported `status=Not charging`,
`current_now=-1.27 A` and a capacity that *fell* 59 % → 52 % in twelve minutes — while `vbat` was rising
(3.947 → 3.992 V). That combination is contradictory, so the hardware was read directly instead of trusting
the derived values.

**Charger registers (via a temporary debugfs hook in `violet-vbat`, addresses from downstream `smb5-reg.h`):**

| Register | Value | Meaning |
|---|---|---|
| `0x1006` CHGR_STATUS1 | `0x03` | charger in an active charge state (not inhibit, not disabled) |
| `0x1051` CHGR_CFG2 | `0x2c` | bit0 `CHARGER_INHIBIT` = **0** → charging permitted |
| `0x1340` USBIN_CMD_IL | `0x00` | `USBIN_SUSPEND` = **0** → input not suspended |
| `0x1370` USBIN_CURRENT_LIMIT_CFG | `0x1e` | input limit ~3 A (100 mA LSB) |
| `0x1310` USBIN_RT_STS | `0x10` | bit4 set → VBUS present |

So the SMB5 was charging the pack the whole time in its hardware-default configuration; **nothing needed to
be enabled, and there is nothing to "fix" in the charger**. The bug was in the gauge's sign convention:
`violet_batt_sample()` negates the QG burst-average current, which makes the value **positive while
charging**, but every consumer then treated positive as *discharging* — so the coulomb counter subtracted
charge as the pack filled, the status said `Not charging`, and `current_now` was exported negative.

**Fix (7 places in `patches/violet-vbat.c`, positive = charging now):** coulomb counter `+=`, IR-compensated
OCV `vbat - I·Rbat`, status `CHARGING` when `ibat > +30 mA`, `current_now` = `+ibat` (kernel ABI: positive =
charging), the publish gate and the termination test follow the same convention. Built as a module against
the running kernel (vermagic `7.2.10-sm6150 SMP preempt mod_unload aarch64` matches exactly), installed to
`/lib/modules/7.2.10-sm6150/extra/violet-vbat.ko`, `depmod` + `modprobe` — **no flash needed**.

After reload: `status=Charging`, `current_now=+849304` (≈0.85 A into the pack), and the OCV estimate agrees
with the pack (73–80 % rather than the drifted 52 %).

**Lesson:** the derived `status`/`current_now` were self-consistent and therefore convincingly wrong; the
SMB5 registers were the only independent witness. Do not calibrate a gauge against its own integrator.

**Still missing (unchanged):** mainline has **no SMB5 charger driver** (`drivers/power/supply/` has
`qcom_smbb`, `qcom_smbx`, `qcom_battmgr` — nothing for PM6150's SMB5), so charging relies on the boot-time
hardware defaults: no dynamic ICL/AICL, no PD/QC negotiation, no thermal throttling, no charge termination
handling beyond reading the status bit. That is a driver-porting job (downstream `qpnp-smb5.c` + `smb5-lib.c`),
not a block enabled/disabled — and it can be developed as a module, so it does **not** need a flash per
iteration.

## 2026-10-29 20:55 — battery died, and the reboot came up with a dead panel (boot-time DSI init race)

The phone had been up since the previous morning with no cable, ran flat during use, and rebooted when it was
plugged in. That boot came up with a **black screen while the system was fully alive**: SSH over WiFi worked,
`phoc`/`phosh`/`gnome-session` were running, and a screenshot of the session (`org.gnome.Shell.Screenshot`)
returned a perfectly normal **lock screen with the power menu open** — so composition was fine and the panel
was the problem.

Evidence, all within the first 11 s of uptime:

```
[    5.373476] WARNING: drivers/clk/qcom/clk-rcg2.c:136 at update_config+0xd4/0xe8, CPU#6: kworker/u32:0/12
                update_config+0xd4/0xe8 → clk_rcg2_configure+0xec/0xf4 → clk_set_rate+0x98/0x138
                → _opp_config_clk_single → dev_pm_opp_set_rate → dsi_link_clk_set_rate_6g
                → msm_dsi_host_power_on+0xf0/0xaf8 → dsi_mgr_bridge_pre_enable
[   10.399570] DSIDBG fifo_status=0xdddd1019        (repeats; `dsi_err_worker: status=4`)
[   10.427568] DSIDBG sw reset after FIFO error
```

Counts: **8 × `update_config` warnings, 19 × `dsi_err_worker`, DSI power-on attempted twice**, and every one of
those lines is inside 5.39–10.58 s. After that the link is clean (`dsi_err_worker` count frozen at 19 for the
rest of the boot).

So the first `msm_dsi_host_power_on` failed to take the 6 GHz link rate ("RCG did not update its
configuration"), the DSI FIFO kept erroring, and the panel never started scanning — while DRM kept reporting
`card0-DSI-1: connected` and the compositor kept rendering into a pipe nobody was reading. The second
power-on (a later blank/unblank cycle — `org.gnome.ScreenSaver.SetActive(false)` on the session bus, coinciding
with a power-button press) re-ran the DSI enable and **this time the clock took**; the panel came up and stayed
up, backlight `2048/4095`.

Why the power button "did nothing" at first: the compositor's own power menu was already open on screen
(visible in the screenshot), so presses were being consumed by that menu, and the panel had no valid video
timing to show the UI anyway. It is the re-modeset that fixes it, not the key press.

**Why this matters beyond today:** this is the same failure class as the GPU hang — `clk-rcg2 update_config`
failing to apply a rate at a power-on boundary. `docs/STATUS.md` already noted `gpu_cc_gx_gfx3d_clk_src`
reporting dead on this SoC before patch 0007; a GPU that comes up with a wrong/absent gfx3d clock would stall
its ringbuffer with exactly the `adreno_idle: timeout waiting to drain ringbuffer` signature we see in G1.
Worth checking the RCG/`update_config` path (parent PLL not enabled, RCG reconfigured while running) as a
*shared* root cause for both G1 (GPU lockups) and D1 (this dead panel at boot), rather than two separate bugs.

**Workaround that needs no reboot** if it recurs: unblank the session so the bridge re-enables —

```
P=$(pgrep -x phoc); DB=$(tr '\0' '\n' < /proc/$P/environ | grep ^DBUS_SESSION_BUS_ADDRESS= | cut -d= -f2-)
sudo -u user env XDG_RUNTIME_DIR=/run/user/10000 DBUS_SESSION_BUS_ADDRESS=$DB \
  gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver \
  --method org.gnome.ScreenSaver.SetActive false
```

Also observed: battery reports **"Not charging"** at 57 % while plugged into the build host's USB port on
`androidboot.mode=charger` — the NCM gadget enumerates (serial `xiaomi,violet`) and `usb0` is up at
`172.16.42.1/16`, but the phone is not taking charge current from this port.

## 2026-10-29 08:15 — published as a public repository: github.com/VipinVIP/violet-sm6150-mainline

The documentation + patch series went public so the port can be reproduced by others. Old private repo
`violet-mainline` is superseded (user to delete it).

**What was published (137 files, 9 commits, ordered so it reads as a narrative):** `README.md` (scope,
status table, layout, quick start, credits) · `docs/` (STATUS, CHECKLIST, RULED-OUT, PROGRESS, PLAN and a
new `REPRODUCE.md` build/flash guide) · `patches/` (17 patches; **0014 dropped**, it is superseded by 0015) ·
`dt/violet-sm6150.dts` (byte-identical to the DTS that built the flashed image — authoritative over the
early DTS inside patch 0001) · `configs/config-7.2.10-sm6150-2026-10-27` · `host/` (boot image, fastboot
entry, ssh helpers; `host/legacy/` = the kexec-era workflow) · `phone/` (52 on-device scripts/configs) ·
`tools/` (34 probes).

**Deliberately NOT published:** `kernel/` (7.8 GB tree), `images/`, `device-backup/`, `debug-backup/`,
`vendor-extract/`, `fw/`, `logs/`, `*.img`, `*.wav`, `pstore*.raw`, `*.ko/.o` build products. The firmware
blobs are vendor-signed and not redistributable, and the partition dumps carry device-unique identifiers
(IMEI, MACs, calibration data). `docs/REPRODUCE.md` explains how a reproducer pulls them from their **own**
phone.

**Scrubbing pass applied to every published file:** home AP SSID → `<home-ap-ssid>`, AP BSSID →
`<ap-bssid>`, the phone's LAN address → `<phone-ip>`, fastboot serial → `<serial>`, the phone's WiFi MAC →
`<device-wifi-mac>`, personal e-mail → GitHub noreply, `/home/vipi…` → `~`/`$PROJECT`. Verified by scanning
a **fresh clone** of the public repo (no e-mails, keys, tokens, private IPs, MACs, serials, SSID or local
paths), and every link in the markdown resolves.

**Two code changes made for reproducibility, not cosmetics:** `host/mk-bootimg-clean.sh` now requires
`PMOS_BOOT_UUID`/`PMOS_ROOT_UUID` from the environment instead of carrying this phone's filesystem UUIDs,
and `patches/README.md` no longer points at files that stayed behind.

**Verified after publishing:** 137 files / 9 commits on `main`; all 17 patches still parse
(`git apply --numstat`); markdown links resolve; fresh-clone secret scan clean.

## 2026-10-29 07:35 — the GPU lockup is systemic, not ATL/Vulkan-specific (and needs a kernel fix)

Chasing the NewPipe video crash with GL disabled (user: "don't avoid the vulnerability, fix it") established that
the crash is **not** an app, ATL or renderer bug:

- Driving playback without the UI: ATL's `-u/--uri=video-url` reaches NewPipe (RouterActivity) but only opens a
  dialog, never `MediaCodec`; ATL's DBus intent path needs a name (`org.schabi.newpipe`) that this build does
  not export, so UI-free playback is not available as a probe.
- `vkcube` runs fine (Turnip Adreno 612, Vulkan 1.0.354, Mesa 26.2.5) — the Vulkan driver works.
- **9 `hangcheck detected gpu lockup rb 0` events between uptime 32197 and 33094 (≈06:56–07:31)**, with
  `adreno_idle: timeout waiting to drain ringbuffer 0 rptr/wptr = 0/C` before each. Offending tasks include
  `phoc` (twice as `phoc` + twice as `phoc:gdrv0`), `gnome-control-center` and ATL's `main` — i.e. ordinary
  GTK clients, not just video.
- Power accounting at the time: `runtime_active_time` 1.8 h vs `runtime_suspended_time` 7.5 h; every hang is
  after the GPU had been suspended for hours and then used again.

**Ruled out this round:**
- Missing firmware: `a630_sqe.fw`, `a612_rgmu.bin`, `a612_zap.mbn` all present under `/lib/firmware/qcom/`.
- Port regression in `adreno_recover()`: our tree is byte-identical to current mainline there (mainline no longer
  resets `memptrs->rptr/wptr`; the reset seen in old trees is gone). No local modification to restore.
- Missing GPU bandwidth/OPP data: `talos.dtsi` `gpu@5000000` has `interconnects = <&gem_noc MASTER_GFX3D …
  &mc_virt SLAVE_EBI1 …>` plus a 5-point OPP table with `required-opps` (CX) and `opp-peak-kBps` (3.0–7.05
  GB/s), and the phone exposes 435/500/650/745/845 MHz.

**Prior art:** a postmarketOS patch series "drm: msm: adreno: attempt to recover from ringbuffer drain timeout"
(2026-03) reports the *same* signature on another device (`offending task: sway`) and was rejected — calling
`recover()` from `adreno_idle()` breaks the recover worker's locking/state contract. So this is a known
upstream-wide msm/a6xx failure, not violet-specific, and there is no upstream fix to port yet.

**Diagnostic running:** GPU pinned awake since 07:30:57 (`power/control=on` on `card0`, `5000000.gpu`,
`506d000.gmu`; `suspended_time` frozen at 26,860,905 ms). Before the pin, hangs came ~1 per 100 s; in the
following 7 min there were 0 (count still 9). That points at the power-collapse/resume path but is not yet
proof — it needs a load test plus a forced suspend/resume cycle, and the GPU cannot be made to suspend while
the screen is on.

**What a real fix needs:** kernel iteration on the a6xx power-up/resume sequence (the port's own list of
suspects: per-cycle SMMU/pagetable state, UCHE/hwcg re-programming, `needs_hw_init` paths, secure-mode packet
on re-init) plus a devcoredump capture of the hang state (`CONFIG_DEV_COREDUMP=y`,
`CONFIG_DRM_MSM_GPU_STATE=y`, `/sys/kernel/debug/dri/0/gpu` gives the state view). Every iteration needs a
flash → **USB cable**. The pin is a holding measure, not the fix.

## 2026-10-29 07:15 — ATL (Android Translation Layer) installed; NewPipe UI works, video playback hits a GPU lockup

**Why ATL and not Waydroid:** the user wants a Wine-like translation layer, not a container. ATL is packaged
in Alpine edge/testing (`android-translation-layer 0_git20261019-r0`), which Nura edge already has, so nothing
had to be built.

**Install (WiFi only, no flash):** `apk add android-translation-layer` pulls `art_standalone`,
`bionic_translation`, `libandroidfw`, `vixl`, `wolfssl-jni`, `libopensles-standalone` (21.6 MB of downloads).
The phone's WiFi link is weak (-82 dBm, ~50% loss) and stalls long scp sessions, so the three large packages
were fetched on the laptop, split into 512 KiB chunks, pushed 3-in-parallel with per-chunk size verification,
reassembled on the phone and checked by SHA-256 before `apk add --allow-untrusted`. Helper:
`/tmp/push-file.sh` (laptop) — reusable for any file.

**It works:** `gles3jni.apk` boots — `JVM launched successfully`, dex2oat builds the boot image (16.7 s) and
the app's dex (117 ms), a GTK4 window appears. Binary links `libgtk-4`, `libwebkitgtk-6.0`, `libvulkan`,
`libavcodec.so.62` (MediaCodec via ffmpeg — there is a real media path).

**NewPipe 0.29.1 (real-world, GMS-free app):** launches, UI browsable (user confirmed), and on playing a video:

```
CodecCapabilities.isFeatureSupported(secure-playback)
Decoder h264 doesn't support pixel format VAAPI or DRM_PRIME   <- software decode fallback
MediaCodec.configure(... mime=video/avc ...): codecName=h264 / start()
MediaCodec.configure(... audio/mp4a-latm ...): codecName=aac / start()
PCM name: 'default'  state: PREPARED  channels: 2  rate: 44100
Gdk-WARNING: Vulkan: tu_knl_drm_msm.cc:665: BO map failed: Broken pipe (VK_ERROR_DEVICE_LOST)
Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR) fault addr 0x10
```

Kernel side, same second (uptime 32344 s ≈ 07:13):

```
[drm:adreno_idle] *ERROR* 06010200: timeout waiting to drain ringbuffer 0 rptr/wptr = 0/C
[drm:hangcheck_handler] *ERROR* 06010200: hangcheck detected gpu lockup rb 0!
[drm:recover_worker] *ERROR* 06010200: hangcheck recover!
```

So the crash is **not ATL's Java layer** — the A612 GPU hangs, Turnip reports the device lost, GTK4's GS
Vulkan renderer propagates it and ATL segfaults. This is the same subsystem as the 05:58 phoc crash
(`Failed to start render pass` → SIGSEGV), which makes GPU instability the leading suspect for that one too.

**Mitigation installed:** `/usr/local/bin/atl-run` (`phone/atl-run.sh`) launches an APK with
`GSK_RENDERER=gl` so composition stays off Turnip, plus a desktop entry
`~/.local/share/applications/newpipe-atl.desktop` → "NewPipe (ATL)" in the Phosh app grid (APK copied to
`/home/user/atl/NewPipe.apk` so /tmp cleanup can't remove it). Untested yet: whether GL composition survives
video playback, and whether the GPU hang itself is load-related (memory was fine: 836 MB used, 1.96 GB free).
*(Superseded 30 min later by the 07:35 entry: GL is slower **and** crashes the same way, so `atl-run`
now defaults to `vulkan` again; the hang is the GPU driver, not the renderer.)*

**Laptop cannot substitute for the phone here:** ATL translates APIs, not CPU instructions, so the APK's
native libs must match the host ABI. The laptop is x86_64 and Instagram/NewPipe ship ARM natives, so the
laptop would fail at `System.loadLibrary`, not at the API layer. Laptop remains useful for building ATL
(AUR has `art_standalone-git`, `bionic_translation-git`, `wolfssl-jni`) and for APK inspection/merging.

**Instagram verdict:** not attempted. Blockers, in order: (1) it is distributed as split APKs (base +
arm64_v8a + density) while ATL takes a single APK; (2) it depends on Google Play Services (auth, Firebase,
analytics), which ATL does not provide; (3) its media path would hit the same GPU lockup that killed NewPipe
video. ATL's own README: random apps usually fail on a missing Class/Method and need per-app stubbing.

## 2026-10-29 05:58 — session crash: phoc renderer segfault, then greetd's greeter (not a lock screen)

**What the user saw:** "crashed, then a lock screen appeared with another wallpaper; after logging in the
correct wallpaper came back." It was **not** the lock screen — it was the **greeter**.

Evidence from `/tmp/user-session.log` (the logger installed 10-28):

```
05:58:52.131 (phoc:18895): phoc-render-WARNING **: Failed to start render pass
05:58:52.5   Gdk: Lost connection to Wayland compositor / Broken pipe   (every client)
             gnome-session: App 'mobi.phosh.Shell.desktop' exited with code 1
             gnome-session: on_display_server_failure: Unrecoverable failure in required component mobi.phosh.Shell.desktop
=== Thu Oct 29 05:58:52 IST 2026 phosh-session EXITED rc=139   (signal 11 = SIGSEGV)
=== Thu Oct 29 05:59:21 IST 2026 phosh-session start
```

`/tmp/phrog-session-7.2.10-sm6150.log` is written at 05:59 — greetd fell back to the phrog greeter, which runs
as the **`greetd` user** with its own default background. Hence "another wallpaper": the greeter's, not the
user session's. Logging in restores the user's own wallpaper from their dconf.

**Not a reboot:** `uptime` at 06:23 = `up 8:09` → boot ~22:14, so the kernel stayed up; only the session
(compositor + shell) died. Also **not related to the lock-screen work**: that happened at 23:15-23:21, five
hours earlier.

**Cause:** the compositor segfaulted in its render path — `Failed to start render pass` is phoc's wlr renderer
failing, immediately followed by every client losing the Wayland socket, and gnome-session treating the display
server failure as unrecoverable. Prime suspect is the Adreno A612 GL path already documented in this port
(RCG/power-collapse, RGMU suspend notes).

**No backtrace available:** `core_pattern` was plain `core` (written to cwd, which for phoc is not writable),
and dmesg had already rotated past the event (the ADSP handover spam). Fixed for next time:
`/etc/sysctl.d/90-violet-cores.conf` → `kernel.core_pattern=/var/tmp/cores/core.%e.%p.%s`, dir 1777, and the
session logger already does `ulimit -c unlimited`. Next phoc crash will leave a real core to gdb.

## 2026-10-28 23:35 — A5 closed: speaker audible on native boot (re-confirmed by ear, twice)

Ran `speaker-tone` through the real path on the current **native** boot (not kexec): `clk_mode=0`,
`violet_slave=0`, mixer `PRI_MI2S_RX Audio Mixer MultiMedia3` (numid 91) on, `speaker-test -D hw:0,2`.
The user heard the 440 Hz tone, then asked for a second run to reconfirm and heard that too.

Amp state sampled over I2C (`phone/amp-pwrctl-during-tone.py`, `I2C_SLAVE_FORCE` 0x0706 on `/dev/i2c-1`
because the driver owns 1-004c) during both runs, identical:

```
idle           PWR_CTL=0x0e   shutdown
stream t+0.0s  PWR_CTL=0x0c   powered — holds for the whole tone
after stream   PWR_CTL=0x0e   shutdown
```

So A5's premise was wrong twice over: the RCA regbin is not shipped by any vendor image
(`vendor.img /firmware` → only `tas2563_uCDSP.bin`; `persist/audio` → only `tas2563_cal.bin`, 440 B), and it
is not needed — `patches/0018` + `no_rca_mode=2` (boot-wired in `/etc/modprobe.d/50-violet-audio.conf`)
runs the amp on ROM defaults, which is enough for audible output. Cost of the missing regbin is tuning
(no boost/BOP), not function.

Also corrected the probe: the "active vs shutdown" distinction is 0x0c vs 0x0e (bit 1), **not** the
datasheet MODE field in bits[1:0] as the first version assumed; the script now labels only what was measured.
`i2c-tools` was installed on the phone (2439 MiB / 1309 packages) for register reads.

Remaining audio work is mic only: WCD937x/SoundWire is parked on `MASTER_CLASH_DET`, and the codec reset is
LPI gpio24 (not TLMM 24) — both need DT changes, i.e. USB/flash.

## 2026-10-28 23:20 — upstreamed: PR #1 to x-vlad-x/glissando

Opened <https://github.com/x-vlad-x/glissando/pull/1> ("Register with gnome-session as the OSK
(RegisterClient) — fixes session failure on Phosh"): +81/-1 in `crates/glissando/src/dbus.rs`, branch
`VipinVIP:gnome-session-registerclient` off `d1d407d Release 0.3.0` (upstream `main` unchanged, so it applies
cleanly). It is the repo's **first** PR — the tracker had no issues at all, i.e. this bug was unreported.
Chose a PR over an issue because the fix, the spec reference and the on-device verification are all in hand;
the body notes it can be reshaped (moved into `glissando-session`, gated, or split) since the maintainer may
prefer the systemd-unit path that this distro cannot use.

## 2026-10-28 23:20 — lock screen password re-enabled; suspend/resume confirmed still broken (masked)

**Lock screen:** it had been disabled on 2026-10-27 (`disable-lock-screen=true`, `lock-enabled=false`,
`idle-delay=0`) while chasing the "password at session start" confusion. Re-enabled for the user session:

```
org.gnome.desktop.lockdown disable-lock-screen   false
org.gnome.desktop.screensaver lock-enabled       true
org.gnome.desktop.screensaver lock-delay         0     (uint32)
org.gnome.desktop.session idle-delay             300   (uint32, 5 min → blank + lock)
```

That was **not enough** — the lock screen still let a swipe through. Two more causes, found in order:

1. **`sm.puri.phosh.lockscreen require-unlock` was `false`** — Phosh's own switch for "must authenticate to unlock".
   Set to `true`. This is the one that actually gated the password prompt.
2. **The PAM service did not exist.** `libphosh` calls `pam_start("phosh-lockscreen", …)`; Alpine's phosh package
   ships no `/etc/pam.d/phosh-lockscreen` (or `phosh`), so authentication could not run at all — the same packaging
   bug as Arch FS#80192 ("Lock screen does not accept user PIN/passphrase due to missing PAM configuration").
   Installed both names with a plain `pam_unix` stack (Alpine has no `common-*` includes):

```
# /etc/pam.d/phosh-lockscreen  and  /etc/pam.d/phosh
auth       required     pam_unix.so
account    required     pam_unix.so
password   required     pam_unix.so
session    required     pam_unix.so
```

Verify path used during debugging: `org.gnome.ScreenSaver.Lock` on the session bus → `GetActive=true`,
`LockedHint=yes`; Phosh then refuses screenshots of the locked session (`org.gnome.Shell.Screenshot` returns
false), which is a handy "is it really locked" check.

**Suspend/resume:** still broken, and it never was fixed — it is *masked*. Capability on this kernel:
`/sys/power/state` = `freeze mem`, `/sys/power/mem_sleep` = `[s2idle]` (no `deep`), `/sys/power/autosleep`
= off. The 2026-10-26 entry records what happens when it does suspend: black screen, WiFi gone, power key
does not wake it. Three separate guards keep it from triggering accidentally: gsd-power
`sleep-inactive-{battery,ac}-type='nothing'` (set 10-26), `autosleep` off, and `HandlePowerKey=ignore` in
`/etc/elogind/logind.conf`. A real fix is qcs615 suspend work (PDC/interrupt wakeup sources, RPMh sleep
votes, interconnect/regulator suspend paths) and every test needs a flash, i.e. USB.

## 2026-10-28 23:10 — "Oh no" root cause was the unregistered OSK; fixed in glissando and verified

Correction to the 22:05 entry above: the keyring orphan was real and is fixed, but it was **not** what
triggered the failure page. The session logger installed at 21:55 captured gnome-session's own reason in
the next session:

```
gnome-session-binary[4472]: WARNING: Application 'sm.puri.OSK0.desktop' failed to register before timeout
gnome-session-binary[4472]: CODE_FILE=../gnome-session/gsm-manager.c:CODE_LINE=283:
    on_required_app_failure:Unrecoverable failure in required component sm.puri.OSK0.desktop
```

So `sm.puri.OSK0` being a `RequiredComponent` of `phosh.session` means the OSK must not merely own the
DBus name — it must call `org.gnome.SessionManager.RegisterClient`, which is requirement #3 of Phosh's OSK
spec and which glissando never did (0 hits on upstream `main` as of `d1d407d`). Stevia implements it,
which is why the lock screen/greeter never showed the failure.

Fixed in glissando 0.3.0 (`docs/glissando-registerclient.patch`, commit `121c426`): register with app id
`sm.puri.OSK0` and `DESKTOP_AUTOSTART_ID`, keep the `ClientPrivate` proxy alive, honour `Stop` at logout.
Build note: gio 0.22's `DBusProxy::new_sync` takes `&DBusConnection`, not `Option<&>` — the first build
failed on exactly that (E0308) and rebuilt in 1m11s once fixed.

Verified live, without waiting for a relogin: killed the old keyboard, started 0.3.0 with `--replace`, then
`phone/check-osk-registration.sh` → `RESULT: OSK IS REGISTERED ->
/org/gnome/SessionManager/Client24 (sm.puri.OSK0.desktop)` among 24 clients. Installed to both prefixes
(`~/.local/opt/glissando` for user sessions, `/usr/local/libexec/glissando` for the greeter/lock screen).

Also worth recording: `KillUserProcesses=yes` (the S2 fix) means elogind now reaps an SSH session's whole
cgroup on disconnect, so `nohup`/`setsid` background builds die silently at 2-3 log lines — the build has to
be held by a live connection. That cost two dead attempts before the log made it obvious.

Still to confirm end-to-end: a real logout/login with the patched binary, watching
`/tmp/user-session.log` for the absence of `failed to register before timeout`.

## 2026-10-28 22:05 — session crashes root-caused (keyring orphans), researched, systemic fix applied

Sessions kept dying to the `gnome-session-failed` page. Root cause is **not** the keyboard: the dialog appeared while phoc/phosh/gnome-session/glissando were all alive and glissando still owned `sm.puri.OSK0`. The last line written to the session console (`/dev/vcs7`; gnome-session logs to `/dev/tty7`) was `Failed to activate service 'org.freedesktop.secrets': timed out (service_start_timeout=120000ms)`. A **stale `gnome-keyring-daemon --daemonize --login` from the 07:02 session** held `/run/user/10000/keyring/control`, so the new session's daemon printed `discover_other_daemon: 1` and exited instead of serving the bus → `org.freedesktop.secrets` never appeared → 120 s D-Bus activation timeout → gnome-session phase timeout → "Oh no! Something has gone wrong". Proved both ways: before = `discover_other_daemon: 1`, no name owner; after killing it and `rm -rf /run/user/10000/keyring` = `discover_other_daemon: 0` and a pid owning `org.freedesktop.secrets`.

Why it recurred: `/etc/elogind/logind.conf` shipped with `KillUserProcesses` unset (=`no`), so PAM-daemonized processes (keyring, goa-daemon, feedbackd, evolution-source-registry, even the old session `dbus-daemon`) outlive their session; each failed session seeded more orphans. `loginctl` showed three sessions for uid 10000 and `loginctl list-sessions` never shrank. Sessions *are* cgroup-tracked here (`/proc/<phoc>/cgroup` → `0::/c521`, `Service=greetd`), so the documented kill actually has something to act on.

Applied (documented options, not workarounds): `KillUserProcesses=yes` in `/etc/elogind/logind.conf` (backup `.bak-20261028`) + `kill -HUP elogind`; `phone/kill-stale-session-procs.sh` to reap the current generation; session logging wired into **both** real start paths (`greetd-logged.toml [initial_session]` and `/usr/share/wayland-sessions/phosh.desktop Exec=`, backups kept) since gnome-session's output only ever went to tty7; and the keyboard launchers now guarantee a required component never exits.

Research notes (sources): Phosh's OSK spec <https://phosh.mobi/posts/phosh-osk-interface/> — an OSK *must* ship `sm.puri.OSK0.desktop` (**and** placing it in `/usr/local/share/applications` or `~/.local/share/applications` to override the distro one is the documented testing path, so that part was legitimate), *must* register with gnome-session via `RegisterClient(app_id, startup_id)` — **glissando does not** (0 hits in `crates/glissando/src`) → tracked as S5, not the cause of the failure page (the `gsd-*` daemons pass `RequiredComponents` without registering); `RequiredComponents=…;sm.puri.OSK0;` in `phosh.session` is upstream's design ("Add osk stub to fulfil session dependencies"). pmOS switches keyboards via packages (`apk add !postmarketos-ui-phosh-default-osk squeekboard`), so a proper glissando port would be an APKBUILD shipping the desktop file rather than a hand-copied `/usr` tree. `KillUserProcesses` semantics: `logind.conf(5)`.

Open, tracked in `CHECKLIST.md` §5: S5 glissando `RegisterClient` (needs ~11 min rebuild on the phone), S6 the ADSP handover IRQ spam that reduces dmesg to ~87 real lines.

## 2026-10-28 — glissando (glide-typing OSK) built ON the phone and running as the keyboard

Continued from the Claude session `22337ec5` ("violet mainline: audio, WiFi, native boot"), which had talked the user through building [glissando](https://github.com/x-vlad-x/glissando) on the phone but never ran it. Built and installed it over SSH instead, and switched the live session.

**Build, native on the phone (aarch64), not emulated:**
- Toolchain: `rust 1.99.1`/`cargo` were already present; needed `build-base pkgconf glib-dev cairo-dev pango-dev wayland-dev wayland-protocols git curl fontconfig-dev freetype-dev` (`apk`, 66 packages, 2438 MiB installed).
- `cargo build --release -p glissando -j4` → **11m 02s**, exit 0, binary 7,973,952 bytes, `ldd` clean. Only `-p glissando` is needed: the `gtk4` dependency belongs to `glissando-settings`, which is not the keyboard.
- Source: `2fac253 Release 0.2.0` at `~/glissando` on the phone.

**Dictionaries** (`data/dict/` ships empty, only `SOURCES.md`): `tools/build-dicts.py en` needs the AOSP English word list (0.9 MB) plus the Leipzig `eng_news_2024_300K` corpus — **87,595,861 bytes**. Measured on 2026-10-28 the whole house link was at ~0.3-0.4 Mbit/s (Leipzig 18-29 KB/s, Alpine CDN 38-48 KB/s, GitHub 10 KB/s from *both* the laptop and the phone), so the single-stream download would have taken ~55 min. Leipzig honours `Range`/`206` and throttles per connection: **10 parallel ranges ≈ 110 KB/s, 5× faster, 5.5 min**. `tools/parallel-fetch.py` does that (verifies exact byte count before renaming `.part`). Result `en.gld` = 7,210,424 B = **159,890 words, 402,911 nodes, 69,761 bigrams** (+594 corpus-only words), pushed to the phone with tar-over-ssh (scp does not expand a quoted local glob). Rebuilding the dict recompiles the dict tool itself (`glissando-core`/`glissando-lang`, 7.5 s), so the laptop tree needs a working cargo too.

**Install (user scope, no root)** — `tools/install-glissando-on-phone.sh`, mirroring `packaging/device/deploy.sh`: `~/.local/opt/glissando/{bin,share/glissando/{dict,layouts,emoji}}`, plus the `glissando-launch` wrapper (falls back to Stevia after 3 crashes in 5 min) and a **user override** of `/usr/share/applications/sm.puri.OSK0.desktop` with `Exec=.../glissando-launch`. That desktop file is the only autostart entry for the OSK (`X-GNOME-Autostart-Phase=Panel`, checked: nothing else starts stevia), so the override is the correct persistent switch. Rollback: `rm ~/.local/share/applications/sm.puri.OSK0.desktop`.

**Switch semantics (measured, matters):** killing `phosh-osk-stevi` is not enough — **phosh respawns it from its original command line** (`/usr/bin/phosh-osk-stevia --allow-replacement`), re-taking `sm.puri.OSK0`, and glissando then exits with `lost sm.puri.OSK0`. The desktop override therefore only takes effect at **session start**. For a live switch use the binary's own `--replace` (takes `sm.puri.OSK0` from the running keyboard); note the shipped wrapper passes `--allow-replacement` (a no-op compat flag, `main.rs:160`), which permits being replaced but does not replace.

**Verified working:** `glissando --replace --show` renders a full QWERTY — Esc/Tab/Ctrl/Alt/arrow function row, superscript digits, Shift, `?123`, space bar labelled "English", Enter — at 1080x909 scale 3, frame 2 in **1.7 ms** (frame 1 = 151.7 ms first draw). Captured via `org.gnome.Shell.Screenshot` over DBus and read back; the phosh **app-grid overview hides the OSK layer**, so a screenshot of the launcher legitimately shows no keyboard — open an app first. Live instance now running as the session OSK (`--replace`, no `--show`), owns `sm.puri.OSK0`.

**WHY THE SESSION DIES WITH "Oh no! Something has gone wrong" (root cause, 2026-10-28 21:40):**
`sm.puri.OSK0` is one of the `RequiredComponents` in `/usr/share/gnome-session/sessions/phosh.session` (the list ends `...;mobi.phosh.Shell;sm.puri.OSK0;`). A required component that exits makes gnome-session tear the session down and show that dialog. Two ways it fired here: (a) killing `phosh-osk-stevi` by hand; (b) **the keyboard install itself** — the override makes `glissando-launch` the required component, and glissando *exits cleanly* with `another input method is already running on this seat` / `lost sm.puri.OSK0` whenever a Stevia from an earlier session still holds the seat; upstream's launcher only falls back on a *non-zero* exit, so the required component died and took the session with it.
Fix: `phone/glissando-launch-hardened.sh` (installed over `~/.local/opt/glissando/bin/glissando-launch`, upstream kept as `glissando-launch.upstream`) and `phone/glissando-launch-system.sh` — **every** exit path ends in `exec phosh-osk-stevia --allow-replacement` (or an idle loop if no system keyboard exists), so the required component cannot die while the session lives.

**Lock screen vs login screen (2026-10-28 21:45):** the greeter / lock screen runs as the **`greetd`** user (home `/var/lib/greetd`, nologin) inside a bwrap sandbox that binds **only `/usr` read-only** (+`/etc/ld.so.cache`, tmpfs `/tmp-home`, `/tmp-run`), so a `~/.local` install is invisible there — that is why the lock screen still showed Stevia after the user-scope override. Installed system-wide instead: binary + layouts/emoji + `en.gld` under `/usr/local/libexec/glissando` (verified runnable as `greetd`: `glissando 0.2.0`), launcher `/usr/local/bin/glissando-launch-system` (state falls back to `/tmp/glissando-state` because the greeter's HOME is a tmpfs), and **both** desktop entries now `Exec=/usr/local/bin/glissando-launch-system`. `/usr/share/applications/sm.puri.OSK0.desktop` was backed up to `.orig-20261028`. Sanity run as `greetd` without a display correctly logged `cannot connect to Wayland` → `falling back to the system keyboard` and stayed alive. Takes effect the next time the lock screen/greeter keyboard starts.

**Diagnostics are blind here, deliberately fixed next:** `dmesg` holds 1485 lines of which **1398 are one repeating line** (`qcom_q6v5_pas 62400000.remoteproc: Handover signaled, but it already happened`, once per second — ADSP handover IRQ never acked), leaving ~87 real lines. That is why no session crash ever had readable evidence. Also `greetd` does **not** run `[initial_session]` on restart (config verified, wrapper never executed), which is why every restart lands on the greeter instead of autologin — the 06:53 problem, still open. A wrapper `/usr/local/bin/phosh-session-logged.sh` is installed and wired into `greetd-logged.toml` for the next time a session actually starts through it.

**Still to verify:** a logout/login to confirm the override starts glissando as the session keyboard (expect the password prompt, see the 06:53 entry). Prediction *content* confirmed (159,890 words / 69,761 bigrams); actual prediction quality while typing untested. `glissando-settings` (GTK4) is not built or installed.

## 2026-10-28 - why a password is asked: the autologin session ended and greetd fell back to the greeter
User: Phosh sessions crashed a few times (only the session restarted, not the phone). Evidence on the phone: /tmp/phrog-session-7.2.10-sm6150.log shows the phrog greeter started at 00:05:26 and "launched session, exiting in 500ms" at 06:10:00 when the user typed the password; the current phoc/phosh/gnome-session are 35 min old at 06:45. greetd runs `[initial_session]` (autologin) only ONCE after it starts; whenever that session ends (crash, logout, or my `rc-service greetd restart` sessions) the greeter appears and a password is needed again. So the recurring password prompt = the autologin session dying. The session's stdout/stderr goes nowhere (no syslog), kernel ring buffer had rotated past 00:05 (the `qcom_q6v5_pas ... Handover signaled, but it already happened` line prints every second and floods dmesg - separate bug, remoteproc handover IRQ stuck), no core dumps (no coredump handler). Cause of the session crashes still unknown. Next: wrap the autologin command so it logs stdout/stderr + exit signal to ~/.local/state and enables core dumps; consider a greetd setting that restarts the autologin session after a crash.

## 2026-10-27 night - notch handling in Phosh (clock no longer hidden behind the notch)
Problem: Phosh had no cutout data for xiaomi,violet (libgmobile compiles its device table in), so the centred clock ("Oct 27 23:19") sat under the waterdrop notch (composited the box over a VNC capture: it hid "27 23"). Fix without rebuilding anything: `phone/gmobile/xiaomi,violet.json` (name, x-res 1080, y-res 2340, cutout path) installed in /usr/local/share/violet-gmobile/ and selected via `export G_RESOURCE_OVERLAYS=/mobi/phosh/gmobile/devices/display-panels=/usr/local/share/violet-gmobile` in /home/user/.phoshdebug (sourced by phosh-session). Geometry source: LineageOS android_device_xiaomi_violet overlay `config_mainBuiltInDisplayCutout = M -80,0 L -80,80 L 80,80 L 80,0 Z` (160x80 px, top centre; status bar 80 px, software corner radius 103 px). Phosh's layout-manager (src/layout-manager.c get_clock_pos) moves the clock LEFT only if network_box(120 logical px)+clock(40)-notch.x <= 0, i.e. the notch must start at physical x >= 480 (scale 3), otherwise RIGHT (clock becomes the right-most item, battery icon ends up inside the notch). So the notch path is the 120 px box `M 480 0 L 480 80 L 600 80 L 600 0 Z` (the real waterdrop is narrower than LineageOS's generous 160 px box). Result (VNC capture): `Oct 27 23:35 [wifi] ...notch gap... [battery] 98%` - clock+date left, wifi, battery % far right, nothing under the notch. Debug aid: `PHOC_DEBUG=cutouts` makes phoc draw the cutout box (removed from .phoshdebug again). Cutouts are read at session start only (restart needed after editing the JSON). Side notes: show-battery-percentage stays true; lockscreen settings were already require-unlock=false, lock-enabled=false, disable-lock-screen=true but a password is still asked at session start (cause unknown, to capture at next cold start). Screen capture over VNC works (see memory note).

## 2026-10-27 night - clock fixed: PMIC RTC enabled with an SDAM-backed offset (flashed)
Problem: no rtc0 (pm6150_rtc was status=disabled), so the system clock started at 1970-01-01 at every boot until chrony reached an NTP server over WiFi (and never when offline). Findings: the PMIC RTC counter is read-only for Linux (with `allow-set-time` the write RTC_SET_TIME fails EPERM), so the pm8xxx driver must run in offset mode: counter + offset, the offset stored in an nvmem cell. DT (violet-sm6150.dts, backup dt/violet-sm6150.dts.20271027-pre-rtc): `pm6150_sdam_6: nvram@b600 (qcom,spmi-sdam)` with cell `rtc-offset@b4 reg <0xb4 4>` (the SDAM driver only exposes offsets <= 0xbf; vendor QG uses 0x45-0xb3 and 0xbc-0xbd, so b4-b7 is free; 0xe0 was rejected: "Invalid SDAM offset 0xe0"), `&pm6150_rtc { nvmem-cells = <&rtc_offset>; nvmem-cell-names = "offset"; status = "okay"; }`. Kernel config: CONFIG_NVMEM_SPMI_SDAM m -> y so rtc0 is ready before CONFIG_RTC_HCTOSYS runs. Wrote the time once with `hwclock --systohc` after NTP sync. Verified: after a reboot at uptime 0 (no wlan0 yet) dmesg `setting system clock to 2026-10-27T17:45:38 UTC`. Flashed as boot-mainline-native-rtc-2026-10-27.img (rollback unchanged, see above). Also noticed at boot: `msm_dpu ... vblank wait timed out on crtc 0` + a drm_vblank WARNING at ~7 s during fbcon init under native boot (not investigated yet). Note: chrony `rtcsync` keeps the offset updated (writes deferred to shutdown if drift < 30 s).

## 2026-10-27 night - NATIVE MAINLINE BOOT FLASHED (boot partition), kexec no longer needed
Steps: (1) /boot fsck (initramfs entry cleared and restored from the boot.img ramdisk); root fs clean; /vendor (mmcblk0p86) has real damage, left alone. (2) 1.9008 GHz prime OPP re-enabled (delete-node removed): 85 s of 4 busy loops + 4 memcpy procs at cpu6 1.9 GHz, 74 C, survived; the earlier "CPU crash" was the protected-DRAM bug. (3) `mk-bootimg-clean.sh` (CMDLINE override, no UART console / ath10k debug mask / trace events) built boot-native-test.img (Image 7.2.10 + violet-sm6150.dtb with both reserved-memory entries + the r9/pmOS ramdisk); `fastboot boot` (RAM only) came up on its own: session, phosh-osk-stevia started by itself, wlan0 up, battery 99 %, 8-proc memstress ok. (4) Flashed: `fastboot flash boot boot-mainline-native-2026-10-27.img` (== boot-native-test.img). Bootloader unlocked, non-A/B. **Rollback:** the old boot partition (r10) is dumped bit-exact in device-backup/boot-partition-before-native-2026-10-27.img (first 66621440 B == ~/violet-pmos/images-r9/boot-r10.img): `fastboot flash boot ~/violet-pmos/images-r9/boot-r10.img`. Enter fastboot without buttons: ./enter-fastboot.sh (mainline) or power+vol-down. After the flash the phone boots mainline natively, up 1 min, memstress passed again. Note: with no r10, a crash/hang now needs a hold-power reset; to use r10 again for debugging: `fastboot boot ~/violet-pmos/images-r9/boot-r10.img` (RAM only, nothing flashed) or reflash.

## 2026-10-27 night - filesystem check + cleanup started (native-boot prep)
- /boot (loop0p1, ext2, inside mmcblk0p87): e2fsck -fy cleared the dangling 'initramfs' entry (deleted inode 16), attached stray inode 14 (an unrelated 630 KB DTB) to lost+found. /boot/initramfs restored from the boot.img ramdisk (identical to /boot/violet-sm6150.dtb, gzip OK); kexec-test.sh / ml-boot.sh work again. Root fs (loop0p2): clean, no errors recorded (journal only). mmcblk0p86 is the Android /vendor partition: real damage (bad xattr block, extent-tree issues; e2fsck -fn aborts), left untouched on purpose (original firmware files; mounted read-only).
- Re-testing the removed 1.9008 GHz prime OPP (the earlier 'CPU crash' was very likely the same protected-DRAM bug): DT restored without the delete-node (backup dt/violet-sm6150.dts.20271027-with-opp-cap).

## 2026-10-27 night - CONFIRMED FIXED: no more crash under load
After reserving the protected DDR tail (0x173000000-0x17dcfffff) and the 6 MiB hole (0x93500000), the user played YouTube 1080p in Firefox with no crash, the phone stayed up >16 min in the user session, Showtime played the AV1 clip with load ~2 and no reset (70 s monitored), the 8-proc memory stress that hung 6/6 times finished, and a 2.3 GB physical page walk completed. The "Firefox / video / apk / anything that uses memory crashes the phone" bug is the unreserved firmware-protected DRAM, not display/GPU/audio/CPU/power. Reverted/irrelevant experiments left in tree: dt/violet-ddr.dtb + modules/violet-ddrvote (DDR floor, not needed), debugfs core_perf knobs (not needed), cpu6 1.9 GHz OPP removal (probably not needed either: re-test), pixman profile (disabled again, GPU composites). Follow-ups: find the exact protected range (we reserve 173 MiB; the real firmware boundary may leave RAM to reclaim), verify the reservation under native ABL boot, re-test the 1.9008 GHz OPP, fsck /boot and rootfs, keyboard autostart after a clean boot, battery sign bug.

## 2026-10-27 - ROOT CAUSE FOUND: the allocator hands out protected DDR (top 173 MiB of the high bank) - every "crash under load" was this
Method: compared r10's /proc/iomem to mainline's reserved-memory (found one unreserved hole 0x93500000-0x93afffff, 6 MiB; reserved it, still hung), then a page-by-page physical-address walker (scratchpad pfn-walk.py: keeps chunks allocated, prints phys addr every 8th page to the laptop). It died exactly after phys=0x172ff8000 (next page 0x173000000, 16 MB aligned). Reserved the tail `violet-tail@173000000` (reg <0x1 0x73000000 0x0 0x0ad00000>, no-map, 177152 KiB, to the top of the 4 GB map at 0x17dcfffff) in violet-sm6150.dts (+ the 6 MiB hole `violet-hole@93500000`, backup dt/violet-sm6150.dts.20271027-pre-memhole). Result: full 2.3 GB walk over the whole low bank (0x82600000-0xffdf8000) and high bank up to 0x17281d000 with no hang, and the 8-proc memstress (the test that hung 6/6 times) finished all 40 s. So the hang was never display/GPU/audio/CPU/power/DDR bandwidth: the buddy allocator gave a process a physical page inside a firmware/TZ-protected range (accessing it = silent PS_HOLD reset, no log). It only shows once memory use grows (Firefox, video, apk, memcpy), idle/static workloads never touch it. Open: exact start/size of the protected range (0x173000000 up to the DRAM top 0x17fffffff? the vendor DT/hyp memory map would say), whether the native ABL boot needs the same reservation (it should; the reserved-memory node is in the DT).

## 2026-10-27 - power theory REJECTED (battery only still hangs); suspect the big (gold) cluster
8-proc memstress with the phone on battery alone (USB unplugged, status Discharging, 4.31 V, ssh over WiFi): hung within ~1-2 s (battery voltage 4.313 -> 4.291 V on the last sample, no brown-out). So not a USB/charger input limit. Observations all point at the prime cluster (cpu6/7, Kryo gold): 4 procs (fit on the 6 little cores) OK; 8 procs (first to load cpu6/7) hangs instantly; the 1.9008 GHz prime OPP hangs with simple busy loops; busy loops <= 1.7088 GHz survive; Firefox/video/anim/apk all spike the big cores. Next: offline cpu6,7 and run 6 procs; then pin 2 procs on cpu6/7 only (taskset), at different big-cluster caps.

## 2026-10-27 - DDR bandwidth floor tested and REJECTED; power-supply theory next
Built modules/violet-ddrvote (+ dt/violet-ddr.dtb with a `ddr-floor` node: icc path APPSS_PROC -> mc_virt EBI1, peak 6881000 kBps like r10's pinned DDR devfreq). Facts: before the module, interconnect_summary showed ebi avg 2148702145 / peak 2147483647 (the interconnect default max vote); once the module loaded the max vote was released and ebi dropped to the module's 6.88 GB/s (without it ~4.07 GB/s peak). 8-proc memstress with the 6.88 GB/s floor held: STILL hung within seconds. So DDR frequency/bandwidth is not the cause. Remaining unifying theory: total chip power/current while USB-powered with an unconfigured SMB5 charger (all crashes = high CPU+memory/display activity: 1.9 GHz busy loops, 8 memcpy procs, video/animation in Firefox, apk install). Test: same stress on battery alone (USB unplugged, ssh over WiFi), and later a wall charger.

## 2026-10-27 - BREAKTHROUGH: the hang is heavy MAIN-MEMORY traffic, not the display
IRQ-delta tracker during the animation hang showed no storm (only arch_timer, IPI, mmc0 ~800/s). Then a pure memory-bandwidth test with NO display/browser: scratchpad memstress.sh = N python procs doing 48 MB bytearray copies. 4 procs x 20 s (~4.2 GB/s copy, 0.8-1.3 GB/s each): OK. 8 procs x 40 s: phone hung within ~1-2 s of start (monitor stopped 21:57:11, ssh dead, no kernel message). CPU-only busy loops are fine (cache resident). So video decode, software rendering of an animation, pixman, apk install all crash because they push DDR bandwidth above some threshold; display/GPU/audio/CPU-freq/venus/IRQ-storm are ruled out as causes. Hermes' display-bandwidth theory was a symptom (the DPU starves/blues because memory is the real limit?). Suspects now: DDR/LLCC/CPU->DDR bandwidth voting (icc ACV, bwmon/cpu-llcc-ddr devfreq missing in mainline DT), DDR frequency/voltage corner left wrong by our patch 0003 (ACV enable mask) or the bootloader, MX/CX corner not raised with load, or a power/current limit (USB-powered). Next: read-only look at interconnect_summary, devfreq nodes, DDR clocks on mainline vs r10's DDR OPPs; then threshold bisect (6 procs; small-buffer cache-only control).

## 2026-10-27 - Hermes findings read; H1 (display bandwidth starvation) tested and REJECTED
Hermes (docs/hermes/FINDINGS-display-hang.md) concluded the blue screen is the DPU INTF underrun colour (0xff), mainline never unmasks the INTF underrun IRQ, and the most likely cause was too-low MDP bandwidth votes (800 MB/s peak vs vendor 4.5 GB/s/pipe). Verified in tree: `if (1) /* DSIDBG */` clamps the core clock in dpu_core_perf.c; dispcc-qcs615 only has 192/288 MHz. Test (no rebuild): debugfs `core_perf` perf_mode=1, fix_core_ib_vote=4000000, fix_core_ab_vote=1200000, fix_core_clk_rate=307200000, then software-GL Firefox animation. Result: STILL hung and reset, but the user saw a WHITE/GREEN frozen frame, not the blue screen => with enough bandwidth the display no longer underruns, yet the lockup remains. So the blue screen is a consequence, bandwidth/clock hypotheses H1/H3 are out as the cause of the hang. nmi_watchdog cannot be enabled at runtime on this kernel (stays 0). Next: per-IRQ delta tracker (scratchpad irq-delta.sh) to catch an interrupt storm right before the hang, as with the earlier WLED/PMIC storms.

## 2026-10-27 - crash isolation results: it is the DISPLAY path under continuous updates (not CPU, GPU, audio, venus, idle)
Reproducible, each hung the phone within seconds with the screen on (screen must be on; with DPMS off nothing happens): AV1 720p clip autoplaying in Firefox; a plain full-screen CSS animation (no video); with CPUs capped at 1.2 GHz; with the GPU pinned at 435 MHz (devfreq min=max); with NO audio stream in the log; and finally with software compositing (pixman + WLR_DRM_NO_ATOMIC) and software-GL Firefox (GPU completely idle) -> user saw a FULL BLUE SCREEN and the phone restarted. Not reproduced by: headless GPU stress (60 s at 845 MHz, no display), 25x EGL create/destroy, CPU busy loops (<=1.7088 GHz), static pages, overnight idle. No kernel message at the hang (no dpu/underrun/smmu fault lines), softlockup_panic never fires, then PS_HOLD (APSS watchdog bite): a processor stuck below kernel detection, most likely on an MMIO/bus access. There are no /dev/video* nodes (venus not involved). Facts for the next step: disp_cc_mdss_mdp_clk runs at 288 MHz (not one of the DPU OPPs 192/256/307.2 MHz, required-opps low_svs/svs/nom on RPMHPD_CX); mdss_core_gdsc on; pixman profile reverted to .disabled (GPU compositing is the default again). Next experiments: (A) pin the DPU to its highest OPP / lowest OPP and watch; (B) interconnect bandwidth floor for the MDP paths (icc sync_state drops unclaimed votes, same family as the audio SN13 bug); (C) diff against r10's working display config (downstream DT clock rates, bw votes, DSI mode/clocks, underrun handling); (D) drm.debug=0x1ff with netconsole.

## 2026-10-27 - kexec was failing because /boot/initramfs is corrupt (Data consistency error)
`kexec -l ... --initrd=/boot/initramfs` fails with `Could not open initrd file /boot/initramfs:Data consistency error`; ext4 log: `EXT4-fs error (device loop0p1): ext4_lookup: inode #2: deleted inode referenced: 16` (the /boot ext2 partition inside the rootfs image; mounted "unchecked, running e2fsck is recommended"). Hard resets from the crashes damaged it. kexec-test.sh then sat in `until ! ping` forever (kexec -l had failed silently, the link never dropped), which looked like a hang. Workaround without repairing anything: the same initramfs is the ramdisk of /boot/boot.img; extracted to /tmp/initramfs on the phone (scratchpad `extract-rd.py`) and loaded with `--initrd=/tmp/initramfs`; `kexec -e` detached via `setsid nohup`. kexec to mainline then took <1 min. TODO (needs the user's OK, offline): e2fsck on /boot (loop0p1) and the rootfs (loop0p2), then regenerate /boot/initramfs. Also confirmed: with XDG_CURRENT_DESKTOP set in greetd-logged.toml the session now starts phosh-osk-stevia by itself (pid 5849 after reboot).

## 2026-10-27 - crash isolation data (user + me)
User: phone stayed up idle from the evening of 10-26 to the morning of 10-27 (so plain idle is NOT a trigger; it needs activity). Crashes so far all coincided with activity: video playback in the logged-in session (twice, incl. the user's blue-screen reboot), all-core CPU burn at 1.9008 GHz (OPP since removed), and an `apk add` download/install plus some UI touching (phone vanished from USB and WiFi, no kernel message). Next: one-factor tests with log streaming: UI-only (touch/scroll), load-only with screen off, video-only. Also fixed this session: OSK/XDG_CURRENT_DESKTOP for the autologin session (greetd-logged.toml, backup .hermes), user set Phosh require-unlock false.

## 2026-10-26 night - video crash reproduced in the user session; remote UI control
User reproduced: file manager -> video -> playback starts, later BLUE screen, SoC reset (r10 shows Power-off reason PS_HOLD = SoC-initiated, i.e. the armed APSS watchdog bite after a total kernel hang; no pstore, no kernel message). I reproduced it on demand: with the user logged in, `sudo -u user env XDG_RUNTIME_DIR=/run/user/10000 WAYLAND_DISPLAY=wayland-0 showtime /home/user/Videos/clip.mp4` hung the phone within seconds (monitor log stopped at cpu6 1708800 kHz, 42.5 C). The same clip played to the end in the greeter session (uid 108) without a hang. 1.9008 GHz OPP removed already, so the hang is not only that OPP. Suspects: user-session load + CPU ramp, or the display/GPU commit path under video (blue screen = DPU stops getting data). Remote UI: wayvnc listens on 127.0.0.1:5900 on the phone, tunnel `/tmp/tunnel.sh` -> 127.0.0.1:5901, `vncdotool` in /tmp/vncenv; but the VNC framebuffer is a flat grey 360x780 image (screencopy returns nothing), so input works in principle, no screenshots yet. Next experiments (each needs a user login unless autologin is set): (A) video with cpufreq capped <= 1.2 GHz; (B) video with pixman compositor; (C) `msm` drm debug logs.

## 2026-10-26 night - soak at 1.7088 GHz cap + GPU compositing re-enabled
With the 1.9008 GHz OPP removed: 120 s of 8 busy loops, uncapped otherwise (1593600/1708800 kHz, ~65 C) -- phone stayed up (ssh dropped under load but uptime shows no reset; USB NCM stalls under saturation, not a crash). Removed the old `/etc/profile.d/90-violet-pixman.sh` (now `.disabled`, it forced pixman + WLR_DRM_NO_ATOMIC) and restarted greetd: phoc now composites on the Adreno via GLES with atomic modesetting. The old GPU freezes were the WLED OVP storm (fixed 00:15 on 10-26), not the GPU. Firefox uses hardware GL again (software-GL wrapper moved to /usr/local/bin/firefox-esr.sw). Needs a user retest of Firefox and video.

## 2026-10-26 night - CPU frequency bisect: 1.9008 GHz prime-cluster OPP is the crash
8 busy loops for 45 s with policy caps (little/big kHz): 1209600/1209600 ok; 1593600/1209600 ok; 1593600/1363200 ok; 1593600/1516800 ok; 1593600/1708800 ok (65 C); uncapped 1593600/1900800 => silent PMIC Hard Reset at ~25 s (50 C). Fix staged: `&cpu6_opp_table { /delete-node/ opp-1900800000; }` in violet-sm6150.dts (backup dt/violet-sm6150.dts.20261026-pre-cpucap). Needs a longer soak and a Firefox/video retest by the user.

## 2026-10-26 night - FIREFOX/VIDEO CRASH ROOT CAUSE LEAD: all-core CPU load at max OPP kills the phone (not the GPU)
Headless GPU stress (`phone/gpu-stress.py`, 1080x1920 heavy shader, 60 s at 845 MHz turbo, plus 25x context create/destroy) ran clean: GPU is fine. Firefox with hardware GL under the pixman compositor survived 2 min. But eight busy-loops (`while :; do :; done` x8, ~25 s) at cpufreq max (policy0 1.593 GHz, policy6 1.9008 GHz, temp only ~50 C) hung the phone (ssh dead, silent reset back to r10). That matches Firefox (JIT/threads) and software video decode crashing it. Next: bisect the safe max frequency with scaling_max_freq on both policies; the fix is limiting the OPPs / fixing the CPU rail voltage handling, not GPU work.

## 2026-10-26 night - battery parked; discharge data from the unplugged run
batt-log.txt captured ~330 mA discharge (plug=0, QG window 5.3 s, vbat 4.32 V, my `ibat_ua` reads -330 mA while discharging => sign convention in violet-vbat is inverted: discharge is NEGATIVE with `-raw*LSB`; the coulomb integration and the direction filter need flipping, so q stayed at 3580000 and soc stuck at 100). QG current/voltage path itself is live and plausible. Phone then reset itself to r10 (~390 s uptime) while playing clip.mp4 / idle. Parked at user's request; user priority now: stable GPU-accelerated usable phone (Firefox + video crashes).

## 2026-10-26 night - black screen / phone vanishing when unplugged = idle suspend
gsd-power had `sleep-inactive-battery-type='suspend'`; on battery the phone suspends when idle and mainline does not come back (WiFi gone, black screen, power button did not wake it). Set `sleep-inactive-battery-type` and `-ac-type` to `nothing` for the greetd session (gsettings). Real fix (suspend/resume) is separate and not done. r10's own gauge confirmed the plugged/full state: capacity 100, Full, 0 mA, 4.385 V, matching violet-vbat (so the earlier 82 was transient).

## 2026-10-26 night - battery: real gauge work (QG-lite driver), in validation
`violet-vbat` rewritten to read the pm6150 QG hardware directly (same register formulas as the downstream qpnp-qg: V = raw*194.637 uV, I = -raw*305.176 uA on this 10A part; RT FIFO + accumulator via MASTER_HOLD; SDAM SoC byte at 0xb647 for continuity with r10 and written back) and coulomb-count a vendor-profile OCV-anchored SoC (FCC 3580 mAh). Findings: QG S2 FIFO entry = 128 samples x 100 ms = 12.8 s (CTL2=0x26, CTL3=0x0a); when current is below the S3 thresholds the QG sleeps (FIFO/accumulator empty, LAST_ADC_I = 0) so on the charger at full no current data exists; r10's SDAM SoC (82) was stale (QG catch-up after r10 boot), the pack was really ~full (4.39 V, -16 mA). Needs a discharge with load to validate the current path. Log: `batt-log.txt` (over WiFi ssh <lan-ip>).

## 2026-10-26 night - battery % jitter fix
User saw the % go up and down (voltage moves with load). violet-vbat now samples every 10 s into a 1/8 EMA and only lets the reported capacity move down while unplugged / up while plugged. Installed live (rmmod/modprobe) and in /lib/modules/.../extra.

## 2026-10-26 night - battery percentage (estimate driver)
Mainline had no power_supply at all (no QG fuel-gauge / SMB5 charger driver), so Phosh had nothing to show. Added `violet-vbat` (`patches/violet-vbat.c`, kernel `drivers/power/supply/violet-vbat.c`, CONFIG_BATTERY_VIOLET_VBAT=m, module in `/lib/modules/7.2.10-sm6150/extra`, DT node `battery` under `&pm6150_lsid0` in violet-sm6150.dts, io-channel VBAT_SNS). It maps pack voltage to % with the vendor Alium 3600 mAh 25C OCV table and reads the SMB5 USBIN/charger registers (0x1310 bit4 plugged, 0x1006 state). **Caveat:** it is a voltage estimate; while on the charger the voltage is inflated (4.39 V read -> 100 %, while r10's QG said 82 % at the same moment), so trust it on battery, not on the charger. A real fix needs a QG driver (or reading the QG SDAM SoC). r10's reading stays the reference.

## 2026-10-26 night - volume keys: DT only fix
Vendor wiring: volume down = PMIC RESIN, volume up = pm6150l GPIO2 (active low, pull-up). violet-sm6150.dts now enables `&pm6150_resin` with KEY_VOLUMEDOWN and adds a gpio-keys node (KEY_VOLUMEUP on `&pm6150l_gpios 2`). Both input devices (`pm8941_resin`, `gpio-keys`) register on mainline; confirmed working by user. Pre-change DT snapshot: dt/violet-sm6150.dts.20261026-pre-volkeys.

## 2026-10-26 night - user reports: Firefox crashes the phone; music app silent
- **Renderer:** phoc runs `WLR_RENDERER=pixman` (software compositing, /etc/phrog). The Adreno 612 probes (a630_sqe.fw / a612_rgmu.bin load after ~25 s) but `gpu_cc_gx_gfx3d_clk_src: RCG did not turn on` at boot, so the GPU is not trusted. 
- **Firefox crash:** reproduced: `firefox-esr --new-tab https://en.wikipedia.org/wiki/Linux` hard-hung the phone (ssh dead, MemAvail 2.2 GB, load 1.2, no dmesg line; watchdog brought r10 back). Same launch with `LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe MOZ_WEBRENDER=0` ran >100 s stable. Network was not the cause (wget of the same page fine). Likely Mesa/freedreno GL on the Adreno hanging the machine. Fix installed: `/usr/local/bin/firefox-esr` wrapper (`phone/firefox-esr-wrapper`) forcing software GL.
- **Music app silent:** PulseAudio only had `auto_null` (no UCM for this card). `phone/violet-audio-setup` (installed `/usr/local/bin`, autostarted via `/etc/xdg/autostart/violet-audio.desktop`) routes MultiMedia3->PRI_MI2S_RX and loads `module-alsa-sink device=hw:0,2` as default sink `violet_speaker` (50 %). 44.1 kHz float32 via `pacat` and `paplay` both drive the amp without crash. Not yet heard in g4music by the user.

## 2026-10-26 night - handed over: final mainline (WiFi + speaker) kexec'd for the user to try
Booted via kexec with the main DT (`violet-sm6150.dtb`, macros on): wlan0 present, sound card up. `play-speaker [wav]` (phone `/usr/local/bin/play-speaker`, source `phone/play-speaker`) plays through the speaker; the 10 s clip is `/home/user/Music/dandelions-10s.wav` (also `~/Music/violet-test/` on the laptop). Mic work parked for later. Mic findings this round: with macros probed LPASS/LPI regs ARE readable (the earlier hangs were with macros off); LPI gpio24 (WCD9370 reset) reads cfg 0x401 = input, pulled down => codec held in reset, so SoundWire slaves stay UNATTACHED and the card with the WCD links fails -110 `Initialization not complete`. Driving gpio24 high through /dev/mem works (reads back 1), but re-enumeration after boot was not achieved (SWR master rebind fails with irq type mismatch). Next: get the reset released before the SWR masters probe (LPI node must probe after the macros, probably by loading it from an early initramfs/udev step or giving the swr masters a reset dependency); dt/violet-mic3.dtb (LPI node, no clocks, link list with Headset Playback/Capture) is the starting DTB, load `pinctrl_sdm670_lpass_lpi` by hand after boot.

## 2026-10-26 night - SONG PLAYS (confirmed by ear) + macros/SoundWire/WCD9370 enumerate on the main DT
User heard a 10 s clip from ~/Music (Dandelions.m4a -> /var/tmp/song10.wav, 48 kHz stereo) through the speaker path (`phone/speaker-tone.sh <wav>`). Booting the main DT (`violet-sm6150.dtb`, macros + SoundWire on) unlike dt/violet-audio.dtb: both SoundWire masters come up and both WCD937x slaves bind (`sdw:2:0:0217:010a:00:4`, `sdw:3:...:3`), so LPASS registers ARE reachable when the macros are probed normally (the /dev/mem hangs were reads with the macro clocks off). dt/violet-mic.dtb adds Headset Playback (RX_CODEC_DMA_RX_0) and Headset Capture (TX_CODEC_DMA_TX_3) links like sm8250-mtp: the card then fails with `wcd9370-codec ...: Initialization not complete` / `ASoC error -110`.

## 2026-10-26 night - LPASS AHB is wholly unreachable (mic blocker narrowed)
With the macro vote (block 3) granted and a speaker stream running, /dev/mem reads of the va-macro (0x62f20000) and tx-macro (0x62ec0000) also hang the AP, same as LPI (0x62b40000). So it is not LPI specific: the whole LPASS AHB window is dead to the AP while the ADSP firmware's "LPASS_CORE_HW_MACRO_BLOCK power request" evidently does not bring up audio_core GDSC/AHB for the AP. Without that, no bolero macro, SoundWire or WCD9370 (all mics) access. Next lead: disassemble the ADSP vote handler (Hexagon, as for WiFi) to see what the block-3 power request needs. Mic still not working.

## 2026-10-26 evening - SPEAKER AUDIBLE (confirmed by ear)
`phone/speaker-tone.sh` (MultiMedia3 -> PRI_MI2S_RX -> TAS2563, dt/violet-audio.dtb, patches 0015-0018, amp PWR_CTL active during the stream): the user heard the 440 Hz tone from the phone speaker. Speaker playback on mainline works. Mic still blocked on LPI/WCD9370 reset.

## 2026-10-26 evening - LPI wedge cause found
Booting dt/violet-wcd.dtb with pinctrl_sdm670_lpass_lpi blacklisted, then modprobe by hand: q6afe cmd 0x100f4 (LPASS core HW vote) returns ADSP error 3 "Unknown cmd", so "AFE failed to vote", pm_clk enable -110, and the next LPI register access hangs the AP. External watchdog recovered to r10 in about 15 s. Conclusion: this ADSP has no HW-vote command; the LPASS core clock has to be up another way (an active AFE port) before LPI registers are touched.
Second try: booted dt/violet-audio.dtb (no LPI node), started a speaker stream (AFE island cfg ok, stream running), then read the LPI gpio24 register at 0x62b40000+0x18000 through /dev/mem (`phone/lpi-peek.sh`). The AP hung in that read (CPU6 stuck, NMI unanswered, modem crash 30 s later) and the watchdog recovered to r10. So the LPI block is not reachable even with an AFE port up; either the LPASS core clock domain needs something else, or the hypervisor/XPU blocks AP access. Mic path (WCD9370 reset via LPI gpio24) remains blocked. Nothing here is audible-tested: you were away.

Correction + third try: the vote that fails is DCODEC (block 4, "AFE failed to vote (4)"); MACRO (block 3) is accepted ("LPASS core HW vote block 3 -> 0 (handle 20)"), so "no HW-vote command" above was wrong. Tested (a) dt/violet-lpi3.dtb = LPI node with only the macro vote clock (module loaded by hand): AP hung, no printk reached; (b) stream running + block 3 voted (`phone/lpi-peek.sh`, violet_hw_vote=3, dt/violet-audio.dtb) then reading 0x62b40000+0x18000: AP hung again. All recovered through the external watchdog. LPI space stays unreachable from the AP even with the core vote granted and an AFE port up: likely hypervisor/XPU-protected or an ADSP-owned AHB clock. Mic stays blocked; speaker still unverified by ear.


# violet mainline — progress log

**Newest first.** Add each new entry directly under this header block, as a `## YYYY-MM-DD HH:MM — title`
heading (subsections `###`). Use the real wall-clock time (`date`), not a guess.

Related: [PLAN.md](../PLAN.md) (design) · [STATUS.md](STATUS.md) (what works / what doesn't, right now) ·
[RULED-OUT.md](RULED-OUT.md) (dead ends and lessons — check before re-testing anything).

> **Reordered on 2026-10-25 ~11:10** when this log was split out of PLAN.md. Entries are verbatim
> (only heading levels changed); they were in three blocks with different orderings, now merged by
> actual write order.
>
> **Date labels in one stretch are one day ahead.** The entries from "2026-10-25 - touch: bus up, chip
> silent" up to "2026-10-26 (later) — AUDIO" were written on the day *before* their label, going by the
> artifacts they cite: e.g. "2026-10-26 00:15 … prof13" matches `kexec-prof13.log` written 10-25 00:12,
> and the "2026-10-25 - touch" entries match `kexec-touch1x.log` from 10-24 ~13:00–17:00. The labels
> are left as written; their position here is the true order.
>
> The long "2026-10-26 (later) — AUDIO" entry's speaker-amp conclusions are **superseded** by the
> 2026-10-25 audio entry at the top (amp is `ti,tas2563` on `i2c@a80000`, needs `qcom,sd-lines`; the
> fault was the wrong codec driver, not the hardware).

## 2026-10-26 19:45 — amp powers on with the stream; WCD9370 reset pin was wrong (LPI gpio24, not TLMM gpio24); the LPI pinctrl experiment wedged the phone

**Amp (patches/0018):** the tas2781 driver never powered the TAS2563 without RCA configuration blocks (`tasdevice_tuning_switch()` bails out with "conf_no should be not more than 0").
A ROM-mode fallback in `tasdevice_dapm_event()` (only when `no_rca_mode` is set and `rcabin.ncfgs == 0`) now writes PWR_CTL.MODE: active on stream start, shutdown on stop. Verified over I2C (`phone/amp-probe.py`):
PWR_CTL reads 0x0c while the tone plays and 0x0e afterwards; INT_LIVE shows no TDM clock error while playing. Digital volume was set to 180 (-31.5 dB) for the test. Whether sound actually comes out is **unverified** (nobody home).

**Mic findings:** the device's own vendor DTBO (extracted from `dtbo-vendor.img` with `mkdtboimg dump`, decompiled in /tmp/dtbo) shows every microphone (AMIC2 and the digital mics DMIC0-3, powered through MIC BIAS1/3) goes through the **WCD937x codec**
and the TX macro; the codec reset is **LPASS LPI gpio24** (`lpi_pinctrl@62b40000`, func2, output-high). Our DT drives `reset-gpios = <&tlmm 24>` — the main TLMM pin 24, a different pin — so the codec has never been reset properly. The vendor LPI node takes the
clock `lpass_core_hw_vote` (the AFE LPASS core-HW vote); mainline equivalent: `clocks = <&q6afecc LPASS_HW_MACRO_VOTE>, <&q6afecc LPASS_HW_DCODEC_VOTE>` as in sm8250.dtsi.

**What happened when tried:** a DT with `lpass_tlmm: pinctrl@62b40000` (`qcom,sdm670-lpass-lpi-pinctrl`, those vote clocks) and the reset moved to it made the kexec'd mainline hang during boot (before ssh); the watchdog reset it, and the phone then
came up not in r10 but in the pmOS initramfs RNDIS gadget (USB 18d1:d001, answers ping on 172.16.42.1, no ports open) with an unrelated stuck state: **it needs a manual power-cycle**. The variant that enabled only the LPI node (no consumers) hung the same way, so the LPI pinctrl probe/clock path itself is the wedge.
Saved as `dt/violet-sm6150.dts.20261026-lpi-WEDGES-BOOT`; the main DT is back to the safe version (no `lpass_tlmm`).

**Prepared for when the phone is back (nothing run yet):** `phone/60-no-lpi.conf` (install as `/etc/modprobe.d/60-no-lpi.conf`) keeps `pinctrl_sdm670_lpass_lpi` from autoloading, `dt/violet-wcd.dtb` carries the LPI node + reset on it, and `phone/lpi-try.sh` loads the module by hand with dmesg streaming so the last line before a hang is captured.

**Next:** find why the LPI node wedges (is the AFE vote clock actually granted before the first register access? try delaying the node until q6afecc is up and keeping `status="disabled"` until the ADSP audio PD is running, or probe it by hand after boot with a `devlink`), then reset WCD9370 through LPI gpio24 and re-check SoundWire enumeration.

## 2026-10-26 18:10 — AUDIO PLAYBACK PATH WORKS: root cause was the hypervisor ignoring SMMU context banks 10-12 (audio stream 0x1721 stayed FAULT)

**Result (cold kexec boot, real DTB and the display-less audio DTB):** `aplay -D hw:0,2` through the speaker link (`PRI_MI2S_RX` + TAS2563) plays the whole 3 s tone: 24 `ASM_DATA_EVENT_WRITE_DONE` (one per 130 ms period),
no `audio_process` crash, no reset, repeatable (4 runs in a row, first attempt after boot included). The earlier "first data write crashes the audio PD" bug is gone.

**Root cause (found by dumping the SMMU over `/dev/mem`, `phone/smmu-dump.py`):** Linux programmed S2CR[29] for the audio stream 0x1721 to "translate, context bank 10", but the hardware kept
`TYPE=2 (FAULT)`. The hypervisor owns context banks 10, 11 and 12 (it already uses them for streams 0e61/0e63/0e44) and silently ignores S2CR writes that point at them; streams that landed on
banks 13/14 (fastrpc) worked. The ADSP's first PCM read therefore hit a FAULT stream, the DSP got a bus error and `audio_process` died in `memcpy`; with no `iommus` at all the same buffers were raw HLOS
physical addresses and tripped the XPU instead (the instant `PS_HOLD` reset). A direct poke of S2CR[29] through `/dev/mem` is ignored too.

**Fix:** `patches/0017` (arm-smmu-qcom.c): for `qcom,qcs615-smmu-500`, mark context banks 10-12 busy so Linux never uses them. Together with `iommus = <&apps_smmu 0x1721 0x0>` on `q6asmdai` (kept in the main DT) the stream now reads
`type=0 cbndx=13` in hardware. `patches/0016` holds the vendor-parity ASM/ADM/AFE changes (default POPP 0x10BE4 / COPP 0x10314 topologies, `endpoint_id_2 = 0xFFFF`, AFE island config before port start) and the sm8250 `violet_slave` knob;
which of them are strictly needed is not isolated yet (the SMMU fix alone was the decisive change in the last test, but they were all active).

**Not done:** the TAS2563 stays in software shutdown (`PWR_CTL` 0x0e) because its driver has no RCA/calibration firmware, so nothing is audible yet; nothing could be heard anyway (user away). Mic capture is untouched (VA codec-DMA is rejected by the ADSP; the analog mic hangs off the parked WCD9375/SoundWire).
Other dead ends this round: assigning an AP carve-out to LPASS/ADSP VMIDs (the TZ only accepts MSS_MSA shared or an exclusive vmid 4; LPASS/ADSP/ADSP_HEAP return -22), `audiopd` static process creation (resets the SoC).

## 2026-10-26 15:10 — AUDIO: the "MI2S start resets the SoC" theory was WRONG; the real faults are the ASM shared-memory stream and a DSP-side crash on the first data write

All tests with `WDT=ext` (APSS watchdog armed, self-recovers to r10 in ~15 s), DT variants in `dt/` (`violet-iommu.dtb`, `violet-audio.dtb` = iommu + no macros/SoundWire + display and GPU off), kernel patch `patches/0016` (diagnostics and experiments, WIP).

**Found and fixed (kept in the main DT):** `q6asmdai` had no `iommus`, so `q6asm-dai` sent raw physical addresses with SID -1 to the ADSP. Vendor: `&msm_audio_ion { iommus = <&apps_smmu 0x1721 0x0>; }` (SID & 0xf = 1).
Added `iommus = <&apps_smmu 0x1721 0x0>` to `q6asmdai` (mask must be 0; `0xf` makes `of_iommu` fail with -22). With it the ASM device joins an IOMMU group and the **instant SoC reset on playback is gone**.
`PS_HOLD` ("MSM controlled shutdown") was the reset cause in r10's power-off reason; it came from the ADSP touching un-translated HLOS memory.

**What now works (QUAT MI2S + dummy codec, and PRI MI2S + TAS2563 link):**
- AFE port config + `DEVICE_START` on the MI2S port: accepted, no hang, no bite. The bit clock really runs: with the audio PD healthy, `ASM_DATA_EVENT_WRITE_DONE` arrives every 130 ms (= 6240 frames at 48 kHz) for the whole 3 s tone and `aplay` finishes without error.
- Stream open / media-format / COPP open / matrix map: all ack'd with status 0. Slave mode and master mode both start.
- TAS2563 register 0x11 changes while the stream runs (it sees the clock); the amp itself stays in software shutdown (`PWR_CTL`=0x0e) because the tas2781 driver has no RCA/firmware — so nothing would be audible yet.

**Still broken — the first data write kills the ADSP audio PD:** `PDM: service 'audio_process' crash: 'EX:audio_process:2:CDAD30100000:95:PC=b035fed0'` ~9 ms after the first `ASM_DATA_CMD_WRITE_V2`
(`phys 1ffe80000 len 24960`). `b035fed0` is libc `memcpy`'s large-copy path (`dczeroa` on the destination); the destination pointer is a `0xCDAD…` fill pattern, i.e. an
uninitialised internal stream buffer. It reproduces on a cold boot every time except one lucky run (a 15 s idle stream followed by a normal one worked). Not caused by: topology IDs (tried NULL/DEFAULT POPP and COPP),
`endpoint_id_2`, hexagonrpcd running, idle time before the write, zero vs real data, master vs slave clock mode, the macros/display. The AP then wedges and the watchdog resets it.
`ADM_CMDRSP_DEVICE_OPEN_V5` returns copp id `0xb0840000` (a DSP pointer) on every run — possibly the garbage source, not understood.

**Dead ends added:** creating the ADSP `audiopd` static process with an AP remote heap (`/dev/fastrpc-adsp-secure`, `FASTRPC_IOCTL_INIT_CREATE_STATIC`, with or without `qcom,vmids = <LPASS ADSP_HEAP>`) resets the SoC instantly; do not retry as is.
VA codec-DMA mic capture (`VA_CODEC_DMA_TX_0`): the ADSP answers the config with error 3 (unsupported).

**Ideas not yet tried:** compare the DEVICE_OPEN_V5 payload byte-for-byte with the vendor's (struct padding / `dev_channel_mapping`); `ASM_STREAM_CMD_OPEN_WRITE_V3` vs `_V4`; ACDB/topology registration (`AVCS_CMD_REGISTER_TOPOLOGIES`); a remote heap taken from a `no-map` reserved region instead of `dma_alloc`; decoding the PD crash with the ADSP ELF (`/tmp/adsp/seg25.dis`, built from `adsp.b25`).

## 2026-10-26 12:50 — audio/mic retry with the WiFi lessons: still blocked on the ADSP MI2S start; mic path probed (no hang, firmware says "unsupported")

User away from home, so nothing audible was tested; every check was by DSP/kernel state. Phone runs mainline via kexec with `WDT=ext`
(APSS watchdog armed): a wedge now self-recovers to r10 in ~15 s instead of needing a Power hold — use it for every risky audio test.

1. **AP-side LPASS register users removed** (`dt/violet-noswr.dtb`: `vamacro`, `txmacro`, `rxmacro`, `swr1`, `swr2` disabled; Image #137+).
   One `audio-test` (PRI_MI2S_RX + TAS2563 link): the phone still died the instant the stream started (`tasdev-codec … conf_no` is the last
   line, ssh dead, back on r10 ~15 s later). So the SoC reset is **not** caused by the AP touching LPASS MMIO via the macros/SoundWire.
   r10 afterwards reports `PMIC@SID0 Power-on reason: Triggered from Hard Reset` (a PMIC hard reset, not an APSS-watchdog bite).
2. **Mic path via codec DMA** (`dt/violet-vacap.dtb`: extra "Debug Capture" BE `VA_CODEC_DMA_TX_0` + `linux,bt-sco` dummy codec; macros off).
   `arecord -D hw:0,0` (route `MultiMedia1 Mixer VA_CODEC_DMA_TX_0`): **no hang**, phone stayed up. The ADSP answers
   `AFE_PORT_CMD_SET_PARAM_V2` (0x100ef, `CODEC_DMA_CONFIG` 0x102B8, port 0xB021) with **error 0x3 (unsupported)**, so `prepare` fails -22.
   Param IDs, port IDs and sizes are identical to the downstream techpack, so this is the ADSP rejecting it, not a host bug: the codec-DMA/VA
   route needs something else first (bolero macro clock/vote or other cal) on this firmware.
3. **ADSP firmware strings** (`/tmp/adsp/all.bin` from `qcom/qcs615/adsp.b*`): it has `audio_core_gdsc`, `audio_core_lpaif_{pri,sec,ter,quad,qui,sen}_{ibit,ebit,osr}_clk`,
   "Remote client LPASS core power (de)voted", `LPASS_CORE_HW_MACRO_BLOCK power request failed`, and an "AHB Bus hang is detected" monitor
   (`ABTimeout`). The LPAIF clocks/GDSC are therefore ADSP-owned; whatever hangs at DEVICE_START happens inside the ADSP's own power/clock bring-up.

**Next (not done):** disassemble the AFE I2S device-start path in the ADSP image (same Hexagon method that solved WiFi: strings `AFEI2sDriver*`,
`audio_core_gdsc`, then follow the clock-enable call) to see which resource it waits for; test non-LPAIF/other port classes (TDM, AUX PCM);
the codec-DMA error 0x3 needs the same disassembly. No new kernel patch this round (DTB experiments only).

## 2026-10-26 12:05 — WiFi WORKS on mainline: station associates, DHCP, ping and DNS over wlan0

**Result (kexec boot, Image #137+):** `wlan0` associated to the home AP (`<home-ssid>`, <mac>, 2.4 GHz ch 2, -90 dBm),
got `<lan-ip>/24` by DHCP, `ping -I wlan0 1.1.1.1` 3/4 answers (~43 ms; losses only from the very weak signal) and DNS resolves.

**Root cause:** the WCN3990 HL3.x firmware answers `WMI_VDEV_START_REQUEST` for a *station* vdev with status -1 when the vdev has no
peer yet. ath10k (and mac80211) only creates the station's BSS peer *after* the vdev is started; an AP vdev works because ath10k creates
its self-peer first. Found by reading the Hexagon code of the vdev-start handler (`wlan_vdev.c`, handler at 0xb0039594): if the vdev's
word at +0xc is zero and its type is 1/2 it sends the generic "-1" start response at once (b003d7bc builds the 0x28-byte event,
`status = -1`). Confirmed on the air by dumping the WMI commands (new `wmicmd:` hex dump when `debug_mask & 0x2000`): the STA start
bytes are *identical* to the working AP start, so only the missing peer differs.
The two "Rejecting vdev_start" strings were a red herring (both skipped with requestor_id 5, still -1).

**Fix (patches/0015, `drivers/net/wireless/ath/ath10k/mac.c`):** `violet_sta_self_peer=3` (now the default) makes
`ath10k_mac_op_assign_vif_chanctx()` create the peer for `link_conf->bssid` before `ath10k_vdev_start()`; `ath10k_sta_state()` adopts that
peer instead of creating a second one (a duplicate peer asserts the firmware: "Asserted in wlan_p…"); `unassign_vif_chanctx()` and a
failed vdev start drop an orphaned early peer. Module parameter in sysfs: `/sys/module/ath10k_core/parameters/violet_sta_self_peer`
(0 = stock, 1/2 = older experiments, 3 = this fix). Replaces patch 0014.

**Why the earlier self-peer attempt failed:** it created the peer with the vdev's *own* MAC; the firmware never reports that peer
(no HTT peer-map event, wait timed out) and the host then deleted the vdev with the peer present, which asserts the firmware.

**Not done:** `50-wifi-stable-mac.conf` is still moved away (MAC is randomised per connect: <mac> this run); signal is poor
(-90 dBm, phone is far from the AP or the antenna/cal data is not tuned); roaming and 5 GHz untested; a plain reboot of mainline (not
kexec) is untested because `boot` still holds r10.

## 2026-10-26 10:45 — WiFi: AP mode works on air, scanning works, but the firmware rejects every STATION vdev start (association blocked). Long negative-result log

**Where it stands (Image #136, kexec):** `wlan0` autostarts, scans (APs listed in `nmcli`), and **an access point works**: `hostapd` on the phone (`violet-ap-test`, ch 6, WPA2, HT20)
started its AP vdev with no error and the laptop saw its beacons at 89 % (so the radio's TX and RX paths work; the phone can be a hotspot). What fails is **association as a
station**: the user typed the password for `<home-ssid>` (profile saved in NetworkManager), and every attempt dies at
`mac vdev 0 start center_freq 2417 phymode 11ng-ht40/ht20/11g -> vdev-start-response reports status error: -1 -> failed to start vdev 0 ... -22`
(mac80211 retries the three phymodes within ~30 ms, all rejected). Note the home AP is also marginal here: laptop −77 dBm, phone −85..−91 dBm from this desk.

**What the rejection looks like:** the response is the longer HL3.x layout (36 bytes, 9 words): `vdev_id 0, req_id 0, resp_type 0, status 0xFFFFFFFF, chain_mask 0, smps 0, mac_id 0, cfgd_tx/rx_streams 0`.
The command we send (decoded from a hex dump): `bcn_intval 0 (now 100), dtim 0 (now 1), requestor_id 0, flags 0, ssid empty`, channel `mhz 2417, cf1 2427, mode 7, min 0, max/reg 0x28`.
The firmware (`wlanmdsp.mbn`, HL.3.0.1-00747, 2020-12-11) has exactly two reject messages in `wlan_vdev.c`: *"Rejecting vdev_start request from requestor_id = 0x%x. start_delay_us ... max_start_delay_us"*
and *"... for vdev_id = %d ... STA + STA not supported"*. Its log messages are IDs in a metadata table (no code xrefs), and ath10k's `fw_dbglog` produced no records, so I could not see which one fires.

**Ruled out by experiment (every one via runtime knobs, `phone/vs-sweep.sh <param> <values>`, dummy PSK, same result: 3 rejections each):**
`requestor_id` 0-6,8,16,256,65536; extra start flags bits 0-7; vdev start fixed-param extension words (`preferred_rx/tx_streams` etc.); channel `min/max/reg_power/antenna`; channel flag bits 6-13;
SSID in the start command (empty / real / placeholder); vdev id 0-3; `bcn_intval`/`dtim`; retry-with-delay up to 6 x 500 ms; skipping STA keepalive / STA ps params / psmode; creating a self peer for the STA vdev
(**makes the firmware time out and crash**, so no); regdomain US/IN/00; board data generic vs violet; cloned/stable MAC vs permanent MAC (`ae:0d:..`); NetworkManager out of the way; P2P device removed
(`p2p_disabled=1`, `iw wdev del`); no other host vdev exists (only vdev 0 is ever created); QMI host-cap skip quirk; cold vs warm modem; display on/off.
**Not yet tried:** (a) a different `wlanmdsp.mbn` (probably refused by the modem's signature check); (b) finding which of the two reject paths fires (needs the fw DIAG/QDSS log, or reading the Hexagon code - `llvm-objdump --triple=hexagon` works on `fw/wcn3990/wlanmdsp-violet.mbn`, the text segment is wrapped
in `/tmp/fw.elf`-style ELF by a 20-line script; the reject message IDs `0x11ba18be` and `0x11ba0afe` are not immediates in the code); (c) the modem's coex (MWS) window: the vdev starts of the AP type work, so a coex block seems unlikely but a
2.4 GHz ch 1-2 vs LTE B40 effect is untested (the only AP in range is on ch 2; test the AP-start on ch 1/2); (d) a station connect on 5 GHz (no 5 GHz AP in range);
(e) ask linux-arm-msm / ath10k with this data.

**Kernel state:** patches 0010-0013 stand. `patches/0014-...NOT-A-FIX.patch` is the diff of the experiment knobs (all default to the stock behaviour except `bcn_intval 100 / dtim 1`
for stations); the debug hex dumps were removed. Test scripts: `phone/vs-sweep.sh`, `phone/dbglog-run.sh`, `phone/noscan-assoc.sh`; `hostapd` and `iw` apks are installed on the phone from Alpine edge (`/tmp` copies are gone).
Operational fixes made along the way: `violet-modem` now waits 120 s per attempt (the modem's own 40 s-fatal SSR restart then finishes the job); `wifi-connect.sh <SSID>` connects with a password typed locally.

## 2026-10-26 07:00 — WIFI WORKS on mainline: wlan0 up, firmware stable, active scan returns real access points (Image #121, kexec)

Result of `modem-test.sh q1` (fresh kexec of Image #121 + DTB with the changes below): `wlan0` registered, UP, firmware ran for 5+ min with no crash, and
`iw dev wlan0 scan` returned `BSS <mac>  signal -85 dBm  SSID <home-ssid>` (active scan = TX and RX work). Not yet done: associate to a network
(needs the user's SSID and password), a MAC address (ath10k logs "invalid MAC address; choosing random"), and an autostart service (the modem is still started
by hand).

**What it took (in the order they were found; every item was necessary):**
1. `/etc/mainline-stay` (see the 06:15 entry): the old `90-mainline-probe.start` rebooted every mainline boot at ~93 s, which killed all modem tests.
2. Real **rmtfs carve-out** `rmtfs@a1e00000` (0x280000, `qcom,vmid = MSS_MSA`) instead of the bogus `rmtfs@0` (physical address 0 is not RAM). The modem then talks to rmtfs.
3. **IPA** described and enabled (`qcom,sc7180-ipa` compatible, `modem-init`, smp2p `ipa` pair) **plus the IPA fw/GSI carve-outs** `0x97100000/0x97110000`
   (without them the SoC resets ~16 s after "modem is now up"). Needed for the modem to bring up its QMI services (43-45 of them).
4. **pd-mapper table fix**: `qcs615_domains[]` listed each root domain twice, so probe returned -EBUSY and service 64 never registered. One entry per domain.
5. **Removed `qcom,msa-fixed-perm`** so ath10k assigns the MSA to MSS_MSA (the vendor icnss always does).
6. **violet's own board data**: `board-2.bin` + an entry `bus=snoc,qmi-board-id=ff,qmi-chip-id=140,variant=xiaomi_violet` holding the phone's own `bdwlan.bin`
   (26328 B, differs from the generic `qmi-board-id=ff` entry); DT `qcom,calibration-variant = "xiaomi_violet"`. (The copies under `/lib/firmware/qcom/qcs615/bdwlan.*` and
   `ath10k/.../bdwlan.bin` were 0-byte files.)
7. **ath10k `thermal.c`: skip the quiet-mode WMI command on WCN3990.** This HL3.x firmware advertises `WMI_SERVICE_THERM_THROT` but asserts (`EX:wlan_process:1:WLAN RT:xxxx:PC=b0007cf0`)
   on the quiet-mode command right after vdev create, ath10k restarts it, and after four failures gives up. The cause came from the March 2026 ath10k patch for the
   OnePlus 7T (https://lists.infradead.org/pipermail/ath10k/2026-March/016890.html); the guard is `if (QCA_REV_WCN3990(ar)) return;` in `ath10k_thermal_set_throttling()`.

**Update 07:30 — it now comes up by itself after a plain kexec boot** (`ml-boot.sh auto2`, nothing typed on the phone): `wlan0` registers ~98 s after the kexec, NetworkManager
lists it (`wlan0:wifi:disconnected`) and `nmcli device wifi list` shows the real AP `<home-ssid>` (WPA1/WPA2, ch 2). Works with the greeter and the display running too
(the MDSS SMMU fault storm only slows the modem's first boot; it does not break it).
- **Autostart:** `/etc/init.d/violet-modem` (source `phone/violet-modem.initd`) starts `tqftpserv` and `rmtfs`, boots the modem, waits up to 60 s for `wlan0`, and stop/starts the modem
  up to 4 times if it does not appear (the first cold start usually hits the 40 s fatal first, the automatic restart then works; the log is `/var/log/violet-modem.log`).
  It is triggered from `/etc/local.d/50-violet-modem.start` (source `phone/50-violet-modem.start`), NOT from the runlevel: **OpenRC's dependency cache `/run/openrc/deptree`
  is dated Oct 12 while the phone's clock is near 1970 after boot, so init scripts added after Oct 12 are never picked up** (this is also why `rmtfs`, added Oct 25, never
  autostarted on any boot before; `local.d` runs fine).
- Patches saved in `patches/`: 0010 (ath10k quiet-mode guard), 0011 (pd-mapper table), 0012 (glink early intents + intent-req reuse), 0013 (rpmhpd MSS). DTS snapshot:
  `dt/violet-sm6150.dts.20261026-wifi`. Firmware: `fw/wcn3990/board-2-violet.bin` (installed as `ath10k/WCN3990/hw1.0/board-2.bin`; the generic one is `/var/tmp/board-2.bin.generic` on the phone).
- Test harness: `modem-test.sh <tag>` (kexec + `phone/modem-run.sh`, samples QRTR, scans) with env `SMART=n`, `NOBLANK=1`, `SAMPLES`, `RUNTIME`.
- **MAC:** ath10k gets a random permanent MAC each boot; `/etc/NetworkManager/conf.d/50-wifi-stable-mac.conf` (source `phone/50-wifi-stable-mac.conf`) sets `wifi.cloned-mac-address=stable`, so each connection keeps one MAC across boots.
- **Association test:** `./wifi-connect.sh` (you type SSID + password locally; it connects, checks DHCP, pings the gateway, 1.1.1.1 and a hostname over wlan0 only). Not run yet; the phone has no saved WiFi profile and the only other WiFi here is the laptop's own link.
- **Not done:** association with a real network (needs the user's SSID and password), a stable MAC (ath10k picks a random one: "invalid MAC address"), the native-boot path (`boot` still
  holds r10 by the user's choice, `dtbo` erased), a faster/first-try cold modem start, folding the DTS into a clean upstream-shaped patch.

**Earlier todo list (some now done, see above):** (a) the *first* modem start after a kexec boot gets no QRTR services and hits the usual fatal at 40 s; the automatic restart that follows
works at once. A cold-start workaround or its real cause; (b) an OpenRC service that starts `rmtfs` then the modem; (c) MAC address; (d) the native-boot (ABL) path
for all of this: `boot` still holds r10, `dtbo` is erased; (e) connect test with a real network; (f) fold the DTS/driver changes into patches.

## 2026-10-26 06:15 — CLAUDE SESSION: FOUR findings that explain most of the "wedges", and the modem is now alive with 41 QMI services

**1. The "AP wedge ~93 s after kexec" in most of my tests was a boot script, not a hardware fault.** `/etc/local.d/90-mainline-probe.start`
(kexec-era safety net) dumps diagnostics at +20 s, sleeps 45 s, then runs **`reboot -f`** on any `*sm6150*` kernel unless `/etc/mainline-stay` exists.
It also `cat`s `/sys/kernel/debug/tracing/trace` right before, which prints the "Automounting of tracing" notice at about uptime 93 s, exactly where
every kexec run ended (ipa1/2/3, varA/A2/A3, quat, sn13, ign). Created `/etc/mainline-stay` on the phone's rootfs; since then runs stay up for
minutes. **This weakens several 20:15-21:15 conclusions** that blamed an MI2S start for the freeze: the ADSP watchdog bite 0.8 s after the start is real in the
logs and is *not* explained by this, but the "SoC wedge that follows" was at least partly this script. Audio needs re-testing now (see below).
**2. rmtfs shared memory was at physical address 0** (`rmtfs@0`, not DRAM; the vendor's `reg = <0 0x200000>` means "allocate dynamically"). Now a real
carve-out `rmtfs@a1e00000` (0x280000, `qcom,vmid = MSS_MSA`, client-id 1). rmtfs-mem probes fine and **the modem now talks to rmtfs**: it opens
`modem_fs1/fs2/fsg`, `alloc 2097152 => 0xa1e00000`, reads/writes (`rmtfs -v`). Before this the modem made zero requests.
**3. IPA.** Added the IPA smp2p pair (`ipa-ap-to-modem` / `ipa-modem-to-ap`) and an `ipa@1e40000` node (`qcom,sc7180-ipa`, IPA v4.2, `modem-init`; no `ipa_fws`
exists on the device and the vendor never loads one), plus the missing **IPA firmware/GSI carve-outs** `ipa-fw@97100000` (0x10000) and `ipa-gsi@97110000` (0x5000)
(the vendor node *names* say 0x97700000/0x97710000, but its `reg` and the r10 boot log say 0x97100000). Without the carve-outs the first IPA-enabled modem boots
reset the SoC ~16 s after "modem is now up". `ipa 1e40000.ipa: IPA driver initialized`.
**4. Result:** with 2 and 3 (and the display blanked, `greetd` stopped) the modem registers on QRTR as node 0 with **41 services** (NAS, WDS, DMS, UIM, IMS,
location, "Modem embedded file system", "IPA control", servreg instance 180, ...) and **stays up for minutes** (no fatal at 40 s in the rv1 run).
**5. pd-mapper is broken in the tree:** `qcs615_domains[]` listed the same root domain twice (`adsp_root_pd` + `adsp_root_pd_pdr`, `mpss_root_pd` +
`mpss_root_pd_gps_pdr`); every entry adds `tms/servreg` for its domain, so probe returns `-EBUSY` (both instances logged `failed with error -16`) and **pd-mapper
(QRTR service 64) never registers**. Without it the modem cannot learn about `msm/modem/wlan_pd`/`kernel/elf_loader`, so it never loads `wlanmdsp.mbn`. Fixed:
one entry per domain. Module-only change (`qcom_pd_mapper.ko`, installed on the phone; the pre-change copy is `/var/tmp/qcom_pd_mapper.ko.pre-claude`).
Next: fresh run, expect service 64 on node 1, tqftpserv to receive a request for `wlanmdsp.mbn`, WLFW (69) to appear, then `wlan0`.
Also still to do: `bdwlan.*` in `/lib/firmware/qcom/qcs615/` are 0-byte files (board data), and `board-2.bin` is generic.

## 2026-10-25 21:40 — MODEM/QRTR: the glink handshake completes, but **no modem packet ever reaches QRTR** (kprobe-measured). Four leads killed with source + trace evidence

**Method (no kernel change):** installed kprobes over the QRTR transport (`qrtr_endpoint_post` = every remote→AP packet with its v1 header fields, `qrtr_node_enqueue` = every AP→remote packet, `qrtr_sendmsg` = return codes), plus `buffer_size_kb=32M` so nothing is lost to a ring wrap. Scripts: `phone/seq2.sh`, `phone/seq3.sh`, `phone/qrtr-probe2.sh` (installed as `/etc/local.d/91-qrtr-probe.start`). Run over three modem start/stop cycles on one boot; **no reboot needed**, and /etc/mainline-stay was created first.

**What glink actually does on the modem edge** (full trace, one start):
```
version      tx v1 features 0x1   rx v1 features 0x7   version_ack both ways
IPCRTR       rx OPEN -> tx OPEN_ACK -> tx OPEN -> rx OPEN_ACK      (both directions acked)
intent       rx x30 from modem: 16x128, 8x512, 5x1152, 1x8320 (liid 0..29)
intent       tx x5 to modem: 1024 each (liid 1..5)                 <- early-intent patch works
tx_data      rx iid 1 chunk 52   -> the modem's own 52-byte QRTR packet
rx_intent_req rx size 52 -> rx_intent_req_ack granted 1  (reuse check: ACK only, no new INTENT)
rx_done      tx iid 1 reuse 1
open         rx glink_ssr[0/2], SSM_RTR_MODEM_APPS[0/3]            (modem opens more channels)
tx_data      tx iid 0 chunk 52 (x2) -> rx_done iid 0 reuse 1       (AP -> modem, modem consumes it)
```
So: version, channel opens, intents in both directions, TX and RX_DONE all work on the modem edge. The transport is **not** the wall.

**The wall, measured:** in 40 s of modem uptime, over the whole system,
- `qrtr_endpoint_post` was entered **101 times, all `sn=5`** (the ADSP). **Zero** packets from the modem edge.
- `qrtr_node_enqueue` fired 78 times, **all to node 5**. Zero AP→modem enqueues from QRTR.
- `qrtr-lookup` is byte-identical before and after the modem start: node 1 (rmtfs 14, TFTP 4096) + node 5 (11 ADSP services). Nothing from modem.

So mainline QRTR never sees the modem at all — its IPCRTR payloads die *between* `qcom_glink_rx_data()` and the rpmsg callback, and all three ways that can happen are `dev_dbg` (silent at loglevel 8): unknown `rcid`, unknown intent `iid`, or a channel with `ept.cb == NULL`. The one modem-origin packet QRTR has *ever* logged is the earlier `hello from 0:-2` (src node **0**, port `QRTR_PORT_CTRL` = `0xfffffffe`, i.e. `-2` as printed) — that is the modem's own node id being 0, not a parse artefact.

**Still fatal, same number:** `fatal error without message` at **40.03 / 40.3 / 40.03 s** after "remote processor modem is now up" in three separate starts (crash #1..#4). No rmtfs requests, no services, empty crash reason. After the 4th restart the **SoC reset itself** and the phone came back on r10 unaided (no manual power cycle) — so the modem crash + repeat restarts can take the whole SoC down; treat >2 restarts per boot as risky.

**Leads killed this round (with the evidence):**
1. **`qcom_glink` intent-req reuse patch is wrong / not downstream-shaped** — false. Vendor `drivers/rpmsg/qcom_glink_native.c` (LineageOS sm6150, lineage-21) does exactly the same: find a reusable local intent ≥ size, ACK, no new INTENT. The local patch is faithful.
2. **Android control packets carry a checksum we don't set** — false. `qrtr_calc_checksum()` is only used for `QRTR_TYPE_DEL_PROC`, stored in `pkt->proc.rsvd` after `QRTR_DEL_PROC_MAGIC`. HELLO/NEW_SERVER carry no checksum; `struct qrtr_ctrl_pkt` is byte-identical to mainline's (20 B), which is why the modem's packets are 52 B too.
3. **Wrong PAS compatible / driver data** (`sm8150-mpss-pas` vs `sm7150-mpss-pas`) — false. In the sm7150-mainline fork both map to `mpss_resource_init` (crash smem 421, pas-id 4, ssctl 0x12, sysmon "modem").
4. **Missing IPCRTR `qcom,intents` sizes** — not the difference. The working sm7150/sc7180 nodes declare no `qcom,intents` either (5×1K default), and our intents are advertised and used (the modem sends with our liid 1).

**One real structural divergence found in source (not yet proven causal):** Android's `qrtr_endpoint_register()` queues a per-endpoint `say_hello` work and `qrtr_node_enqueue()` refuses everything else until that HELLO goes out (`if (!hello_sent && type != HELLO) drop`). Mainline sends exactly **one** HELLO, at module init, to `QRTR_NODE_BCAST` — before any endpoint exists — and never says hello to an endpoint when it appears. So the AP only ever answers a modem hello and never initiates one. If the modem's ipc_router gates on having *received* our hello first, this is it; that needs the in-kernel ns to send a hello on endpoint registration.

**DT deltas vs the working sibling (sm7150/sc7180, same PM6150/PM6150L, same generation):** they list `power-domains = cx, mx, mss` and `label = "modem"`; we list `cx, mss` and `label = "mpss"`. Vendor `qcom,smp2p-modem` also carries `ipa` in/out entries that our `smp2p-mpss` lacks. All three are free to try (DTB only, kexec).

**Next step (one run, no rebuild):** `echo 'file drivers/rpmsg/* +p' > dynamic_debug/control` (plus `file net/qrtr/* +p`) and repeat one modem start. The three silent drop paths then name themselves. The attempt (`seq4`) was cut short by the SoC reset before dmesg was captured.

**Also noticed:** every `bdwlan.*` in `/lib/firmware/qcom/qcs615/` is **0 bytes**, so W7 in CHECKLIST is not actually staged.

**Refinement (same day, from the sm7150-mainline v7.1_rc3 tree):** that port runs its modem + WiFi on **stock** mainline `net/qrtr` and `drivers/rpmsg/qcom_glink_native.c` — `git log` over both paths lists only upstream commits, no vendor patches. So this is *not* a missing glink/qrtr driver fix; the difference is DT/config/firmware/userspace. Our tree also already carries the two upstream commits worth suspecting, `69940b88` ("Handle IPCR control port format of older targets", `QRTR_PORT_CTRL_LEGACY = 0xffff`) and `a387e73f` ("Handle rejected intent request better"), and the vendor's `qcom_glink_handle_intent_req()` matches our reuse patch.

**probe3 (fresh boot, one modem start, `phone/qrtr-probe3.sh`): the transport *is* bound — and the modem sends nothing.**
```
before: (no modem-edge rpmsg device)
up at 29.081612
29.091692  qcom_smd_qrtr 4080000.remoteproc:glink-edge.IPCRTR.-1.-1: Qualcomm SMD QRTR driver probed
during:  4080000…IPCRTR (driver=qcom_smd_qrtr), SSM_RTR_MODEM_APPS (unbound), glink_ssr, rpmsg_ctrl
crash at  69.120304   (40.04 s after up)
trace:   199 entries, 199 written, none lost
          qcom_smd_qrtr_callback 100    qrtr_endpoint_post 99  -> all sn=5 (ADSP)
          0 packets with sn != 5, i.e. the modem emitted nothing at all this run
          dynamic debug on 55 rpmsg/qrtr files: not one glink message (the drop paths never ran)
```
So "the modem's IPCRTR endpoint has no bound QRTR transport" is **dead** — it is bound 10 ms after "up". What changes between runs is how far the modem's own ipc_router gets: in this fresh-boot start it sent **zero** packets (not even the hello); in the earlier runs (modem started later in the boot, or restarted) it sent exactly **one** 52-byte packet which also never surfaced at `qrtr_endpoint_post`. Its node id is 0 and it publishes no services in either case, then asserts at 40.0 s.

**Reading:** the AP side is ready (node 1's ns up, rmtfs 14 + tqftpserv 4096 registered, modem-edge IPCRTR bound and probing), and the modem's QRTR still comes up degraded — so the next lever is what the firmware expects from the AP *at the moment it boots*, not the glink/QRTR code. `SSM_RTR_MODEM_APPS` being unbound is the one visible AP-side hole on that edge (Android's `subsystem_restart`/SSR channel).

**probe3b (same boot, modem restarted at uptime 220 s): the missing link.** Full handshake again, and this time the modem *did* send its packet:
```
intent   tx x5 (1024, liid 1..5)
tx_data  rx iid 1 chunk 52        <- the modem's QRTR HELLO, and glink accepted it (RX_DONE sent)
rx_intent_req size 52 -> ack granted 1 ; rx_done tx iid 1 reuse 1
open     rx glink_ssr[0/2] ; open rx SSM_RTR_MODEM_APPS[0/3]
counts   qcom_smd_qrtr_callback=109   qrtr_endpoint_post=108   sn=5 for all 108
crash    40.03 s after "up"   (fatal error without message, again)
```
**So the modem's 52 bytes never reached `qcom_smd_qrtr_callback` at all** even though glink consumed the intent and sent RX_DONE. In `qcom_glink_rx_data()` the intent lookup cannot be the culprit (`dev_err` would have fired) and the channel resolves (RX_DONE went out), which leaves exactly one silent path: **`channel->ept.cb == NULL`**.

**Mechanism (fits every number):** `qcom_glink_create_ept()` installs `ept->cb` **after** `qcom_glink_create_remote()`, and `create_remote()` blocks up to 5 s waiting for the remote's OPEN_ACK. The modem opens IPCRTR, immediately sends its single QRTR HELLO and then waits for an answer — that HELLO lands inside the window where the RX path has no callback yet, so it is copied, RX_DONE'd and **dropped**. Our name service therefore never learns the modem exists (`qrtr_ns_message` never fires — confirmed, zero ns messages in any run), never greets it, and the firmware asserts 40 s later. The ADSP lives through the identical race because it keeps retransmitting; the modem sends exactly one packet.

**Fix applied to the tree 2026-10-25 21:5x** (`drivers/rpmsg/qcom_glink_native.c`, needs an Image relink because GLINK is built in):
1. `qcom_glink_create_ept()`: install `ept->rpdev/cb/priv/ops` in the remote-initiated branch **before** `qcom_glink_create_remote()`, so data arriving during the OPEN_ACK wait is delivered instead of dropped.
2. `qcom_glink_rx_data()`: the `ept.cb == NULL` drop now prints `violet: dropping %u B on %s (rcid %u): ept.cb is NULL` instead of being silent (this is the line that will confirm or kill the theory on the next boot).
Revert = move the four assignments back below the branch.

**Note (possible second landmine, not yet proven):** `qcom_glink_create_ept()` leaves `struct glink_channel *channel;` **uninitialised** before `idr_for_each_entry(&glink->rcids, channel, cid)`, so if no entry matches by name the loop leaves `channel` pointing at the *last* channel in the table and the endpoint is then installed on the wrong channel. Worth a `channel = NULL;` when this is next touched.

**Test to run once the relink finishes (tag `probe4`):** same probe, one modem start; expect the `violet: dropping …` line to disappear, `qrtr_ns_message: hello from 0` to appear, `qrtr-lookup` to gain modem services, and no fatal at 40 s.

**RESULT probe4 (Image built 22:17, kexec'd 22:2x): the fix changed nothing, and it killed its own premise.**
- Fresh-boot start: modem emitted **zero** QRTR packets again (`qrtr_endpoint_post` 99/99 `sn=5`), fatal at 40.0 s. The new `violet: dropping …` line never printed.
- Late start at uptime 139 s (the run that normally does produce the modem's packet): `tx_data rx iid 1 chunk 52` + `rx_intent_req 52` again, `qcom_smd_qrtr_callback=106`, `qrtr_endpoint_post=105`, **still 105/105 `sn=5`**, and again **no `dropping` line**.
- Third start (uptime 225 s, dynamic debug on 70 rpmsg/qrtr/soc files): the modem did not even complete a QRTR exchange this time; no glink `dev_dbg`/`dev_err` at all; fatal at 40 s.

**So `channel->ept.cb` is NOT NULL** — the diagnostic would have fired. The reorder is harmless and stays (it closes a real race), but the loss is earlier in `qcom_glink_rx_data()`: the only remaining silent exits are the two `dev_dbg` fifo paths (`Not enough data in fifo`, `Payload not yet in fifo`), i.e. the packet is *deferred* and never completed, or the `idr_find(&channel->liids, liid)` on a *different* channel instance. Distinguishing them needs dynamic debug actually enabled **in the run that produces the packet** — the last attempt did not, because the modem's behaviour is bimodal: in most starts it sends **nothing at all**, occasionally exactly one 52-byte packet.

**Revised reading:** the AP side is not the wall (transport bound, intents both ways, RX_DONE flowing). The modem's own QRTR comes up barely alive — zero packets in most starts, one hello in a few, node id 0, no services — and asserts 40.0 s after "up" every time. Next lever is the *boot-time contract* between firmware and AP (what the modem expects to find at its boot: SMEM items, SSCTL/SSR handshake), not glink/QRTR plumbing. Keep the restart budget ≤2 per boot: at 3 starts this boot the SoC stayed up but earlier boots reset.

## 2026-10-25 21:15 — r10 back in `boot`; mainline tested via kexec; downstream AFE sequence = mainline; QUAT MI2S also hangs; kernel change: SN13/SN9 keepalive

**Boot partition now holds r10** (`images-r9/boot-r10.img`, flashed ~20:50 at the user's request). Mainline is tested through `ml-boot.sh`
kexec, and gets reflashed only once audio works. `dtbo` is still erased, and r10 boots fine without it. **Lesson:** do not run r10's
`/sys/kernel/boot_adsp/boot` before a kexec; with the ADSP already running, the mainline kexec reset straight back to r10.
r10 itself has **no sound card**: the downstream `audio_notifier`/LPI pinctrl stay deferred waiting for the ADSP audio PD, so it is not a live reference.

**Downstream sequence (research-downstream-mi2s.md, LineageOS sm6150 techpack):** CLOCK_SET {v1, 0x100, 1536000, attri 1, root 0, en 1}
→ pinctrl active → (ISLAND_CONFIG if AFE API >= 4) → I2S_CONFIG v1 → DEVICE_START. This matches mainline field for field. Downstream does no
LPASS core vote for MI2S and no LPAIF_CLK_CONFIG. `clk_mode=1` (kexec audk2) failed cleanly at open with -EINVAL and did not crash.

**quat (kexec, #118 + DTB with the debug BE on QUATERNARY_MI2S_RX):** the phone wedged immediately as well, so the hang is common to every LPAIF
MI2S port and is not tied to the PRI/SEC `GCC_SDR_*` clocks. The audio TBU GDSCs all read `on`, so that is not it either.

**New hypothesis plus kernel change (shared tree):** a port start is the first time the LPASS DMA uses `qns_lpass_snoc` → `qnm_lpass_anoc`
(BCM **SN13**) → DDR. SN13 has no keepalive and no Linux consumer, so after icc `sync_state` it is voted to 0 and the first LPAIF DMA can
deadlock the NoC, hanging both the ADSP and an AP CPU (the same class as the MM1 fix). `drivers/interconnect/qcom/qcs615.c`: `bcm_sn13` and
`bcm_sn9` (`qnm_aggre1_noc`) now have `.keepalive = true`. Revert by dropping those two lines.

**Result sn13 (kexec #119):** no change; QUAT plus dummy codec still wedges at once. **Reverted** in the source (the Image is still #119 with it;
the next build drops it). **ign (kexec #119, `clk_ignore_unused pd_ignore_unused`, after one failed kexec attempt):** still wedges at once.
So it is not a clock or GDSC that Linux turns off.
**Remaining lead (new, not tried with working glink):** downstream audio waits for the ADSP **audio protection domain** (`avs/audio` on
`msm/adsp/audio_pd`, through `audio_notifier`/servreg) before using the AFE. Hermes tried `qcom,protection-domain` at 14:40, but glink was wedged
then, so servreg could never answer. With glink fixed, PDR may now work. Test: check that servreg answers (pd-mapper plus
`/sys/bus/pdr`), then add `qcom,protection-domain = "avs/audio", "msm/adsp/audio_pd";` to the q6afe node.

## 2026-10-25 20:40 — WiFi/modem on the fixed glink (#117/#118): IPCRTR opens, modem stalls after its first packet; reply-mode switch wedges the AP

**#118** adds two runtime switches (both built in): `qcom_glink.violet_intent_req_reuse` (Y = downstream reuse check, ACK only;
N = mainline new INTENT + ACK) and `q6afe_dai.violet_hw_vote` (an LPASS core HW block to vote before an MI2S prepare; 0 = off).

**wifi1 (#117, reuse=Y):** rmtfs + tqftpserv up, `echo start` → `modem is now up` in 1.3 s. The glink handshake is now clean:
VERSION, the modem opens IPCRTR, our reciprocal open is ACKed, intents flow both ways, `glink_ssr` and `SSM_RTR_MODEM_APPS` open.
The modem sends **one** 52-byte IPCRTR packet (its QRTR HELLO), then `RX_INTENT_REQ 52`; we ACK only. After that the modem sends nothing
(the AP's 52-byte packets every 5 s get RX_DONE but no reply), so no node 0 and no services. `fatal error without message` comes **40 s**
after up, as before. Recovery restarts it with the same pattern, and the phone wedged silently after the second recovery.
**wifi2 (#118, reuse=N):** about 20 s after `modem is now up`, `rcu_preempt detected stalls`, **CPU1 does not answer the NMI**, and the phone wedges.
Nothing was logged in between (no ath10k or QMI lines).

So on this modem, ACK only leaves it waiting, and a fresh INTENT lets it get further, until something hangs an AP CPU. The CPU-stuck-on-NMI
signature matches the ADSP MI2S case. Suspects: a hardware access to a block that is not powered (the WCN3990 CE space at 0x18800000 after
`modem running`, or the MSS rail after proxy unvote, since `RPMHPD_MSS` was added locally).

**vote3 (#118, audio):** `violet_hw_vote=3` → `LPASS core HW vote block 3 -> 0 (handle 20)`. The firmware **accepts** the vote, but the
SEC MI2S + dummy-codec start still gives an ADSP watchdog bite 0.8 s later. Lead (1) of research-mi2s-hang.md is dead.
**Common pattern across afe3, wifi1, wifi2 and vote3:** an AP CPU stops answering NMIs about 20 s after a remote crash, i.e. during
**recovery**. Mainline recovery takes a coredump by default, which reads the remote carve-out. A TZ-protected read would hang a CPU.
Coredump turned out to be **already disabled** on both remoteprocs, so that theory is dead.
**norecov (#118):** ADSP `recovery` disabled, then the same SEC MI2S start: the phone wedged at once, before even the watchdog line reached
the stream. So the AP hang comes from the ADSP's hang itself (a shared bus/NoC), not from mainline's recovery path. Nothing on the AP side
can avoid it. Audio needs the *right* AFE sequence, not damage control.

## 2026-10-25 20:15 — glink wedge FIXED (#117); AFE now answers. New wall: starting any MI2S port makes the ADSP take a watchdog bite (the amp is innocent)

**Fix that works (Image #117):** advertise the base glink intents in `qcom_glink_create_ept()` (straight after the open handshake),
as downstream does, instead of in `announce_create()` after the driver probe. Measured on device:
- no `AFE set params failed -110` at boot; the ADSP now returns **real DSP errors** (va_macro: `cmd 0x100f3 returned error 0x16`,
  so va_macro probes `-22` instead of `-110`; the WCD path is parked anyway);
- glink-smem IRQs keep climbing (125 → 399); IPCRTR traffic and RX_DONEs keep flowing at t=81 s; there are no
  `intent request timed out` or `no open_ack` messages (so `tx_with_rcid` never fires, and it can be reverted later);
- `RX_INTENT_REQ` on IPCRTR is now answered and the ADSP carries on, so the firmware is fine with the request *after* intents exist.

**Debug BE made real:** `qcom_snd_parse_of()` treats a codec-less link as a *front end*, so "Debug Playback" never was a BE.
It now has a dummy codec (`linux,spdif-dit`, `dummy_codec`) plus `&q6afedai dai@18 { qcom,sd-lines = <0>; }`.

**Playback results (tone440.wav into hw:0,2, live `dmesg -w` streamed to the laptop over ssh, since netconsole has no target):**

| test | path | result |
|---|---|---|
| spk1 | MM3 → PRI_MI2S_RX → TAS2563 (`clk_mode=0`) | SoC froze within 1 s, then a hardware reset (pstore empty) |
| afe1 | MM3 → SEC_MI2S_RX → dummy codec (`clk_mode=0`) | `AFE close failed -110` after 3 s, then the SoC froze/reset. **No amp in the path** |
| afe2 | same, `clk_mode=2` (no MI2S clock command) | 0.9 s after start: `watchdog received` / `crash detected in adsp: type watchdog`, then the AP recovers the ADSP; the phone wedged a while later |

**Verdict:** starting an AFE MI2S port hangs the **ADSP itself** (watchdog bite), with or without the IBIT clock command and with no
codec at all. The TAS2563 is not the cause, and probably never was the cause of the old "PMIC hard reset" either. Ruled out on
the way: GCC `SDR_*`/MI2S protected clocks (the vendor marks them `protected-clocks`, but gcc-qcs615.c does not implement them, so
mainline never gates them); the ADSP AOP load-state (`qcom,qmp` is wired).
**Open leads:** (1) this ADSP loads 44 modules from the `dsp` partition through fastrpc reverse calls (Android's `adsprpcd`).
With nothing serving them, a port start that needs a module may stall a DSP thread until the watchdog bites. Test: run
`hexagonrpcd` (pmOS) against the `dsp` partition, since fastrpc now opens. (2) LPASS/LPAIF hardware unclocked or unpowered on a native
boot. (3) "Handover signaled, but it already happened" repeats every 1 s on the ADSP smp2p (still unexplained).

**afe3 (20:20), lead (1) killed:** installed `hexagonrpcd` 0.4.0 (Alpine community apk, via the laptop) and served the `dsp` partition
(`/mnt/dsp`, with `/vendor/dsp` and `/vendor/lib/rfsa/adsp` symlinked) on `/dev/fastrpc-adsp-secure`. The ADSP attached at once and asked for
`lowi/lowi_lp.conf`, so fastrpc reverse calls now work. But the SEC MI2S port start still ends in an ADSP watchdog bite **0.85 s**
later, with no file request in between. New AP-side evidence from the same run: during the ADSP recovery, `rcu_preempt detected
stalls`, and **CPU3 stops answering NMIs**. A CPU stuck on a hung bus access is how the whole SoC freezes. The phone then wedges
and needs a manual Power hold. So every MI2S test costs a manual reboot.

## 2026-10-25 19:39 — CLAUDE SESSION (Hermes stopped): the ADSP glink edge wedges on our RX_INTENT_REQ reply; kernel change in the shared tree

**Read before the next build/flash.** The Claude session now drives the phone, and Hermes has stopped.

**Measured (glink trace, native boot, Image #115):** the ADSP services every glink command until it sends
`RX_INTENT_REQ size 40` on `apr_audio_svc`, which it needs in order to reply to q6core's first command. Mainline answers with a
new `INTENT (liid 6, 40 B)` followed by `RX_INTENT_REQ_ACK granted`. From that moment the ADSP sends **nothing** on any channel:
the glink-smem IRQ count freezes, no RX_DONE is ever sent for APR, and IPCRTR and fastrpc opens are never acked.
Reproduced on an ADSP stop/start at t=392 s, where before the stall IPCRTR and fastrpc **did** open and pass data in both
directions with RX_DONEs. So three earlier conclusions were wrong: "this ADSP never acks AP-initiated opens", "AFE is deaf",
and the servreg/PDR `-110`. Each was a symptom of this one wedge (the opens at boot were simply sent after the stall).
`tx_with_rcid` (15:40-18:55) was built on that misdiagnosis.

**Difference from downstream:** the vendor 4.14 `qcom_glink_handle_intent_req()` first looks for an existing reusable local
intent that is large enough. If it finds one, it sends **only** the ACK, with no new INTENT. Mainline always allocates and
advertises a new one. Here we had just advertised 5×1024 reusable intents, so the vendor driver would never send that INTENT.

**Change:** `drivers/rpmsg/qcom_glink_native.c` `qcom_glink_handle_intent_req()` now has the downstream reuse check. glink native is
built in, so this needs a full Image relink plus a flash. Expected: no stall after `rx_intent_req`; q6core and AFE replies arrive
(RX_DONE tx on `apr_audio_svc`); IPCRTR opens at boot; `AFE set params` stops returning `-110`. The modem edge may share the same
mechanism (its "fatal error" about 40 s after up), and will be checked after the ADSP.

**Result 1 (Image #116, 19:43): not sufficient.** The reuse check works (the trace shows only `RX_INTENT_REQ_ACK granted`, with no new
INTENT), but the ADSP still goes silent right after sending its `RX_INTENT_REQ`. The first boot of #116 also did not come up on USB for
about 5 min; the user power-cycled it and the second boot was normal. The cause of the first boot's stall is unknown (no console).
**Refined cause:** in mainline the base intents go out in `announce_create()`, which runs *after* the driver's probe, while q6core sends
its first request *from* probe. The ADSP answers at once, holds no AP intent, and has to send `RX_INTENT_REQ`, and this firmware stops
servicing the edge after sending one, whatever we reply. Downstream advertises intents as soon as the channel opens, so the ADSP
never needs to ask. **Change 2:** `qcom_glink_create_ept()` now advertises the base intents (DT `qcom,intents` or 5×1 KiB) right after
the open handshake, and `announce_create()` becomes a no-op for that channel (`intents_announced`). The reuse check stays.

**W3 result on device (2026-10-26 00:20).** The corrected DTB is flashed and the kernel confirms it:

```
OF: reserved mem: 0x8b000000..0x92dfffff (129024 KiB) modem@8b000000
OF: reserved mem: 0x93300000..0x934fffff (2048 KiB)  wlan_msa_mem@93300000
OF: reserved mem: 0x92e00000..0x932fffff (5120 KiB)  video@92e00000
OF: reserved mem: 0x0..0x1fffff (2048 KiB)          rmtfs@0
```

**It did not fix the crash.** With rmtfs serving and the map correct, the modem still dies:

```
[102.751] qcom_q6v5_pas 4080000.remoteproc: fatal error without message
[102.751] remoteproc remoteproc1: crash detected in modem: type fatal error
```

and `qrtr-lookup` during the run still shows only node 1. So W3 was necessary (the map really was wrong) but the
modem's fatal error has a different cause. Since rmtfs logs zero requests and the modem publishes no services, the
remaining suspect is the modem's QMI/QRTR path to the AP - not storage and not memory layout.

## 2026-10-26 00:05 — W3 memory map actually fixed; and an honest note on process

**The process failure first.** `CHECKLIST.md` has carried **W3 — fix the modem/MSA memory map before starting it**
all along, with the expected failure being exactly what we were seeing. I spent roughly an hour generating new
hypotheses (ADSP taking the modem down, glink cid collisions, QRTR announcement routing) and went back to the
document only when asked. Every one of those hypotheses was less informed than the checklist. Rule from here:
read `CHECKLIST.md` and `RULED-OUT.md` before proposing any new theory.

**W3 done, verified from the built DTB (not from the source):**

```
0x08b000000 +0x7e00000  modem@8b000000          (vendor: 0x8b000000 +0x7e00000)
0x092e00000 +0x0500000  video@92e00000          (vendor: 0x92e00000 +0x500000)
0x093300000 +0x0200000  wlan_msa_mem@93300000   (vendor: 0x93300000 +0x200000)
overlaps: none (except the vendor's own xbl_aop_mem/aop-cmd-db nesting)
```

Two changes were needed. The MSA was **1 MB** with a comment claiming `pil-video@93400000` would overlap it - but that
video node is talos', not violet's, and violet has nothing at 0x93400000. Restoring the full 2 MB then genuinely
collided with talos' node, so that node had to go.

**Build break and its fix (worth remembering):** deleting `pil-video@93400000` outright fails the build -

```
talos.dtsi: ERROR (phandle_references): /soc@0/video-codec@aa00000:
        Reference to non-existent node or label "pil_video_mem"
```

`video-codec@aa00000` references the label, so the node's *label* has to survive even though its address must move.
Fixed by `/delete-node/ pil-video@93400000;` plus re-declaring `pil_video_mem: video@92e00000 { ... }` in the board DTS,
and dropping our duplicate `video_region@92e00000`.

**Still not flashed**: `enter-fastboot.sh` timed out on the retry, so the phone is still running the previous image with
the old (1 MB MSA) DTB. The rebuilt `boot-mainline.img` is staged and ready.

**Also measured this round (documented in CHECKLIST §3a):**

- `rmtfs -s` is not storage; `-o <dir>` is. The service now runs `rmtfs -o /var/lib/rmtfs`, seeded from the EFS
  partitions. The modem went from dying in ~1 s to running 32-40 s.
- With rmtfs *correctly* configured the modem still asserts - `fatal error without message` 40 s after up - and
  **rmtfs logs zero requests**, so EFS is not the cause.
- The modem publishes no QRTR services; node 5 is the ADSP (proven by stopping `remoteproc0`, which removes exactly
  those 11 services). The AP is node 1.
- Battery: added the missing `ADC5_VBAT_SNS` channel to `&pm6150_adc`; reading 4.389 V on device. Percentage needs a
  power_supply driver that mainline does not have for PM6150 - deferred by user decision.

## 2026-10-25 23:30 — battery voltage readable; rmtfs now a real service; modem dies together with the ADSP

**Battery (quick win, deferred beyond this):** upstream `pm6150.dtsi` only declares the `die_temp` channel of the
PMIC ADC, so `VBAT_SNS` was never described and userspace had no pack voltage at all. Added to the board DTS:

```
&pm6150_adc {
	channel@84 { reg = <ADC5_VBAT_SNS>; label = "vbat_sns"; };
};
```

Verified on device after one flash: `in_voltage_vbat_sns_input = 4389444` (4.389 V) and `vph_pwr = 4593618`.
So voltage is readable now. A *percentage in Phosh* still needs a `power_supply` driver (PM6150 QG/charger are not in
mainline — `qcom_smbx` only supports pmi8998/pm660), so that part is deferred by user decision.

**rmtfs is now a service, with the correct flag.** `/etc/init.d/rmtfs` (kept in repo as `phone/rmtfs.initd`) runs
`rmtfs -o /var/lib/rmtfs`, seeds `modem_fs1/fs2/fsg` from the EFS partitions on first start, and is added to the
`default` runlevel. Confirmed running as `/usr/bin/rmtfs -o /var/lib/rmtfs`.

**Modem behaviour changed but is still fatal:** with the service up it survived `state=running` at 8/16/24/32 s
(previously ~1 s), then hit `crash detected in modem: type fatal error` at ~40 s — the exact window the Snapdragon-855
bring-up notes attribute to a failed `efs sync`. But at the *same instant* the ADSP also reported
`crash detected in adsp: type fatal error` (`handling crash #1`), and the modem crash follows the ADSP one by ~20 ms.

New hypothesis: the ADSP is the unstable one, and its reset takes the modem down with it. The ADSP has shown
`intent request timed out` every ~10 s on its glink edge and repeated `Handover signaled, but it already happened`,
both of which are symptoms of the glink intent/cid patches we carry. So the next experiment is to find out whether the
modem survives when the ADSP is left alone *and* whether the EFS requests actually reach rmtfs (verbose log).

Phone went dark again during that test and needs a power cycle (cue played).

## 2026-10-25 22:40 — ROOT CAUSE of the modem crash loop: `rmtfs -s` is not storage

Read `rmtfs.c` (linux-msm upstream) after the phone kept killing the modem. The option table is:

```
-o <dir>   storage root        <-- what we needed
-P         find/use raw EFS partitions by partlabel
-s         "enable sync for the mss rproc instance"  (calls rproc_init(), takes NO path)
-r         read-only
-S <slot>  A/B partlabel slot suffix
-v         verbose
```

Every invocation this session used `rmtfs -s /var/lib/rmtfs`, which does **not** set the storage directory — `-s` opens
the remoteproc sync fds and `/var/lib/rmtfs` was silently ignored. Storage therefore stayed at the default `/boot`,
which has no EFS files:

```
[storage] failed to open '/boot/modem_fs1' (requested '/boot/modem_fs1'): No such file or directory
```

So the modem's `efs sync` failed on every single boot, it asserted fatal, remoteproc recovered it, and it crashed
again — `handling crash #183 in modem` was the counter for all our attempts. The "modem was stable once" observation
was coincidence, not the rmtfs fix.

Correct command: `rmtfs -o /var/lib/rmtfs` (add `-r` for a read-only EFS, `-P` to use the raw partitions by name).

**Still to verify:** whether the modem now survives with `-o` — the first attempt got it to `state=running` at 8 s and
16 s (vs crashing in ~1 s before), then the phone itself rebooted/hung at ~24 s and USB went away. Needs a power cycle
and one clean retest.

**Also found:** restarting the modem re-probes the pd-mapper subdevice and fails `-16 (EBUSY)` —
`qcom_pd_mapper.qcom-pdm-mapper qcom_common.pd-mapper.1: probe with driver qcom_pd_mapper failed with error -16`. Harmless
today (the first instance keeps serving) but it means only one pd-mapper subdevice can bind.

**Confirmed node identity:** stopping `remoteproc0` (adsp) removes exactly the 11 services on QRTR node 5 and nothing
else, so **node 5 = ADSP**. The modem publishes **no** services at all.

## 2026-10-25 21:30 — ADSP restart test kills the ordering theory; audio reproduces exactly at the AFE

**Ruled out: "the ADSP booted before pd-mapper existed".** Restarted the ADSP *after* pd-mapper was loaded:
`echo stop > /sys/class/remoteproc/remoteproc0/state` → `offline` (clean, no hang) → `start` → `running`. The restart
is safe and non-destructive: `/dev/snd` keeps `controlC0 pcmC0D0c pcmC0D1c pcmC0D2p pcmC0D4p timer`, all 10 QRTR
services come back, and APR re-enumerates `aprsvc:service:4:3/4/7/8`. But `/sys/bus/pdr/devices` is **still empty**.

Conclusion: this ADSP image never registers its protection domains with a servreg locator, regardless of ordering. The
PDR route to `avs/audio` is closed on this firmware; the `-110` is not a startup-race we can fix by sequencing.

**Audio reproduced to the exact message.** My earlier `-22` was self-inflicted — the `PRI_MI2S_RX Audio Mixer
MultiMedia3` switch was `off`, so `hw:0,2` had no route and `aplay` failed at open. With it on:

```
qcom-q6afe aprsvc:service:4:4: AFE set params failed -110
q6afe-dai ...: mi2s clk: mode=0 ibit_id=256 -> -110
qcom-q6afe aprsvc:service:4:4: AFE enable for port 0x1000 failed -110
q6afe-dai ...: fail to start AFE port 10
ASoC error (-110): at snd_soc_dai_prepare() on PRI_MI2S_RX
```

Stream opens, buffers allocate (`BUFFER_SIZE 24960`), then the AFE command on APR service 4 / port 4 gets no reply at
all. So the blocker is the ADSP's AFE service not answering — not PDR, not DTS, not the codec, not the amp.

**Lesson for future attempts:** always confirm the mixer route switch is on before reading a `-22` as a driver fault.

## 2026-10-25 20:45 — root-PD lookups fixed; wlan_pd servreg appears; ath10k rebind shows missing xo-cal-data

Two cheap experiments, no flash and no reboot:

**1. PDR roots now resolve.** `tms/pdr_enabled` on `msm/adsp/root_pd` / `msm/modem/root_pd` failed with `-6` (ENXIO)
because `qcs615_domains[]` only carried `adsp_root_pd` (services `{ NULL }`), not `adsp_root_pd_pdr` (which is the
entry that actually claims the `tms/pdr_enabled` service for that domain). Added `&adsp_root_pd_pdr` with a comment.
After reloading `qcom_pd_mapper.ko` + `pd_trigger`, all four lookups register cleanly and the root lookups stop
erroring. `pd-trigger` now requests, in order: `tms/pdr_enabled`@adsp/root, `tms/pdr_enabled`@modem/root, `wlan/fw`
@wlan_pd, `avs/audio`@audio_pd.

**2. `Service registry notification service, instance 180` is now advertised on QRTR.** Instance 180 is exactly
`msm/modem/wlan_pd` (matches `modemuw.jsn`'s `qmi_instance_id: 180`), so the WLAN protection domain is at least
visible to the service registry — the first sign of it in the whole bring-up. Audio still returns
`register listener txn wait failed: -110`; WLFW (69) still absent.

**3. Reloading `ath10k_snoc` (free, ~40 s) produced one new clue** with the debug mask on:

```
ath10k_snoc 18800000.wifi: snoc xo-cal-data return -22
ath10k_snoc 18800000.wifi: qmi msa.paddr: 0x93300000 , msa.vaddr: 0xcb2ebf55
ath10k_snoc 18800000.wifi: snoc probe
```

`qcom,xo-cal-data` is missing from the wifi node (`-22` = invalid argument, the property is absent). It is the XO trim
value programmed into the chip during power-up, so it is **not** the current blocker (the chip never powers up), but it
must be added before a successful WLFW handshake can boot the chip. Note `msa.vaddr` looks like a raw ioremap cookie —
normal.

Still open: the modem publishes **no** QRTR node of its own, which is why the `wlan_pd` PDR request returns
`0x7FFFFFFF` — the domain's owner never answers.

## 2026-10-25 20:10 — pd-trigger module: PDR requests now exist; audio servreg answers -110; WLFW still absent

Wrote `pd-trigger/pd-trigger.c` (~80 lines, out-of-tree module, built with `make M=$PWD` against this tree) that
allocates a PDR handle and registers the two lookups nothing in mainline ever asks for:

```
pdr_add_lookup(pdr, "wlan/fw",   "msm/modem/wlan_pd")
pdr_add_lookup(pdr, "avs/audio", "msm/adsp/audio_pd")
```

Loaded on the phone, pd-mapper resolves both descriptors correctly:

```
pd-trigger: requested wlan/fw on msm/modem/wlan_pd
PDM: found msm/adsp/audio_pd / 74      -> service 'avs/audio' offset 0 returning 1 domains (of 1)
PDM: found msm/modem/wlan_pd / 180     -> service 'wlan/fw'   offset 0 returning 1 domains (of 1)
pd-trigger: msm/adsp/audio_pd  -> state 268435455
pd-trigger: msm/modem/wlan_pd  -> state 2147483647
```

**Instance ids confirmed against the device's own firmware**: `modemuw.jsn` in the `modem` partition carries
`"qmi_instance_id": 180`, exactly matching `mpss_wlan_pd` in `qcs615_domains`; audio is 74 in both. So the
descriptors are right and this is not a pd-mapper data problem.

**The audio path now has a hard, measurable failure point:**

```
PDR: msm/adsp/audio_pd register listener txn wait failed: -110
```

The request reaches the ADSP's servreg (QRTR node 5, service 66, instance 74) and times out. Meanwhile the ADSP is
fully visible on QRTR for the first time — it advertises 10 services:

```
15 Test service (x3)   43 Subsystem control   66 Service registry notification (inst 74)
51 CoreSight (x2)      24 Thermal mitigation  400 Snapdragon Sensor Core
769 SLIMbus control    4098
```

So QRTR↔ADSP is healthy in both directions and the remaining audio blocker is the ADSP's servreg listener itself.

**WiFi:** the `wlan_pd` request returns `0x7FFFFFFF` (no owner answered), WLFW (69) never appears, and the modem
registers **no** services on QRTR at all — its IPCRTR rpmsg device is present and bound to `qcom_smd_qrtr`, but no
node has any service. Suspects, in order: the modem needs `tms/pdr_enabled` on its own root PD first (PDR domains are
hierarchical), or the modem's QMI stack needs the memshare/MSA hand-over before it publishes anything.

Also noticed: `qcom_q6v5_pas 62400000.remoteproc: Handover signaled, but it already happened` once per second on the
ADSP edge since the PDR attempt — new noise, worth watching.

## 2026-10-25 19:40 — modem STABLE with rmtfs serving EFS; modem QMI services appear; WLAN domain still not started

New Image flashed (the `tx_with_rcid` glink fix). Verified live on the ADSP edge:

```
glink-edge: IPCRTR: no open_ack from remote, tx will use rcid 1
glink-edge: fastrpcglink-apps-dsp: no open_ack from remote, tx will use rcid 3
```

**The modem crash was `efs sync failed`, not glink.** Set up rmtfs properly — copies of the EFS partitions served
from a directory, never the live partitions:

```
/var/lib/rmtfs/modem_fs1  <- /dev/disk/by-partlabel/modemst1   (8 MB)
/var/lib/rmtfs/modem_fs2  <- /dev/disk/by-partlabel/modemst2   (8 MB)
/var/lib/rmtfs/modem_fsg  <- /dev/disk/by-partlabel/fsg        (8 MB)
rmtfs -s /var/lib/rmtfs
```

With that running **before** `echo start > /sys/class/remoteproc/remoteproc1/state`, the modem survives past the
40 s EFS window (`state=running` at 8/16/24/32 s; it only showed `crashed` in runs where rmtfs had died).

**The modem now advertises real QMI services on QRTR** (node 5) — this is new:

```
 15 Test service              43 Subsystem control service     66 Service registry notification
 51 CoreSight remote tracing  24 Thermal mitigation            400 769 SLIMbus control 4098
```

and pd-mapper *is* being talked to by the modem:

```
PDM: service 'tms/pdr_enabled'      offset -1 returning 0 domains (of 0)
PDM: service 'tms/pddump_disabled'  offset -1 returning 0 domains (of 0)
```

**Still missing: WLFW (0x45/69) and the WLAN protection domain.** `qcs615_domains` already contains
`mpss_wlan_pd` = `msm/modem/wlan_pd`, instance 180, services `kernel/elf_loader` + `wlan/fw`, and pd-mapper
advertises it — but the modem never asks for `kernel/elf_loader`, so its WLAN elf loader never runs, so it never
requests `wlanmdsp.mbn` over tqftp (tqftpserv logs no requests at all) and WLFW never appears.

Reference: the 0xd.to Snapdragon-855 WCN3990 bring-up (same silicon layout: `qcom,icnss@18800000`, `qcom,mss@4080000`
PAS id 4) documents exactly this ordering — WLAN lives as a PD inside the modem firmware, and it needs *all four*
servers up before the modem starts: rmtfs (else `efs sync failed` ~40 s), tqftpserv (`server_check.txt` write),
pd-mapper (`kernel/elf_loader` reply), and memshare (MSA hand-over via TZ). We now have the first three; the open
question is what makes the WLAN PD *start* — on Android that's `icnss` issuing the PDR request, which mainline
ath10k does not do.

Next candidates: (a) request `msm/modem/wlan_pd` from the AP side (a tiny PDR client, or teach the pwrd?); (b) check
whether the instance id 180 matches the device's own `modemuw.jsn` from the modem partition; (c) mainline sm8150-hdk
works with the same ath10k and no PDR client, so compare its mpss firmware packaging (`qcom/sm8150/modem.mbn`,
merged) against our `.mdt` + segments.

## 2026-10-25 18:55 — build gotcha + reworked TX-cid approach (built, not yet flashed)

**Gotcha worth remembering:** `CONFIG_RPMSG_QCOM_GLINK=y` while `CONFIG_RPMSG_QCOM_GLINK_SMEM=m`, so
`qcom_glink_native.c` is compiled **into the Image**, not into `qcom_glink_smem.ko`. Rebuilding the module after an
edit to `qcom_glink_native.c` silently produces an unchanged `.ko` (same size, no new strings) and changes nothing
on the phone. Verify with `strings qcom_glink_smem.ko | grep <new message>`; every native glink change needs a full
`make Image` + flash. This is why the aliasing experiment never actually ran.

**The aliasing was therefore not the destabilizer.** The modem fatal-error cycle appeared in runs where *rmtfs was
answering the modem's RFS requests*, so the prime suspect is now a bad RFS reply (the modem asks for a file, gets a
buffer it cannot read, asserts). Control experiment to run next: start the modem with rmtfs **not** running and see
whether it stays up for minutes.

**Reworked fix, built into `Image` at 16:08 and packaged into `boot-mainline.img`:** instead of aliasing lcid to
rcid (collides with the remote's id space), `qcom_glink_create_remote()` keeps its own lcid, sets
`channel->tx_with_rcid = true` when the reciprocal open ack never arrives, and the TX paths (TX_DATA, RX_DONE,
INTENT_REQ_ACK, SIGNALS) then address packets with the remote's cid via `qcom_glink_tx_cid()`. Verified present:
`strings arch/arm64/boot/Image | grep "tx will use rcid"` → 1.

Phone is dark on USB again (no NCM, no fastboot) — needs a physical power cycle before anything else can be tested.

## 2026-10-25 18:25 — glink: TX now reaches the modem (cid aliasing), QRTR is bidirectional, modem registers RFS

The previous tolerant-open patch let channels *exist* but every byte we transmitted went out addressed with a local
cid the firmware had never seen, so the remote silently dropped it. Evidence: `rmtfs: sendto(): Broken pipe` /
`failed to send open-response: Operation not permitted` exactly when the modem asked for a file, and
`glink-edge: intent request timed out` every 10 s on the ADSP edge.

`qcom_glink_create_remote()` now, after acking the remote's open, **skips the reciprocal open entirely** and aliases
the local channel id to the remote's (`idr_alloc(&glink->lcids, channel, channel->rcid, channel->rcid + 1, …)`),
because this firmware uses a single cid space: the cid in its OPEN is the id it expects on our TX_DATA.

Result on the mpss edge, first time ever:

```
qcom_glink_cmd_tx_data: tx remote: mpss channel: IPCRTR[1/1] iid: 0 chunk_size: 52
qcom_glink_cmd_rx_done: rx remote: mpss channel: IPCRTR[1/1] iid: 0 reuse: 1     <- modem consumed it
qcom_glink_cmd_open:    rx remote: mpss channel: SSM_RTR_MODEM_APPS[0/3]
```

and `qrtr-lookup` shows a *service the modem registered*:

```
  Service Version Instance Node  Port
       14       1        0    1    14 Remote file system service     <- modem RFS
       64       1        1    1 16388 Service registry locator service  <- our pd_mapper
     4096       1        0    1 16389 TFTP                                <- tqftpserv
```

(ModemManager is what sent that 52-byte QMI hello, which the modem acked.)

**Still open:** the modem then hits `crash detected in modem: type fatal error` ~20 s after start and the rproc
recovers it; `failed to send hello msg` follows. The likely cause is a cid collision: with the alias, our lcid
equals the modem's cid for that channel, which is probably not what it expects once it tracks both directions.
Next: try aliasing only for channels where the remote did not itself ack (or use `rcid | 0x8000` as the local id),
and keep ModemManager away from the modem until the channel is stable.

Also set up in this pass: `/dev/qcom_rmtfs_mem1` exists (reserved-memory node `rmtfs@0`, 2 MB at PA 0, client-id 1,
no `qcom,vmid` because the SCM reassign returns -EINVAL), and `rmtfs` + `qrtr` were installed from Alpine edge into
the phone rootfs so the modem's RFS requests can be answered at all.

## 2026-10-25 17:40 — WiFi: modem<->QRTR path proven, WLFW bootstrap is the last gate

With `ath10k_core.debug_mask=0x7fffffff` on the cmdline (now in `mk-bootimg.sh`) ath10k finally talks:

```
ath10k_snoc 18800000.wifi: received modem starting event
ath10k_snoc 18800000.wifi: received modem running event
```

That is a *positive* result: those are SSR notifications (`QCOM_SSR_*`) delivered over **QMI on QRTR from the
modem**, so QRTR name resolution works with the new mpss glink transport — the modem's QMI is reachable exactly as
intended. The WLFW lookup (`qmi_add_lookup(QMI_SERVICE_ID_WLFW)`) still never resolves, so no wiphy.

Cross-checked the vendor's own node (`qcom,icnss@18800000`, dt/ref base-sm6150.dtsi:2639) to see how Android
bootstraps the chip. Findings:

- It does **not** toggle any enable GPIO in DT either — it uses the `cnss_wlan_en_active/sleep` pinctrl states
  (gpio98), which we have now hogged high, and then speaks QMI. So the modem is what actually powers/enables the
  WCN3990; the host only asks.
- `qcom,vdd-cx-mx-config = <640000 640000>` — our `vreg_l9a_0p6` (640–728 mV, always-on) matches.
- The vendor's modem smp2p block carries an extra entry named **"wlan"** (`smp2p_wlan_1_in`, used for
  `qcom,smp2p-force-fatal-error` / `early-crash-ind`). Our `smp2p-mpss` has only master/slave-kernel.
- All four WLAN rails in our DTS are already `regulator-always-on`, so the rails are not the missing piece.

So the remaining gate is the WLFW service itself: either our modem firmware does not expose it, or it needs the
"smp2p wlan" entry / an extra QMI client registered before it appears. Next concrete steps, both cheap: (a) add the
`wlan` smp2p entry to `smp2p-mpss` and retest; (b) if WLFW still never appears, dump the modem's QMI service list
over QRTR to see what it actually offers.

## 2026-10-25 17:05 — MODEM IS UP ON MAINLINE (first time), and WiFi's real dependency chain is exposed

Three changes, one big result.

**1. `RPMHPD_MSS` added to `qcs615_rpmhpds`** (`drivers/pmdomain/qcom/rpmhpd.c`). `qcom_q6v5_pas`'s
`mpss_resource_init` attaches proxy power domains `"cx"` and `"mss"`; with only CX in the table,
`qcom_pas_pds_attach()` returned `-ENODATA` and the modem remoteproc never even probed. Now it does
(`remoteproc1: modem is available`, offline until started).

**2. Modem node + smp2p + firmware.** Labelled the existing `modem@8b000000` carve-out `modem_mem`, added
`smp2p-mpss` (smem 435/428, GIC_SPI 451, mbox `apss_shared 14`, remote-pid 1) and
`remoteproc_mpss: remoteproc@4080000` (`qcom,sm8150-mpss-pas`, wdog GIC_SPI 266, six smp2p IRQs, CX+MSS power
domains, `qcom,qmp = <&aoss_qmp>`, `firmware-name = "qcom/qcs615/modem.mdt"`). The firmware is the device's own,
copied out of the `modem` partition: `/image/modem.mdt` + `modem.b00..b27` → `/lib/firmware/qcom/qcs615/`. There is
no `mba.mbn` — this is TZ-PAS (`pas-id 4`).

Result: `sudo sh -c 'echo start > /sys/class/remoteproc/remoteproc1/state'` →

```
remoteproc1: powering up modem
remoteproc1: Booting fw image qcom/qcs615/modem.mdt, size 9100
remoteproc1: remote processor modem is now up          (1.27 s)
```

**3. Modem glink edge added** (`interrupts-extended = GIC_SPI 449`, `mboxes = <&apss_shared 12>`, `label = "mpss"`,
`remote-pid = 1`). Trace on the modem edge is a textbook healthy handshake — unlike the ADSP:

```
glink_cmd_version: tx/rx mpss version 1 (features 0x1 / 0x7), version_ack both ways
glink_cmd_open:      rx mpss IPCRTR[0/1]      <- modem opens IPCRTR
glink_cmd_open_ack:  tx mpss IPCRTR[0/1]
glink_cmd_open:      tx mpss IPCRTR[1/1]
glink_cmd_open_ack:  rx mpss IPCRTR[1/1]      <- modem DOES ack our reciprocal open
glink_cmd_intent:    rx mpss IPCRTR[1/1] 128 B intents
```

So QRTR finally has a second, healthy transport (two bound `qcom_smd_qrtr` IPCRTR devices), which is the
prerequisite for ath10k's WLFW lookup.

**WiFi state after all that:** still no wiphy, `WLAN_CE_0` IRQ count still 0, and ath10k logs only the harmless
`supply vdd-3.3-ch1 not found, using dummy regulator`. Reading the driver explains it exactly:
`ath10k_snoc_probe()` ends at `ath10k_qmi_init()` → `qmi_add_lookup(…, QMI_SERVICE_ID_WLFW, …)`, and the wiphy is
only registered from `ath10k_snoc_fw_indication()` on `ATH10K_QMI_EVENT_FW_READY_IND` (snoc.c:1389). The chip's
power-up — rails plus the WLFW `wlan_enable` request — lives in `ath10k_snoc_hif_power_up()`, i.e. **behind** that
QMI handshake. Nothing powers the WCN3990 before WLFW answers, so the sequence cannot start by itself on a cold
boot: on Android `cnss2` does the power sequencing (rails, `CNSS_WLAN_EN` on gpio98, SNOC clocks) *before* QMI.

Next steps, in order: (a) confirm whether our modem firmware even exposes the WLFW service; (b) replicate the
vendor's pre-QMI power sequencing for the chip (rails + gpio98 + the `pwrseq` "wlan" device the driver now looks
for via `devm_pwrseq_get()`), so the chip's ROM can announce WLFW.

Side note / new nuisance: the ADSP edge now logs `62400000.remoteproc:glink-edge: intent request timed out` every
~10 s — fallout from the tolerant-open patch (a channel kept open whose intents the ADSP never grants). Harmless so
far (audio card unaffected) but worth cleaning up.

## 2026-10-25 16:15 — glink: IPCRTR now opens (patch works, reproduced twice); servreg still absent

Traced the boot with `trace_event=qcom_glink` on the cmdline (kept in `mk-bootimg.sh`) and got the handshake
sequence in order, which is the first time any of this has been visible rather than inferred:

```
before the patch:                       after the patch (2 boots, reproduced):
glink_cmd_open:      rx IPCRTR[0/1]     glink_cmd_open:      rx IPCRTR[0/1]
glink_cmd_open_ack:  tx IPCRTR[0/1]     glink_cmd_open_ack:  tx IPCRTR[0/1]
glink_cmd_open:      tx IPCRTR[3/1]     glink_cmd_open:      tx IPCRTR[2/1]
glink_cmd_close:     tx IPCRTR[3/1]     glink_cmd_open_ack:  rx IPCRTR[2/1]   <-- the missing ack
                                        glink_cmd_intent:    tx/rx both ways (1 KiB TX, 128 B RX)
```

So the ADSP opens `IPCRTR` itself, we ack it, and mainline then insists on a *reciprocal* open plus its ack
(`qcom_glink_create_remote()`, drivers/rpmsg/qcom_glink_native.c:1286). This firmware only ever satisfied the first
half. The failure was never "AP-initiated opens are refused" — it was **mainline discarding a channel the remote had
already opened, because the reciprocal ack never came**.

Fixed with a local patch to `qcom_glink_create_remote()`: on the 5 s ack timeout, log a warning and return success
instead of tearing the channel down (`close_link`). After installing that `qcom_glink_smem.ko` and rebooting:
`qcom_smd_qrtr` no longer prints `failed to create endpoint`, and the trace shows the real `open_ack: rx` from the
ADSP plus intents flowing in both directions. Verified on two consecutive boots.

Still not working, measured after that:

- `qcom,fastrpc …: failed to create endpoint` → still `-12` at ~26 s. That path is a pure AP-initiated open
  (`qcom_glink_create_local()`), and for those the ADSP answers nothing at all — no ack, no reciprocal open. Since a
  locally-opened channel has no `rcid` until the remote answers, tolerating the timeout there would only produce a
  channel whose packets go to cid 0, so that is not worth patching blind.
- `qcom_pd_mapper` (with the `qcom,sm6150` table entry, dyndbg on) logs nothing and `/sys/bus/pdr/devices` stays
  empty: the ADSP's servreg client never connects to our mapper, so no `avs/audio` PD is ever registered.
- The AFE is unchanged: `AFE set params failed -110`, `mi2s clk … -> -110`, `AFE enable for port 0x1000 failed -110`.
  Audio still silent, but the card and its four PCMs are up.

Interpretation (to test next): with `IPCRTR` genuinely open, QRTR should now be able to carry servreg — the missing
piece is the ADSP actually *registering* with our pd-mapper, which on Android happens through the ADSP's own servreg
client after QRTR is up. That is the last gate between us and a working AFE, and the device-side check is whether any
QRTR traffic appears at all (no sysfs class/bus exists on 7.2, so this needs a userspace AF_QIPCRTR lookup client
rather than a sysfs peek).

## 2026-10-25 15:40 — ROOT CAUSE FOUND: this ADSP never acks AP-initiated glink channels

Three things were tried and measured; the third explains every symptom we have collected all day.

**1. Upstream Talos audio exists and is verified working — but it is AudioReach, not APR.** Le Qi's series
"arm64: dts: qcom: QCS615 Talos EVK audio support" was applied 2026-05-12 (`d962cd7c49fa`, `141d7ea5036e`):
GPR node + APM/PRM services + MI2S1 pinctrl, and a `compatible = "qcom,qcs615-sndcard"` card with a DA7212 on
PRIMARY_MI2S — "playback through headphones and capture from the headset microphone have been tested and verified
to work". Our own tree already has all of it (`talos-evk.dts`, machine driver `sc8280xp.c`, and the `gpr`/`q6apm`/
`q6prm` nodes in `talos.dtsi`). That looked like the answer until we checked the firmware: violet's stock ADSP speaks
**legacy APR** — the glink edge offers `apr_audio_svc`/`apr_apps2` and never `adsp_apps`, which is exactly what the
AUDIO comment in our own DTS says (from the vendor overlay). So the AudioReach path is not available on this firmware.

**2. The in-kernel PD mapper did not know this platform at all.** `qcom_pd_mapper` matches machines against a
hardcoded table; `qcom,sm6150` was absent, so it printed
`PDM: no support for the platform, userspace daemon might be required.` and gave up. Added
`{ .compatible = "qcom,sm6150", .data = qcs615_domains }`, rebuilt just that module (`qcom_pd_mapper.ko`), pushed it,
`depmod`, reloaded — the notice is gone, so the *mapper* half of PDR now works. That is a real fix, and it is
installed on the phone.

**3. It still cannot help, because QRTR never comes up — and that is the root cause of the whole audio blocker.**
Measured three times (boot at 25.6 s, and again after a late `modprobe` at 80.4 s and 109.0 s):

```
qcom_smd_qrtr …glink-edge.IPCRTR…: failed to create endpoint
qcom_smd_qrtr …: probe with driver qcom_smd_qrtr failed with error -12
```

`-12` is rpmsg_core masking the real error. Reading `qcom_glink_create_local()` (drivers/rpmsg/qcom_glink_native.c
:1245) shows the truth: it sends `GLINK_CMD_OPEN`, then `wait_for_completion_timeout(&channel->open_ack, 5*HZ)` and
`(&channel->open_req, 5*HZ)` — and the fastrpc failure lands in the same millisecond as qrtr's, i.e. both sat out the
5 s ack timeout. **The ADSP simply never answers an OPEN initiated by the AP.** Remote-initiated channels work
perfectly — that is why `apr_audio_svc`, `apr_apps2`, `glink_ssr` and `LOOPBACK_CTL_LPASS` all come up and why APR
itself is healthy (q6core answers).

Everything we have been chasing is one symptom of that single fact:

| blocked | needs | consequence |
|---|---|---|
| `IPCRTR` | AP-initiated open | no QRTR → no servreg → no PDR → `qcom,protection-domain` q6afe/q6apm defer forever → **no audio** |
| `fastrpcglink-apps-dsp` | AP-initiated open | no fastrpc → the 44 ADSP audio modules on the `dsp` partition can never be loaded |
| `adsp_apps` (GPR/APM) | AP-initiated open | the AudioReach alternative is closed too, even on newer firmware |

Consequence: audio on violet is **not** a codec, clock, DAI-link or amp problem any more (all of those are solved or
bypassed: `tasdevice_startup()` returns 0, `no_rca_mode=2`, MI2S pins muxed, vote removed). It is a glink
open-handshake problem, i.e. driver work, and the two candidate explanations to test next are (a) this 2019-era
`ADSP.VT.5.2` firmware expecting the downstream `VERSION_CMD`/`VERSION_ACK_CMD` negotiation before it will accept an
OPEN (mainline's `qcom_glink_native` never sends VERSION), and (b) the ADSP expecting the AP to pre-register channel
*intents* (the vendor declares `qcom,glink-channels` + `qcom,intents` up front, mainline creates channels on demand).

Also worth noting for the next session: `CONFIG_QRTR_SMD`, `RPMSG_QCOM_GLINK_SMEM`, `QCOM_FASTRPC` and
`QCOM_PD_MAPPER` must stay `=m`; built in, `glink_smem` deadlocks the ADSP boot (`build-qrtr.log`).

State after this entry: DTS reverted to the working configuration (PD properties out, `nomacrovote` kept), card 0
with `pcmC0D0c/D1c/D2p/D4p` back, patched `qcom_pd_mapper.ko` installed, and the phone boots native from ABL.

## 2026-10-25 15:25 — the `dsp` partition answers "why is this ADSP so dumb": it loads 44 audio modules at runtime

Dumped the vendor firmware partition (`/dev/disk/by-partlabel/dsp`, 32 MB, ext4, LABEL=dsp) and mounted it. It
contains exactly two trees — `adsp/` and `cdsp/` — and `adsp/` holds **44 shared objects** plus CHRE bits:

```
AudioContextDetection.so.1   AudioSphereModule.so.1   VoiceWakeup_V2_Module.so.1
fluence_voiceplus_module.so.1  HeaacDecoderModule.so.1  LdacModule.so.1  … (44 total)
```

Strings inside the image give the provenance of this ADSP: `violet-q-stable-build/vendor/qcom/non-hlos-2019-spf10/
ADSP.VT.5.2/adsp_proc/...`. So this platform's ADSP expects its audio framework modules and audio post-processing to be
**pushed into it at runtime from userspace over fastrpc** (Android does that with `adsprpcd` reading this very
partition). The firmware segments we boot (`/lib/firmware/qcom/qcs615/adsp.b*`) are *not* in this partition — they
come from elsewhere — and `adsp.b04`/`b15`/`mdt` are byte-identical to what we already install, so the firmware image
itself is consistent.

That reframes the audio blocker once more, and ties it to the thing we already saw break at boot:

- `qcom,fastrpc ... failed to create endpoint` → `-ENOMEM` at ~25 s. No fastrpc ⇒ no way to load those 44 modules
  ⇒ the ADSP's audio framework has nothing to run with.
- The same glink edge also fails to open `IPCRTR` early, which is why there is no QRTR/servreg/PDR — the second half
  of the same problem.
- APR itself is healthy (q6core answers), so the AFE service exists and simply never gets a working audio subsystem
  behind it. Every `-110` we have been fighting is a symptom of that.

Consequence for the plan: audio is not a codec/clock problem any more, it is a **fastrpc + ADSP-module-loading**
problem, and the next real step is to get the AP↔ADSP channels acknowledged (glink OPEN for `IPCRTR` and
`fastrpcglink-apps-dsp`, both of which the ADSP ignores when they are attempted at ~25 s) and then provide a
userspace rpcd that serves the modules from the `dsp` partition. Practical fallback if that proves too deep: the
vendor DT's intents-based channel declarations (`qcom,adsp_qrtr { qcom,glink-channels = "IPCRTR"; qcom,intents =
<0x800 5 0x2000 3 0x4400 2>; }`) are what downstream uses instead of mainline's on-demand channel creation, and
reproducing them is the cheapest way to test whether the ADSP will ack when the channels are announced up front.

## 2026-10-25 15:05 — audio test `nomacrovote`: the vote was NOT wedging the AFE (decisive negative)

Removed the last clock-vote consumer from the DTS — `vamacro` now takes only
`LPASS_CLK_ID_TX_CORE_MCLK` for "mclk", no `LPASS_HW_MACRO_VOTE` ("macro" and "dcodec" are
`devm_clk_get_optional`, so this costs nothing while the WCD9375 path is parked). DTB-only change, flashed.

Result: the boot-time failure is **gone** — no `AFE failed to vote (3)`, and `va_macro` probes instead of dying with
`-110` (only `qcom,dmic-sample-rate dt entry missing`, which is harmless). And yet:

```
[ 61.883386] qcom-q6afe aprsvc:service:4:4: AFE set params failed -110
[ 61.883453] … mi2s clk: mode=0 ibit_id=256 -> -110
[ 64.892134] qcom-q6afe aprsvc:service:4:4: AFE enable for port 0x1000 failed -110
[ 64.892213] … fail to start AFE port 10
```

**So the vote failure was not what made the AFE deaf.** The AFE ignores
`AFE_PARAM_ID_CLOCK_SET` and `AFE_PORT_CMD_DEVICE_START` whether or not a vote was ever attempted. That kills the
"the failed vote left the AFE in a bad state" theory and the ROCKNIX-style "probe too early" explanation for our
case, and leaves the PDR/protection-domain route as the only live hypothesis: q6core answers (it returned the AFE's
service version at probe), so APR itself works, and only the audio PD's absence remains unexplained.

Keep the `nomacrovote` DTS change: it removes a 3 s stall and an `-110` probe failure for free.

## 2026-10-25 14:40 — audio: AFE is deaf for a reason outside the codec; QRTR/PDR chain mapped, two config experiments reverted

Three more results, all measured.

**1. `qcom,protection-domain` is the missing DT property — and it needs a working PDR.** Every in-tree SoC
(`agatti`, `kodiak`, `hamoa`) declares on its `q6afe` node:
`qcom,protection-domain = "avs/audio", "msm/adsp/audio_pd";`. Our node never had it. Adding it changed q6afe's
behaviour exactly as the binding intends — and the card disappeared entirely (`/dev/snd` = `timer` only), because
q6afe then waits for the ADSP's audio PD and that PD never arrives. Reverted to a comment in the DTS so the card
and PCMs stay available; the property is the correct end state once PDR works.

**2. Why PDR cannot work yet — the QRTR chain.** `qrtr_smd` is bound to the glink `IPCRTR` rpmsg device
(`62400000.remoteproc:glink-edge.IPCRTR.-1.-1`, confirmed in `/sys/bus/rpmsg/devices`), the AF_QIPCRTR socket family
exists, and yet there is no QRTR node, no servreg, no `/sys/kernel/debug/pdr`, and `qcom_pd_mapper` logs nothing even
with dynamic debug on. So the "avs/audio" PD is never registered → PDR lookups cannot resolve → q6afe-style gates
can never open. Meanwhile at boot those same channels fail once with `failed to create endpoint` (`-ENOMEM`) for
fastrpc and IPCRTR, i.e. the AP-initiated glink OPEN is not acknowledged by the ADSP when it happens early.

**3. Building the ADSP stack in (`QRTR_SMD`, `RPMSG_QCOM_GLINK_SMEM`, `QCOM_FASTRPC`, `QCOM_PD_MAPPER` = `y`) is
worse — do not retry it.** With `glink_smem` in-kernel the ADSP never boots: `qcom_glink_smem: exports duplicate
symbol qcom_glink_smem_register (owned by kernel)` plus the classic proxy-power-domain deadlock
(`qcom-rpmhpd ... sync_state() pending due to 62400000.remoteproc`). Reverted; traceback in `build-qrtr.log`.

Also decoded from the log: `AFE failed to vote (3)` at ~24 s is the *macro* vote (`va_macro` takes `-110` right
after), and the q6afe callback has no case for an error reply to `0x100f4`, so the waiter sleeps out its whole
timeout and the probe then fails hard instead of deferring. ROCKNIX hit the identical sequence on 7.2 and fixed it
by making the audio stack probe later ("Built in, it fires ~17ms after the APR AFE service appears and the ADSP is
not ready"). Their log is character-for-character ours.

**Current working state**: card 0 with `pcmC0D0c/D1c/D2p/D4p`, amp startup gated by `no_rca_mode=2`, and every AFE
command still `-110`. Next single-variable test: disable the three unused WCD9375 macros (`va_macro`, `tx_macro`,
`rx_macro`) in DT so the boot-time vote never happens, then see whether the AFE answers — that separates "the vote
failure wedges the AFE" from "the AFE was never going to answer".

## 2026-10-25 14:10 — audio: upstream q6afe vote fix applied; AFE still unreliable (APR/glink, not the codec)

Applied upstream **patch 1/6 of "ASoC: qcom: fixes and improvements"** (Val Packett, 2026-04-23,
`[PATCH 1/6] q6afe: fix clk vote response type mismatch`) to `q6afe.c`: the firmware's vote reply is a single
`u32` client_handle, not an `APR_BASIC_RSP_RESULT`, so the driver was reading out of bounds and mis-reporting
failures. Three-line change (`vote_result` field, callback stores `*vote_res`, caller returns it). Built and
flashed (Image 13:12).

What it changed: in the first boot after flashing, `snd_soc_dai_set_sysclk()` on `PRI_MI2S_RX` **succeeded**
(`mi2s clk: mode=0 ibit_id=256 -> 0`, was `-110`), and `aplay` got as far as `Playing WAVE ... 48000 Hz, Stereo`
and wrote frames before `pcm_write: write error: I/O error` + `AFE close failed -110`.

What it did **not** fix, measured on later boots:
- `AFE failed to vote (3)` still appears at ~23 s and takes `va_macro` down with it (`probe ... error -110`);
  the response genuinely times out there, so the type fix cannot help that instance.
- Every AFE command on `PRI_MI2S_RX` now returns `-110` (`AFE set params failed -110` on `set_sysclk`,
  `AFE enable for port 0x1000 failed -110` on prepare), reproducibly, on a fresh boot too.
- Also at 25 s, independent of audio: `qcom,fastrpc ... failed to create endpoint` → `probe ... error -12`
  (-ENOMEM) and `qcom_smd_qrtr ... probe failed with error -12`. That is an ADSP glink/endpoint allocation
  failure, and it is the most likely reason APR replies stop arriving at all.

So the remaining blocker is **the ADSP's APR/glink channel**, not the amp and not the clock parameters. Evidence
from a working sibling port (`howtocuddle/xiaomi_raphael`, SM8150 + TFA9874 on QUAT MI2S) that is worth applying
here: (a) the AFE **cpu** DAI must be given `SND_SOC_DAIFMT_BP_FP` — ours already is; (b) its IBIT/sd-line config
matches ours; (c) **a crashed secondary DSP poisons the ADSP's QMI services** — violet has no SLPI/CDSP
remoteproc up, so that specific cause is out, but the `-ENOMEM` endpoints show our ADSP's glink is half-broken
from boot.

Amp side, kept from earlier work and now persistent across boots (`/etc/modprobe.d/50-violet-audio.conf`):
`options snd-soc-tas2781-i2c no_rca_mode=2` (RCA regbin absent; vendor `tas2563_uCDSP.bin` installed as
`tas2563_coef.bin` parses, calibration missing is non-fatal) and `options snd-soc-sm8250 clk_mode=0`.

Next: chase the glink endpoint `-ENOMEM` (fastrpc/qrtr endpoints), since no AFE command can succeed while it is
broken; then re-test with the first AFE access of a boot (one shot per boot appears to be what the ADSP gives us).

## 2026-10-25 12:55 — audio test `audio1`: NO PMIC reset with the right driver. Two clean blockers instead

First audio experiment on **native boot** (no kexec hand-over), DTB = `audio1`: ramoops `record-size` added, sound node
gets `pinctrl-0 = <&mi2s1_pins>`, amp node stays `okay` (disabling it makes the card fail to register — "codec dai
not found" — and then there is no PCM at all). Stream: MM3 routed to `PRI_MI2S_RX` (`amixer -c 0 cset numid=78 1`),
`aplay -D hw:0,2 tone440.wav`.

**Result: the phone did NOT reset.** It used to hard-reset the PMIC on stream start. Now it fails cleanly:

```
[  22.971742] qcom-q6afe aprsvc:service:4:4: AFE failed to vote (3)
[  22.978627] tasdev-codec 1-004c: Direct firmware load for tas2563RCA1.bin failed with error -2
[  22.978666] tasdev-codec 1-004c: Failed to read tas2563RCA1.bin
[  94.907084] qcom-q6afe aprsvc:service:4:4: AFE set params failed -110
[  94.907142] q6afe-dai …: ASoC error (-110): at snd_soc_dai_set_sysclk() on PRI_MI2S_RX
[  94.907173] tasdev-codec 1-004c: ASoC error (-22): at snd_soc_dai_startup() on tasdev_codec
[  94.907206]  Speaker Playback: ASoC error (-22): at __soc_pcm_open()
```

What this settles:
- The PMIC hard reset was the **TAS2562 driver driving a TAS2563** (the old hypothesis): with `ti,tas2563` →
  `tas2781-i2c.c` (`tasdev-codec`) nothing resets any more, even though the path still fails. `RULED-OUT.md` can
  stop calling this "AFE vs amp not separated": the amp-side crash is gone.
- `tas2563RCA1.bin` is missing exactly as `research-audio.md` §1 predicted, and `tasdevice_startup()` returns
  `-EINVAL` because of it, so **the amp has still never been powered** — this is the next real blocker on the amp
  side, and it needs the RCA regbin (PPC3/regbin tool) before any audible output is possible.
- The **AFE side is now the first failure**: `AFE failed to vote (3)` at probe time, then `AFE set params failed
  -110` (ETIMEDOUT) at `set_sysclk` on `PRI_MI2S_RX`. That is the LPASS core/HW vote the ADSP firmware answered with
  "Unknown cmd 0x100f4" — i.e. `sm8250.c`'s clock programming is not what this firmware accepts, and the ADSP is
  timing out rather than faulting (which is why we get no reset).
- Card, PCM and DAPM are all healthy throughout: `pcmC0D2p` (MM3) and `pcmC0D4p` (Debug Playback) exist, and the
  only deferred-probe noise is the WCD9375 macro chain (`txmacro`/`rxmacro`/`vamacro`/`soundwire`), which is the
  parked SoundWire item, not this path.

Also from this run: ramoops now registers with `record-size`, so a future panic/hard reset leaves
`dmesg-ramoops-N` instead of nothing.

Next (checklist A6): chase the vote/clock path — log the `q6afe` vote response, compare `AFE_PARAM_ID_CLOCK_SET`
(0x10290) vs `LPAIF_CLK_CONFIG` (0x10238), and try the `sdm845.c`-style MCLK_1 + IBIT pair; in parallel get
`tas2563RCA1.bin` (A5) so the amp can be brought up in MUTE → ACTIVE.

## 2026-10-25 12:45 — hands-free fastboot: `reboot bootloader` works (it was never the bootloader, it was the caller)

With native boot every iteration needs `fastboot flash boot`, and the only way in was Power+Vol-Down. Two
"software" attempts, one dead one live:

**Dead — `misc` BCB.** Wrote `bootonce-bootloader` into `bootloader_message` (offset 0 of `mmcblk0p50`, which was
all zeros; 4 KiB backed up to `misc-bcb-backup.bin`) and rebooted: ABL ignored it and booted Linux normally. Read
`LinuxLoader.c` to see why — the boot decision is only `GetKeyPress()` (SCAN_DOWN → fastboot, SCAN_UP → recovery,
SCAN_ESC → EDL) and `GetRebootReason()` → `switch (BootReason)`. There is **no misc/BCB parsing on the boot path**
in this ABL. BCB cleared back to zeros; that code path removed from `enter-fastboot.sh`.

**Live — the reboot-mode framework.** Our DT already has it all: `pm6150_pon` is `compatible = "qcom,pm8998-pon"`
(GEN2 reason shift 1) with `mode-bootloader = <0x2>`, and the kernel has `CONFIG_REBOOT_MODE=y` +
`CONFIG_POWER_RESET_QCOM_PON=y`. `qcom-pon.c` writes the magic into the PMIC's PON soft-reboot spare (0x8f) and
ABL's `EFIResetReason` returns `FASTBOOT_MODE`, so `LinuxLoader` sets `BootIntoFastboot` and goes straight to
`FastbootInitialize()`. This is the same path `adb reboot bootloader` uses on Android, and Qualcomm's Linux debug
guide documents `reboot bootloader` for exactly this.

The blocker was purely the userspace caller, which is why the old note said "busybox `reboot bootloader` ignored,
RESTART2 EINVAL":
- busybox 1.38 `reboot` accepts only `-d/-n/-f`, no command argument;
- glibc's `reboot()` wrapper supplies the magics itself and takes only `howto` → passing four args yields
  `EINVAL` and no reboot at all.

Working call: raw **arm64 `syscall(142, 0xfee1dead, 672274793, 0xA1B2C3D4, "bootloader")`**. Verified twice: the
phone lands in fastboot (`cb0bdec5 fastboot`, `product: violet`) within ~15 s, no buttons, no partition writes.

Installed: `/usr/local/bin/reboot-bootloader` on the phone (source `phone-reboot-bootloader.sh`, arg guard so
`--help` does not fire it) and `./enter-fastboot.sh` on the host (calls it, waits for fastboot, `--check` to poll).
Docs for the upstream question: U-Boot grew reboot-mode→fastboot handling in 2026 for chainloaded Qualcomm boards;
for ABL devices this PON path is the equivalent.

## 2026-10-25 11:56 — MILESTONE: ABL BOOTS OUR IMAGE. Native boot works (dtbo erased)

**The three-week refusal is solved, and the fix was the ABL branch, not the DTB.** `fastboot erase dtbo`, then
`fastboot flash boot boot-mainline.img` (rebuilt at 11:52 from the 11:15 Image + 96,237 B DTB, `qcom,msm-id = 355 0`,
`qcom,board-id = 34 0`), `fastboot reboot` — and mainline came up **from ABL**, no kexec:

- `uname -r` = `7.2.10-sm6150`, `/proc/device-tree/model` = `Xiaomi Redmi Note 7 Pro`, uptime counted from the flash.
- `/proc/cmdline` is ours (`earlycon=msm_geni_serial,0x880000`, `pmos_boot_uuid=24d6dade-…`) with ABL's own
  `androidboot.*` appended, including **`androidboot.dtb_idx=-1347440721`** (`0xafafafaf`) — the "no dtbo was
  considered" marker, i.e. ABL never went down the overlay path.
- `dmesg | grep -c kexec` = 0.

**Persistence verified at 12:02**: a `sudo reboot` from mainline dropped the gadget for ~18 s and came back as
`7.2.10-sm6150` with uptime 0 min — ABL booted our image again, so this is the persistent path, not a one-shot.

Why it works: with **no valid dtbo**, `DTBImgCheckAndAppendDT()` takes the legacy path, `DeviceTreeAppended()` finds a
single valid FDT and accepts it **without any ID match and with no overlay applied**. Every earlier refusal was
`ApplyOverlay`/libufdt failing to apply the stock violet overlay to a mainline base (the same thing `fdtoverlay`
reported as `FDT_ERR_BADOVERLAY`) — so identity, PE header, AVB and `__symbols__` were never the problem, exactly as
the 10-13 bisection's correct half said. Source: `research-abl.md` §1a.

State to keep in mind:
- **`dtbo` is now erased. Do not flash `dtbo-vendor.img` back** unless you want to return to kexec — a valid dtbo
  re-arms the overlay path that refuses our DTB. Recovery images if ever needed: `dtbo-vendor.img` (8 MB dump,
  `d7b7ab1e`, entry 0 = 341,934 B violet overlay) and `~/violet-pmos/images-r9/boot-r10.img`.
- `boot` now holds mainline, so the old "kexec from r10" workflow is gone. Back to r10 = flash `boot-r10.img`.
- ABL passes the modem/panel cmdline extras (`msm_drm.dsi_display0=dsi_nt36672a_shenchao_vid_display:`), which is
  the same string r10 uses, so the panel keeps working.

Also found while rebuilding: `mk-bootimg.sh`'s `__symbols__` step never worked (`dtc -I dtb -O dtb -@` cannot invent
labels), so our DTB carried 0 symbols vs the vendor's 1 — recorded in `RULED-OUT.md`. Irrelevant on the legacy path.

**New tooling for the human-in-the-loop problem:** `/home/vipi/violet-mainline/cue.sh` + `make-cues.py` +
`need-hands.sh` play a *distinct* sound per situation (ok / fail / fastboot / power / net / ask) instead of one
generic chime; `need-hands.sh fastboot|power|net [sec]` cues, then polls for the transport and plays `ok` when it
lands. Use it whenever a flash, boot or cable action is needed — the user does not see notifications.

## 2026-10-25 11:45 — research phase finished (three notes), handover to Hermes, `docs/CHECKLIST.md` written

The Claude session that started this group ran out of tokens at 11:30 right after its three research agents handed
back, so nothing from them had reached the log. All three notes are complete and are the source for the new
[CHECKLIST.md](CHECKLIST.md):

- `~/.config/Claude/side-session-notes/local_0be438d6-…/research-abl.md` — read ABL source (CodeLinaro
  LA.UM.8.9.1.c25). The refusal is now explained as a *branch*: while a valid dtbo exists, ABL must apply the stock
  board overlay to our base DTB, and that overlay does not apply (`FDT_ERR_BADOVERLAY`, already measured). With no
  valid dtbo it uses the legacy single-appended-DTB path and accepts **without any ID match**. So
  `fastboot erase dtbo` is the cheap test (checklist N1), and the panel/identity/AVB routes stay closed.
- `research-audio.md` — `tas2781-i2c.c` never powers the boost in probe and `tasdevice_startup()` returns `-EINVAL`
  without `tas2563RCA1.bin`, so **prof51's "no USB" is not evidence about the amp**: `kexec-prof51.log` holds only
  `Cannot find device "enp0s20f0u4"` and the console file one failed ssh — the phone never enumerated at all.
  AFE-vs-amp is therefore still unseparated (checklist A1). Also found: our sound node has no `pinctrl-0` while
  talos-evk muxes `mi2s1_pins`; and the vendor blob `tas2563_uCDSP.bin` may parse as `tas2563_coef.bin`.
- `research-wifi.md` — the modem is TZ PAS (`pas-id 4`), i.e. `qcom,sm8150-mpss-pas` is the right node; probe will
  fail `-ENODATA` until `qcs615_rpmhpds` gains `[RPMHPD_MSS] = &mss`. Draft DT + rmtfs/tqftpserv route included.

No device action was taken in this entry. Next: checklist N1 (needs the user's OK — it touches `dtbo`), then A0/A1.

## 2026-10-25 11:22 — CLAUDE SESSION: SMMU-fix kernel tested once; new boot-time fault storm, patches 5-7 reverted

**Test `smmufix1`** (`ml-login-test.sh`, Image = 7.2.10 + MM1 keepalive + "fix SMMU fault dumps" v3 1-7): phone stayed
up the full 180 s. Autologin did NOT take (the boot greetd held seat0/tty7, so the second greetd never got a session),
so this was a greeter-only run, not a login test.

**New finding in that boot (`login-smmufix1-dmesg.txt`):** a continuous MDSS SMMU fault storm from **5.24 s**, right after
`[drm] Initialized msm`, before any session: `arm_smmu_context_fault: ~300 000 callbacks suppressed` every 5 s, all
`iova=0x00001000`, `cbfrsynra=0x800` (MDSS). None of yesterday's mainline dmesg captures show any SMMU fault, so this is
new in this kernel. The old random-IOVA (in-flight framebuffer) faults are down to a handful.
Suspect: patches 5-7 of the series (DPU DSPP/DSC/resource-reassignment changes; 7/8 = "only reassign resources when
the encoder is reprogrammed"). The pin-state backport (1-2) was re-read and looks correct.

**Now in the tree:** patches 6-8 of my split (= v3 5/8, 6/8, 7/8) **reverted**; kept v3 1-4 (pin serialisation,
refcount leak, kms_init unwind, release-after-vblank) + MM1 keepalive. Built OK (`build-smmufix-1to4.log`).

**Test harness:** `ml-login-test.sh <tag> [s]` now switches `/etc/conf.d/greetd` to `/etc/phrog/greetd-autologin.toml`
(`[initial_session] phosh-session` as `user`) on r10 *before* the kexec and restores it from
`/etc/conf.d/greetd.pre-autologin` right after mainline is up, then streams `dmesg -w` and checks liveness every 10 s.

**Blocked:** `to-r10.sh` (sysrq reboot from mainline) left the phone with **no USB at all** (watchdog off) - needs a Power
press. If it comes back on r10 with autologin config still active, `/etc/conf.d/greetd.pre-autologin` holds the original.

## 2026-10-25 11:15 — CLAUDE SESSION: log split into docs/, plus two results that were not logged

**Docs:** PLAN.md is now the design doc only. This log moved here (newest first; add entries at the top), and the current state is in
[STATUS.md](STATUS.md), dead ends in [RULED-OUT.md](RULED-OUT.md). Backup of the old file: `PLAN.md.bak-pre-split`.

**smmufix1 (preliminary, test was still running at 11:10):** Image #109 = MM1 keepalive + SMMU v3 1-7. `login-smmufix1-dmesg.txt`
shows SID 0x800 `fsr=0x402` context faults from **t=5.2 s, during boot, before any login**, at `callbacks suppressed` 140k-380k per 5 s,
IOVAs 0x1000, 0x2000 ... 0x1b9b000 (not the fbcon framebuffer range from prof47). No RCU stall, soft lockup or AMC -110 by t=109 s.
=> the SMMU v3 patches do not remove the MDSS faults, and the faulting fetch starts before userspace. One candidate is the DPU still
fetching from low IOVAs at probe (splash or handoff), which is worth checking next.

**prof51 (TAS2563 switch, 10:54):** the phone did not come back on USB within 3 min and no console was captured (`kexec-prof51.log`).

**Resolved:** ramoops is configured (no `record-size`, so there is no panic record), and the 10-13 "discriminator is the KERNEL" table is the invalid
`fastboot boot` reading. Notes were added in place in those entries.

## 2026-10-25 — audio: card, playback PCM and AFE port start all solved; the speaker amp was bound to the WRONG DRIVER (that is the PMIC hard reset)

**Bottom line: there is still no audible sound.** But four separate blockers were removed with
evidence, and the one that remains is now identified precisely instead of guessed at. Three of those
blockers each looked like "audio is broken" and were not.

### 1. The speaker amp was on the wrong I2C controller (FIXED — verified)

The vendor calls the amp's bus `qupv3_se4_i2c` at `0x88c000`, and I attached the amp there. Wrong:
`0x88c000` is QUPv3 **wrapper 0**. The pins the amp is actually wired to (**gpio20/gpio21**, with its
reset on **gpio22**) belong to **wrapper 1 / SE0 = `i2c@a80000`**, which `talos.dtsi` already describes
with exactly those pins and function `qup1` — vendor's `qup10` downstream is the same thing.

What the bus errors were telling us, which I initially misread:

| Attempt | Error | Meaning |
|---|---|---|
| amp on `i2c3` (`0x88c000`), default pins gpio18/19 | `-6` (ENXIO) | bus worked, **no device at 0x4c** on that bus |
| amp on `i2c3` but pins forced to gpio20/21 `qup1` | `-110` (ETIMEDOUT) | pins don't belong to this controller -> **bus unusable** |
| amp on `i2c4` (`0xa80000`) with its own pins | clean probe | correct |

`-6` = NAK (bus is fine). `-110` = no clocking at all (wrong pins/controller). I had those two
backwards at first and spent a cycle chasing power.

Second half of the same fix: `talos.dtsi` leaves **`qupv3_id_1` (geniqup@ac0000) and `gpi_dma1`
disabled**, so `i2c4` never probed and the card sat in
`deferred probe pending: snd-sm8250: Speaker Playback: codec dai not found`. Enabled both.

Evidence of a live amp now:
```
geni_i2c a80000.i2c: Bus frequency not specified, default to 100kHz.
tas2562 1-004c: Property ti,imon-slot-no is missing setting default slot
tas2562 1-004c: Property ti,vmon-slot-no is missing setting default slot
-i2c-1 / 1-004c present
```
Only missing-optional-property warnings — **zero register read failures**, versus a continuous `-110`
stream before.

### 2. A playback PCM now exists (FIXED — verified)

`/proc/asound/pcm` was `MultiMedia1 … capture 1` / `MultiMedia2 … capture 1` and nothing else, so
`aplay -l` was empty. Dynamic-debug trace on card rebind showed why:

```
ASoC: adding MultiMedia1 Capture widget
ASoC: adding MultiMedia2 Capture widget
ASoC: adding MultiMedia3 Playback widget      <-- only playback FE in this q6asm instance
```

Added an `mm3-dai-link` (`MSM_FRONTEND_DAI_MULTIMEDIA3`). Result: `00-02: MultiMedia3 (*) : playback 1`,
`pcmC0D2p`. MM1/MM2 are capture-only on this firmware and cannot be used for playback.

### 3. Mixer routing: the control name is backwards from what you'd guess (SOLVED)

Not `MultiMedia3 Mixer PRI_MI2S_RX` but **`PRI_MI2S_RX Audio Mixer MultiMedia3`** — i.e.
`<backend> Audio Mixer <frontend>`. `amixer sset` refuses that name ("Invalid command!"), so set it by
numid:
```
N=$(amixer -c 0 controls | grep "PRI_MI2S_RX Audio Mixer MultiMedia3" | grep -oE "numid=[0-9]+" | cut -d= -f2)
amixer -c 0 cset "numid=$N" 1
```

### 4. The AFE port would not start at all (FIXED — verified)

This is why `aplay` "succeeded" while producing silence: the failure is at **prepare**, after open.

```
qcom-q6afe aprsvc:service:4:4: no line is assigned
q6afe-dai: fail to prepare AFE port 10
ASoC error (-22): at snd_soc_dai_prepare() on PRI_MI2S
```

`q6afe_i2s_port_prepare()` builds a `sd_line_mask` from DT; with no mask it returns `-EINVAL`. Fix:

```dts
&q6afedai {
	dai@16 {
		reg = <PRIMARY_MI2S_RX>;
		qcom,sd-lines = <0>;
	};
};
```

After this the prepare error disappears entirely.

### 5. The remaining defect: starting the stream HARD-RESETS the PMIC

What the evidence proves, and what it rules out:

- PMIC on the next boot: `PMIC@SID0 Power-on reason: Triggered from Hard Reset` — a hardware reset.
- Booted with **`panic=0`** (kernel never reboots on panic) and the phone **still reset**. Therefore it
  is *not* a kernel panic.
- `WDT=off` disables the APSS watchdog (`wdt-disable.py` writes EN=0 at `0x17c10000`), so it is *not* a
  watchdog bite.
- **netconsole cannot capture it**: normal kmsg arrives fine (verified with a probe line), but a forced
  `sysrq-c` panic produced **no** panic text in the log at all — the phone just rebooted. netconsole is
  not a usable panic channel here, and `ramoops` has never been configured (`"memory size and the
  record/console size must be non-zero"`).
  *[note added 2026-10-25 11:15: ramoops IS configured in the DTS (`ramoops@a1600000`, console + pmsg, booted as `ramoops: using 0x800000@0xa1600000`); it has no `record-size`, so panics get no dmesg record.]*
- Amp `Amp Gain` = 0 (muted) still resets -> not the speaker output stage drawing current (the amp's
  boost still powers up regardless of gain).
- Removing the amp from the BE stopped the resets, **but** the FE then failed to open (`-EINVAL`,
  because a `no_pcm` BE PCM cannot be opened from userspace), so the AFE never actually started in that
  test. **AFE vs amp is therefore still not fully separated** — recorded honestly rather than claimed.

### 6. Root cause, and the fix now in flight

The amp was bound to **`ti,tas2562`**. Mainline has a **dedicated TAS2563 driver**:
`sound/soc/codecs/tas2781-i2c.c`, whose match table contains
`{ .compatible = "ti,tas2563", .data = &tasdevice_id[TAS2563] }`. TAS2563 is *not* register compatible
with TAS2562 — different boost, different PLL, plus a DSP — so the TAS2562 init sequence was
mis-programming it, which is a very plausible way to trip the PMIC the instant a stream starts.

Done: `compatible = "ti,tas2563"`, `reset-gpios = <&tlmm 22 GPIO_ACTIVE_HIGH>` (the driver calls
`devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_HIGH)`), and
`CONFIG_SND_SOC_TAS2781_I2C=m` + `COMLIB` + `COMLIB_I2C` + `FMWLIB`. All four modules built in **90 s**
with `make modules` (fixdep limits the rebuild to the new symbols — no 25-minute relink). Shipped to
`/lib/modules/7.2.10-sm6150`, `depmod` OK, DTB rebuilt with the new compatible.

Boot test (`prof51`) was in flight when this was written; the phone had not re-enumerated on USB yet.

### Current audio state in `violet-sm6150.dts`

- ADSP: `&rproc_adsp_mem` at `0x95300000 + 0x1e00000`, `firmware-name = "qcom/qcs615/adsp.mdt"`.
- Legacy APR: `apr_audio_svc`/`apr_apps2` -> q6core/q6afe/q6asm/q6adm; card `qcom,sm8250-sndcard`.
- Links: `MultiMedia1`, `MultiMedia2`, `MultiMedia3`, `Speaker Playback` (cpu `q6afedai PRIMARY_MI2S_RX`,
  codec `&tas2563`), plus a **diagnostic-only** `Debug Playback` (`SECONDARY_MI2S_RX`, codec-less) used
  for the AFE-vs-amp bisect — remove it once sound works.
- `&q6afedai { dai@16 { qcom,sd-lines = <0>; } }` — required or the port never prepares.
- `&qupv3_id_1`, `&gpi_dma1`, `&i2c4` all enabled; amp at `0x4c` as `ti,tas2563` with `reset-gpios` gpio22.
- No WCD9375 links in the card (a failing codec takes the whole card down with `-110`). SoundWire stays
  parked: WCD9375 enumerates but goes `UNATTACHED` after `MASTER_CLASH_DET`, and its reset lives on
  LPASS LPI gpio24, which mainline cannot clock for this SoC.

### Tooling added today

- `attention.sh` + `attention.wav` — audible chime through the **laptop** speakers when the phone has
  been unreachable for ~2 min, per the user's request (they often miss desktop notifications).
- `netconsole-play.sh` + a `socat` listener on UDP 6666 -> `netconsole2.log`.

### Lessons to keep (each one cost real time)

1. Attach a peripheral to the I2C controller its **pins** belong to, not to an address you recognise.
   `-6` means the bus works and the device isn't there; `-110` means the bus isn't usable at all.
2. **Grep the codec directory for the exact part number before binding a generic driver.** `tas2563` ->
   `tas2781-i2c.c` was one grep away and was missed for hours.
3. `ssh` host with `%iface` must **not** be bracketed — brackets are for `scp` only.
4. `ssh -n` *and* a trailing `</dev/null` both destroy a heredoc; use `ssh -T`. A script that "runs"
   silently doing nothing is this bug.
5. `panic=0` is the cheap test that separates a hardware reset from a kernel panic.
6. netconsole on this gadget carries normal kmsg but not panic text.
7. `amixer sset` chokes on the generated routing names; use `numid`.
8. `make modules` after adding a `=m` symbol is ~90 s, not a full relink.

### Note on this file's ordering

An earlier audio write-up was appended to the **end** of this file (against the "append newest first"
rule above) — it is the long `ADSP/APR/macros/SoundWire` block at the bottom. It is still accurate on
ADSP/APR/SoundWire, but its speaker-amp conclusions are **superseded by this entry**.

## 2026-10-25 10:50 — NOTE FROM THE CLAUDE SESSION: second lead, the serial console (cmdline-only test)

**Finding:** mainline registers the GENI UART as a kernel console (`880000.serial: ttyMSM0 at MMIO 0x880000`,
`printk: legacy console [ttyMSM0] enabled`, seen in kexec-prof31/32 and crash-ramoops-2), and `kexec-test.sh`
boots with `console=ttyMSM0,115200n8 ignore_loglevel loglevel=8`. So **every** printk - debug included - is written
synchronously to a 115200-baud UART (~9 ms per 100-byte line), busy-waiting with interrupts off. Bursts (spmi
`cleanup_irq`, DPU/RPMh warnings, DSIDBG, drm debug, printk heartbeats) can keep a CPU IRQ-off long enough to miss
IPIs/NMIs -> `kick_all_cpus_sync` softlockups, RCU "CPU not responding", and a log that goes silent because printk
itself is what is stuck. Same failure class as an X1E report where `Error sending AMC RPMH requests (-110)` turned
out to be a CPU stuck on a serial console/getty (fixed by masking it).

**How to test (no rebuild):** `kexec-test.sh` now honours `KCONSOLE`; the default is unchanged.
    KCONSOLE="loglevel=4" ./ml-boot.sh <tag>        # no UART console; pstore/ramoops + netconsole still work
Recommended order: (1) KCONSOLE="loglevel=4" with the MM1-keepalive Image -> log in; if stable, (2) re-add the UART
console to see which of the two was needed. Also check that no getty runs on ttyMSM0 (`ps | grep getty`).
Backup of the old script: `kexec-test.sh.bak-console`.

## 2026-10-25 10:45 — CLAUDE SESSION: the post-login freeze is the upstream "drm/msm: fix SMMU fault dumps" bug

**Evidence (Hermes's prof47 netconsole, `netconsole2.log`):** at t=55 s, right after the session starts:
`arm_smmu_context_fault: 483976 callbacks suppressed`, `arm-smmu 15000000.iommu: Unhandled context fault:
fsr=0x402, iova=0x00740b00 ... cbfrsynra=0x800, cb=6` - SID **0x800 = MDSS** (`talos.dtsi` mdss `iommus =
<&apps_smmu 0x800 0x0>`). All faulting IOVAs lie in 0x14ef00..0x94b000, i.e. inside the fbcon framebuffer
(IOVA 0x100000, 10186752 bytes = 1080x2340x4). The display keeps fetching a framebuffer whose IOMMU mapping is
already gone; ~half a million fault IRQs pin the CPUs -> missed IPIs -> kick_all_cpus_sync/RCU stalls -> wedge.

**Upstream diagnosis + fix:** Dmitry Baryshkov, "[PATCH v3 0/8] drm/msm: fix SMMU fault dumps"
(msgid 20260912-fd-kms-fix-smmu-v3-0-a7ddc6fe2032@oss.qualcomm.com, not in 7.2.10): since commit 111fdd2198e6
("drm/msm: drm_gpuvm conversion") unpinning detaches the VMA, and msm released the old framebuffer at atomic cleanup
while the in-flight frame (video mode only waits for CTL_FLUSH) was still being fetched -> `fsr=0x402` faults.
Patch 4 defers releasing retired framebuffers to a vblank work; patches 1-2 fix pin refcount races (NULL base
address); 3, 5-7 are related DPU/KMS cleanups. Same fault signature, same mechanism.

**Applied to the tree:** patches 1-7 of v3 (8 = CI list only), all apply cleanly on 7.2.10. Mails in the Claude
scratchpad `smmu-v3/split/`. Known review note: an AI reviewer flagged a theoretical use-after-free in patch 4 when a
CRTC disable races a commit (not our failure path). Rebuild started (`build-smmufix.log`); this Image ALSO keeps the
MM1-keepalive change. Test = the usual r10 -> kexec, log in, use the session; expected: no arm-smmu faults, no freeze.
**Build done (10:44):** `arch/arm64/boot/Image` now = 7.2.10 + MM1 keepalive + "drm/msm: fix SMMU fault dumps" v3 1-7.
Ready for r10 -> kexec + login test. Look for: zero `arm-smmu ... Unhandled context fault` from SID 0x800, session alive.

## 2026-10-25 10:25 — NOTE FROM THE CLAUDE SESSION (read before the next kexec): kernel change in the shared tree

**Changed:** `drivers/interconnect/qcom/qcs615.c`, `bcm_mm1` now has `.keepalive = true`. A rebuild of `Image`
was started at 10:20 (`build-mm1keepalive.log`); once it finishes, **every kexec of the tree's Image includes this**.

**Why (research, not trial-and-error):** upstream fixed the same failure on SDM845 with
"interconnect: qcom: sdm845: Enable keepalive for the MM1 BCM" (Georgi Djakov, 2020): with the
multimedia BCM allowed to drop to 0, the RPMh sequencer gets stuck and client votes fail with
`Error sending AMC RPMH requests (-110)` from `icc_set_bw` — exactly the prof13 trace
(`rpmh.c:386 rpmh_write_batch` WARN + ETIMEDOUT from `qcom_icc_bcm_voter_commit`). On QCS615, `bcm_mm1`
carries **`qxm_mdp0`** (the display's DDR path) and had no keepalive (MM0, SH0, SN0, MC0, CN0, QUP0 do).
Expected effect if right: no more RPMh AMC timeouts and no `dpu_encoder_frame_done_timeout` -> no SoC wedge
~30-40 s after login. Test = log in and use the session (the greeter alone never froze).

**Coordination:** the Claude session is NOT driving the phone while Hermes is running prof* tests (it saw
prof45 at 10:20). Revert = drop the `.keepalive = true` line in `bcm_mm1`.
**Build done:** `arch/arm64/boot/Image` (36313096 bytes, 10:23) includes the MM1 keepalive change; DTB unchanged
(09:54). Ready for the next r10 -> kexec boot + login test.

## 2026-10-26 (later) — AUDIO: ADSP + APR + macros + SoundWire all up; codec attach is the wall

### What now works (each verified on device, prof21–prof36)

- **ADSP boots** (`remote processor adsp is now up`), only with
  `&rproc_adsp_mem { reg = <0x0 0x95300000 0x0 0x1e00000>; };` and
  `&rproc_cdsp_mem { reg = <0x0 0x93b00000 0x0 0x1800000>; };` (vendor TZ windows).
  Upstream's `0x95900000` gave `qcom_scm_pas_mem_setup()` **-22**.
  Firmware: `qcom/qcs615/adsp.mdt` + 29 `adsp.b*` (13.4 MB) from `/run/msm-firmware-loader`.
- **APR (legacy) stack binds**: glink channels `apr_audio_svc`, `apr_apps2`, `IPCRTR`;
  services `4:3` q6core, `4:4` q6afe, `4:7` q6asm, `4:8` q6adm; dais `q6afe-dai`,
  `q6asm-dai`, `q6routing`. **Not** AudioReach — the 2019 firmware has no `adsp_apps`.
- **VA/TX/RX macros probe**, WCD9375 powers up and **enumerates on both SoundWire links**
  (`sdw:2:0:0217:010a:00:4`, `sdw:3:0:0217:010a:00:3`), codec driver binds.
- **Clocks confirmed running** (clk_summary): `LPASS_CLK_ID_{RX,TX}_CORE_MCLK` enabled at
  19.2 MHz through q6afecc, and both masters hold `lpass-{rx,tx}-mclk` at 9.6 MHz.
  So the bus *is* clocked — the clock-vote theory is dead.

### The wall

After the binds the slaves go **UNATTACHED** and the card fails:

    qcom_swrm_irq_handler: SWR bus clsh detected        <- MASTER_CLASH_DET, both masters
    wcd937x_codec: bound sdw:...:4 / sdw:...:3
    wcd9370-codec sdw:3:...:3: Initialization not complete
    wcd937x_codec: ASoC error (-110): at snd_soc_component_probe()
    snd-sm8250 soc@0:sound: ASoC: failed to instantiate card -110

`/proc/asound/cards` -> `--- no soundcards ---`. **No tone is possible yet.**

### Ruled out with evidence (do not re-test)

| Theory | Test | Result |
|---|---|---|
| Runtime-PM autosuspend strands slaves (ROCKNIX wsa881x fix) | udev rule pinning `power/control=on` on **bind** | `ctl=on rt=active`, still UNATTACHED |
| Wrong SWR IP version | swapped `qcom,soundwire-v1.5.1` -> `v1.3.0` | identical, clash + detach |
| Port arrays too short | qcom parser: `nports = din + dout`, HW reports 6 dout + 1 din = 7 | now the Android kona/wcd937x 7-entry tables, no mismatch warnings |
| Wrong port config at all | stripping `qcom,ports-*` | driver `-EINVAL` -> properties are mandatory |
| Codec unpowered | `ldo10 state=enabled use=2`, `ldo15 enabled use=1` after detach | rails hold |
| Probe ordering: `qcom_swrm_init()` after `sdw_bus_master_add()` restarts the live link under the slaves | **patched** `drivers/soundwire/qcom.c`: init before add, `bus_master_added` guard in the IRQ handler, explicit `get_device_status`+`enumerate`+`handle_slave_status` after add | **identical behaviour** -> ordering was not it, but the patch is harmless and stays |

### New dead end (important)

The codec's reset is **LPASS LPI GPIO 24**, not TLMM. `pinctrl-sdm670-lpass-lpi`
(sdm670's LPI block is byte-identical: base `0x62b40000`, 32 pins, `lpi_cdc_rst` on gpio24)
binds there but its probe **wedges a CPU** and the kernel panics ~44 s later in
`load_module` -> `kick_all_cpus_sync` (`SMP: failed to stop secondary CPUs 0,2,7`).
With the node removed the kernel boots normally. So the LPI block needs its audio clock
before any register access; the AFE clock-vote command this firmware rejects
(`Unknown cmd 0x100f4`) is exactly the thing that would have provided it.
The codec therefore **still cannot be reset under our control** — current `reset-gpios`
points at a harmless TLMM pin only because the property is mandatory.

### Next steps, in order of value

1. **Get the LPI block clocked** so gpio 24 can actually reset the codec
   (candidates: `lpass_core_hw_vote` / `qcom,audio-ref-clk` = `AUDIO_LPASS_CORE_HW_VOTE`
   from the vendor DT — a *hardware* vote, not the AFE command that fails; or a
   fixed-clock stand-in purely to unblock register access).
2. Compare against the **vendor stack while it is running** (r10 has working audio):
   dump SWR frame/port registers from the downstream kernel and diff with ours.
3. If SWR stays hostile: **bypass it** — violet's speaker is a **TAS2563 on I2S**
   (mainline `sound/soc/codecs/tas2562.c`), which needs no SoundWire handshake.
4. `audio-test.sh` + `tone440.wav` are ready; the moment a card appears,
   `./audio-test.sh 440` plays it.

## 2026-10-26 09:40 IST — WHY WIFI IS DEAD: it is gated behind the MODEM, not behind the wifi node

Chased to the root this session. Everything below is verified on hardware or read out of the source.

### What was fixed and works now (prof18/prof19)

1. **The chip's power rails are now real regulators.** mainline ships `qcom,pm6150-rpmh-regulators` and
   `qcom,pm6150l-rpmh-regulators` but no platform had described the rails, so ath10k's `regulator_bulk_get()`
   fell back to dummy regulators and **never enabled anything**. Added RPMh nodes under `&apps_rsc`
   (`regulators-0` = pm6150 pmic-id "a", `regulators-1` = pm6150l pmic-id "c") for the four rails the vendor
   icnss node names:
   | supply | rail | limits (vendor) |
   |---|---|---|
   | vdd-0.8-cx-mx | pm6150 ldo9 | 400000-728000 (icnss raises to 640 mV; min raised to 640000 here because mainline never reads `qcom,vdd-0.8-cx-mx-config`) |
   | vdd-1.8-xo | pm6150l ldo1 | 1800000-1900000 |
   | vdd-1.3-rfa | pm6150l ldo2 | 1304000 fixed |
   | vdd-3.3-ch0 | pm6150l ldo10 | 3200000-3312000 |
   They are `regulator-always-on`: ath10k only enables the rails in `hif_power_up()`, which runs *after* the QMI
   handshake, so the chip must be powered from boot. Verified in prof19 - `ldo9/regulators-0`,
   `ldo1/regulators-1`, `ldo2/regulators-1`, `ldo10/regulators-1` all report `state=enabled` at boot and
   `vdd-3.3-ch1` is the only remaining dummy (this board has no fifth rail).
2. DT is otherwise correct: MSA region accepted (1024 KiB), 12 CE interrupts (4-cell GIC), SID 0x1640,
   `ath10k_snoc` binds and **probe returns 0**.

### The actual blocker

ath10k's probe deliberately stops there: it registers a QMI client for the WLFW service and waits for
`WLFW_FW_READY_IND` before calling `ath10k_core_register()` - hence zero errors and zero netdev. The WLFW service
exists only once the WLAN coprocessor is **running**, and on this SoC generation the WLAN coprocessor is booted by
the **modem DSP**:

> "The wlanmdsp.mbn is downloaded by the onboard modem DSP via the tqftpserv request (which is served from the
> board-specific folder qcom/qcm2210). The firmware-N.bin file is loaded by the WiFi driver itself."
> - ath10k mailing list, Dec 2023 (Dmitry Baryshkov, RB1/RB2 platforms)

`ath10k_snoc_probe()` even calls `ath10k_modem_init()` -> `qcom_register_ssr_notifier("mpss", ...)`: the driver is
built around the modem being present. And our DT has **no modem at all**:

- `talos.dtsi` (QCS615) contains **no MPSS/remoteproc_mpss node** and **no smp2p entries** whatsoever. The qcs615
  remoteproc series upstream enabled only ADSP and CDSP - on the LKML thread Konrad noted explicitly that MPSS is
  not part of QCS615 ("It was a part of the SM6150 design"). violet is SM6150, so the modem exists in hardware but
  has no mainline description.
- No QRTR transport exists either (`/sys/bus/qrtr/devices` empty), which is consistent: the modem's glink edge is
  what carries the `IPCRTR` channel that `qrtr-smd` binds, and there is no modem node to hang it off.
- Downstream is no better: r10's dmesg shows `icnss: Platform driver probed successfully` and a qcacld
  `wlan_hdd_state wlan major(496) initialized`, but **no wlan0** - and our `device-xiaomi-violet` package ships
  no wifi firmware at all. **Wifi has never worked on violet in postmarketOS on any kernel.**

Firmware itself is available on the device (stock `modem` partition): `bdwlan.104..bdwlan.10f`, `bdwlan.b04/.b07`
(per-board board-data blobs), `wlanmdsp.mbn`, plus `adspr.jsn`/`adsps.jsn` PD descriptors.

### What "make wifi work" therefore requires

In order, and none of it exists upstream for this platform:
1. **MPSS (modem) remoteproc for sm6150** - PAS node (mba/modem firmware, watchdog IRQ, smp2p mss in/out,
   glink edge with `IPCRTR` + `DS` + `IPCR` channels, mhi/ipa plumbing). This is modem bring-up, a project in itself.
2. **tqftpserv** running on the device, serving `qcom/<soc>/wlanmdsp.mbn` + the `bdwlan.*` blobs to the modem over QMI.
3. Then ath10k's existing, already-working QMI path should finally see `WLFW_FW_READY` and register a netdev -
   `ath10k/WCN3990/hw1.0/{firmware-5.bin,board-2.bin}` are already installed.

This also explains why nothing I did to the wifi node could ever have produced `wlan0`: the node, the MSA, the IRQs
and now the rails are all necessary but the *copressor is never started*, and starting it is the modem's job.

### Consequence for planning

Wifi is not a wifi problem; it is a **modem bring-up** problem. Audio, by contrast, sits on a path upstream already
supports for this SoC (qcs615 ADSP PAS exists, the node is in talos.dtsi at status="disabled").

## 2026-10-26 07:40 IST — WiFi: ath10k side fully prepared, but blocked on WCSS bring-up (not a DT typo)

Work done this session, all verified on device:

1. **Module tree installed.** The device had `/lib/modules/4.14.356-openela-rc1-perf` only, i.e. no module tree for our
   kernel at all, so every `=m` driver was unloadable. Built a module tree and installed **747 modules** to
   `/lib/modules/7.2.10-sm6150`, vermagic verified `7.2.10-sm6150 SMP preempt mod_unload aarch64`.
   Also flipped `SOUND`, `SND`, `SND_SOC`, `CFG80211`, `MAC80211`, `RFKILL`, `ATH10K`, `SOUNDWIRE_QCOM`,
   `SND_SOC_WCD937X_SDW`, `SND_SOC_QDSP6` to built-in (a `select` fight keeps `QCOM_RPROC_COMMON`/`ATH10K_SNOC`
   modular, which is fine now that modules load).
2. **WiFi DT node written** (`&soc { wifi@18800000 { ... } }`) from vendor `icnss@18800000`: SID `0x1640`,
   CE IRQs 414-425, `qcom,msa-fixed-perm`, `memory-region`. Firmware installed:
   `/lib/firmware/ath10k/WCN3990/hw1.0/{firmware-5.bin,board-2.bin}`.
3. **Two real bugs fixed:**
   - GIC on this SoC takes **4 cells** per interrupt (compare `remoteproc_adsp`: `GIC_SPI 162 IRQ_TYPE_EDGE_RISING 0`).
     With 3 cells the parser mis-splits, only 1 IRQ registers -> `-ENXIO: IRQ index 1 not found`.
   - The board DTS already had `wlan_msa_mem@93300000` (unlabelled, **2 MB**), which overlapped `pil-video@93400000`,
     so the kernel **dropped the region** and ath10k got no MSA. Now labelled and shrunk to 1 MB
     (`0x93300000..0x933fffff`, matches vendor `qcom,wlan-msa-memory = <0x100000>`), phandle verified.
4. **Result:** reserved mem accepted (`nomap non-reusable wlan_msa_mem@93300000`), device binds, probe **returns
   success** (it ends at `ath10k_qmi_init()`/`ath10k_modem_init()`), regulators only warn "using dummy regulator"
   (pm6150/pm6150l LDOs are not modelled in mainline). But **no netdev**.

### Why there is still no netdev

`ath10k_snoc` probe deliberately does **not** bring the chip up: it registers a QMI client and waits for the WCSS
firmware to announce itself (`WLFW_FW_READY_IND`) before it calls `ath10k_core_register()`. Hence the completely
silent behaviour - no error, no netdev.

Checked on device: `/sys/bus/qrtr/devices` is **empty**, `/sys/class/remoteproc/` is empty (no ADSP/CDSP/WCSS
remoteproc registered), so the WLFW service can never arrive. On sc7180 the wifi DT node alone is enough because
that SoC's WCSS plumbing is upstream; here it is not:

- `drivers/remoteproc/qcom_q6v5_wcss.c` matches only `qcom,ipq8074-wcss-pil` and `qcom,qcs404-wcss-pil` - **no
  sm6150/qcs615 WCSS PAS**, so there is no WCSS remoteproc node to anchor a glink edge.
- `kodiak.dtsi` shows the modern shape: its wifi node has `qcom,rproc = <&remoteproc_wpss>`. talos has no
  equivalent remoteproc.
- The vendor icnss does this in-kernel via `qcom,smp2p_map_wlan_1_in` + SCM; none of that exists in mainline for
  this SoC.

**So WiFi on violet is blocked on WCSS remoteproc bring-up (driver support for the sm6150 WCSS + DT), not on the
ath10k node.** Everything on the ath10k side is now in place so that when WCSS comes up, wifi should appear.

### Audio: also a driver gap, not a DT job

No audio DT exists at all (no swr0/1/2, no codec, no card) **and** mainline's Bolero drivers do not list sm6150:
`lpass-rx-macro.c` matches sc7280/sm6115, `lpass-tx-macro.c` sc7280, `lpass-wsa-macro.c` sm8250/sm8450.
Hardware topology from the vendor tree (`~/violet-pmos/kernel`): `rx_macro@62ee0000` (swr1, WCD9375),
`tx_macro@62ec0000` (swr2), `wsa_macro@62f00000` (swr0); downstream card `qcom,sm6150-asoc-snd`; mainline's
equivalent binding is **`qcom,qcs615-sndcard`** on the AudioReach path, exactly as `talos-evk.dts` uses it
(`q6apm` + `q6apmbedai` DAIs). ADSP firmware exists on-device as split images (`adsp.b00/.b01...`, `adsp.mdt`,
`adsp.mjs/.jsn` in the stock `modem` partition) which msm-firmware-loader can assemble.

**Next concrete steps for audio** (in this order): add `qcom,sm6150-lpass-{rx,tx}-macro` compatibles to the macro
drivers (data identical to the existing sm8250 entry - same `LPASS_MACRO_FLAG_HAS_NPL_CLOCK`), add the soc-level
`rx_macro`/`tx_macro`/`wsa_macro` nodes + `swr0/1/2` masters, enable `remoteproc_adsp` with
`firmware-name = "qcom/qcs615/adsp.mbn"`, then add the `qcom,qcs615-sndcard` node with `q6apmbedai` DAIs and the
`wcd937x` SoundWire codec on swr1.

## 2026-10-26 06:40 IST — STATUS SNAPSHOT: what actually works on mainline right now

Written at the user's request, so there is one honest place to read the current feature state.

### Works (verified on the device, mainline 7.2.10, kexec'd from r10 `4.14.356-openela-rc1-perf`)

| feature | evidence |
|---|---|
| boot via kexec from r10 | every prof* run; kernel reports `7.2.10-sm6150` |
| display / panel | NT36672A "shenchao" 1080x2340 lights up, renders; user confirmed the repaired panel shows a working picture |
| touchscreen | novatek at i2c **0x01** (0x62 is the HW command window), 944 real events captured, binds ~5.06 s after the delayed-work change |
| GPU acceleration | Adreno 612 via freedreno (`GL_RENDERER FD612`, Mesa 26.2.4), devfreq OPPs 435/500/650/745/845 MHz, `&gcc { power-domains = <&rpmhpd RPMHPD_CX>; }` |
| backlight | WLED works, and `qcom,num-strings = <2>` removed the ~1150 IRQ/s OVP storm |
| eMMC | 8-bit, `non-removable`, no CQE, HS200, 58.2 GiB, 21 partitions; 9.3 GB fsync'd writes with load 5.5 without a single mmc error |
| USB networking | NCM gadget, ssh over IPv6 link-local, netconsole to the laptop |
| crash evidence pipeline | netconsole + `harvest4.sh` (2 s samples, top-3 IRQ movers by name, printk-liveness probe) + pstore after a *warm* reset |
| PMIC interrupt storm | masked at the PMIC in `spmi-pmic-arb.c cleanup_irq()` (16,677 suppressed reports -> one line) |

### Known broken

| issue | state |
|---|---|
| **graphical session hard-locks the SoC ~30-40 s after login** | parked by user request. Storage, GPU runtime-PM, CPUs 5-7, PMIC storm and the WLED storm all eliminated. Latest trace: display frame-done IRQ stops being delivered (10 x `dpu frame done timeout`), one boot showed an `rpmh_write_batch` ETIMEDOUT from `icc_set_bw` first |
| wifi | nodes + firmware + config prepared this session, not yet tested |
| audio | **no DT at all** (no swr0/1/2, no codec, no sound card) AND mainline's Bolero macro drivers do not list sm6150: `lpass-rx-macro.c` matches sc7280/sm6115, `lpass-tx-macro.c` matches sc7280, `lpass-wsa-macro.c` matches sc8250/sm8450. Needs driver compatibles added, not just DT. Hardware topology from the vendor tree: `rx_macro@62ee0000` (swr1, RX/WCD9375), `tx_macro@62ec0000` (swr2), `wsa_macro@62f00000` (swr0), card compatible downstream `qcom,sm6150-asoc-snd`, mainline equivalent `qcom,qcs615-sndcard` (as used by `talos-evk.dts`) |
| camera / modem / sensors | untouched |

### The module realisation (important)

`/lib/modules` on the device contains **only** `4.14.356-openela-rc1-perf` (r10's tree). Our kernel has *no* module tree at all, so every driver we have ever used on mainline was built in. Anything left as `=m` (`ATH10K_SNOC`, most of `SND_SOC_*`) can never load until either the config is changed to `=y` or a matching module tree is installed with `modules_install`. That is why wifi was never going to work regardless of DT.

## 2026-10-26 00:50 IST — prof14 (HS200 at proper clock): still froze, and the display frame-done IRQ simply stops

**prof14 setup**: `bus-width=<8>`, `non-removable`, no `supports-cqe`, **no** `max-frequency` (my cap reverted),
`qcom,num-strings=<2>`. eMMC enumerated `HS200 MMC card`, 58.2 GiB, all 21 partitions. Healthy at the greeter
for 785 s. `wled_ovp_irq` total = 0 the whole time (storm fix holds).

**Death**: login at t=800 (`phoc` 3640 -> 17235), load 3.5. Heartbeats (netconsole printk probe) continue
normally to t=835.9, then:

```
[837.5 .. 838.5] [drm:dpu_encoder_frame_done_timeout:2730] [dpu error] enc35 frame done timeout   x10 (~104 ms apart)
[838.5]          silence; SoC resets (no panic, no pstore)
```

So the mp/DSI **frame-done interrupt stops arriving entirely** ~37 s after login, the 100 ms watchdog fires
ten times, and the machine is gone within a second of the first timeout.

**Notable: this is a different first-victim than prof13** (there: mmc command timeout at ~155 s, then RPMh
ETIMEDOUT, then RCU stall). Every boot the system wedges and a different subsystem notices first. That is
consistent with one shared resource dying, not with N independent bugs.

**Checked and clean** (static): `catalog/dpu_5_3_sm6150.h` exists and sm6150 has a proper DPU 5.3 catalogue -
`intf_1` (DSI 0) has `intr_underrun = TOP0_INTR:26`, `intr_vsync = TOP0_INTR:27`, tear rd_ptr on
`MDP_INTF1_TEAR_INTR:2`. Not the swapped-index bug seen on other SoCs. Our `mdss@ae00000` has `interconnects`
(mdp0-mem), `power-domains = <&dispcc MDSS_CORE_GDSC>`, `iommus`, clocks - all present.

**Hypotheses still standing, in order**
1. **ICC/RPMh pressure on the shared apps_rsc BCM voter.** prof13 had a literal `WARN_ON` + ETIMEDOUT in
   `rpmh_write_batch` from `icc_set_bw`; the DPU votes bandwidth on commits and cpufreq votes per-OPP, both
   through `apps_bcm_voter` with only 2 ACTIVE TCS. The vendor avoids this by giving display its own
   `disp_rsc` mailbox (`base-sm6150.dtsi`: `mailbox@af20000`, GIC SPI 129, `drv-id 0`, own `disp_bcm_voter`).
   mainline's DPU has no such separation. **This is the strongest remaining lead.**
2. MDSS power collapse / GDSC off under a commit, making DPU register access (and the interrupt) dead.
3. The first frame-done timeout calls `msm_disp_snapshot_state()`, which dumps registers from possibly-dead
   hardware - that may be what turns a stalled display into a total bus hang.

**Next experiment (needs a ~25 min relink)**: make `dpu_encoder_frame_done_timeout()` skip
`msm_disp_snapshot_state()`, so a display stall no longer escalates to a machine hang. If the system then
survives with a frozen screen, there is time to read the DPU/DSI/ICC state over SSH and identify exactly which
block stopped, instead of losing the machine in under a second.

## 2026-10-26 00:25 IST — prof13 (WLED fixed): still froze, and this time it produced a real trace. My 52 MHz cap was a mistake.

**prof13 result**: `wled_ovp_irq` stayed at **0** through login (t=116, `phoc` 3655 -> 7475) and up to death at
up≈155 s. So the backlight storm is genuinely fixed, but **the freeze persists** — that storm was a real bug, not
*the* bug.

**What the trace shows** (netconsole, in order):

```
[155.x]  mmc0 command timeout -> sdhci + sdhci_msm register dumps (started ~10 s earlier)
[165.9]  WARNING: drivers/soc/qcom/rpmh.c:386 at rpmh_write_batch+0x1f8, CPU#6: sugov:6/96
[166.2]  Call trace: rpmh_write_batch -> qcom_icc_bcm_voter_commit -> qcom_icc_set -> icc_set_bw
                    -> _set_opp -> dev_pm_opp_set_opp -> qcom_cpufreq_hw_target_index
                    -> __cpufreq_driver_target -> sugov_work
[166.2]  Error sending AMC RPMH requests (-110)      <- drivers/interconnect/qcom/bcm-voter.c:318
[176.1]  rcu: detected stalls on CPUs/tasks: 4-...0 (1 GPs behind); rcu_preempt kthread starved
[186.4]  [drm:dpu_encoder_frame_done_timeout] [dpu error] enc35 frame done timeout
```

So the ordering is **mmc first (~155 s), RPMh timeout second (166 s), RCU stall third (176 s), display fourth**.
`rpmh.c:386` is the `WARN_ON(1)` in the ACTIVE-state wait: the message was accepted (no `-EBUSY`, so a TCS was
free) but the AMC completion never arrived inside `RPMH_TIMEOUT_MS` = 1 s.

**Checked and NOT the cause**: apps RSC `qcom,tcs-config` is `ACTIVE_TCS 2 / SLEEP_TCS 3 / WAKE_TCS 3 /
CONTROL_TCS 1` in our `talos.dtsi`, and the vendor `base-sm6150.dtsi` specifies the **same** numbers. Do not
"fix" the RPMh timeout by adding TCS entries — the firmware owns that allocation. (Side note from the vendor
DT: sm6150 also has a separate `disp_rsc` mailbox at 0xaf20000, GIC SPI 129, used for display bandwidth votes;
mainline's DPU doesn't use it.)

**My own regression, now reverted.** `max-frequency = <52000000>` was wrong: capping the clock does not stop the
core selecting HS200 mode (it is a host capability, not a DT property), so the controller ran **HS200 timing at
52 MHz**, a quarter of the required clock — out of spec, and exactly the kind of thing that produces command
timeouts like the one at t=155. The timing correlation is hard to ignore: deaths before the cap were 321-345 s;
immediately after adding it they were **107 s, 77 s, 155 s**. Removed the cap, kept
`bus-width=<8>`, `non-removable`, `/delete-property/ supports-cqe`.

**prof14 DT state** (verified in the compiled blob): `bus-width = <8>`, `non-removable`, no `max-frequency`, no
`supports-cqe`, `qcom,num-strings = <2>`.

## 2026-10-26 00:15 IST — ROOT CAUSE FOUND AND FIXED: backlight WLED OVP interrupt storm (~1150/s whenever the panel is lit)

**Finding.** mainline's `qcom-wled` WLED5 defaults are `num_strings = 4` with `enabled_strings = {0,1,2,3}`
(`wled5_config_defaults` in `drivers/video/backlight/qcom-wled.c`). violet's PM6150L WLED does not have four
populated strings, and the driver was never told otherwise, so the boost converter ran into an
enabled-but-open string and tripped OVP in a retry loop for the entire time the panel was lit.

Measured with the corrected per-CPU parser (`harvest4`), and the onset is unambiguous:

| t (s) | state | wled_ovp_irq per 2 s |
|---|---|---|
| 1211-1215 | `dpms=Off`, greeter | 0 |
| **1218** | **`dpms` flips Off -> On** (still greeter, `phoc=3662`) | **+802** |
| 1220-1280 | panel lit, then logged in | **+2230..+2330 sustained** |

That is **~1,150 interrupts/second**, each handler doing two `regmap_read()` calls over SPMI, i.e. **~2,300
SPMI transactions/second** on the arbiter that also delivers every other PMIC interrupt, with IRQs disabled
inside the handler. The log ends mid-storm. This is the mechanism that matches the whole failure signature:
a CPU pinned in hardirq/SPMI context -> stops acking IPIs -> `kick_all_cpus_sync()` hangs -> softlockup ->
hard reset with empty pstore. It also explains why **login always triggered it** (the display is on and busy)
and why GPU rendering died sooner than pixman (more frames -> more display activity once the bus is saturated).

**Fix.** In `&pm6150l_wled`:

```dts
qcom,num-strings = <2>;
```

**Verified fixed, without needing a login**: after the DT rebuild, panel lit, `dpms=On`, brightness 2048,
three 10-second windows measured `ovp=0 (0/s)`. Storm gone.

**Method note worth keeping**: because the storm's trigger is "panel lit" and not "logged in", it can be
measured entirely from the SSH side at the greeter. Any future state-dependent storm should be probed this
way instead of costing the user a login per iteration.

**Still open**: whether killing the storm also stops the freezes. prof13 (num-strings=2) is instrumented with
`harvest4` (top-3 IRQ movers by name, printk liveness) + netconsole, awaiting a login.

## 2026-10-26 00:05 IST — Storage exonerated by load test; two of my own analysis errors corrected

**Storage is NOT the freezer.** prof12: at the greeter with nobody logged in, 31 passes of
`dd bs=1M count=300 conv=fsync` + `sync` (~9.3 GB written to the eMMC-backed loop image, load average
5.5) ran for four minutes and the phone was completely healthy at up=406 s and beyond. The eMMC
`bus-width`/`non-removable` fix is still a genuine bug fix and stays, but the mmc timeouts seen in prof6
were collateral damage, not the trigger. **Do not reopen the storage theory without a new signal.**

**Correction 1 — the "98 million backlight interrupts" was my awk bug.** `/proc/interrupts` lines for
`pmic_arb` IRQs end in `chip hwirq trigger name`, e.g.

```
 100:  69525 0 0 0 0 1 0 0  pmic_arb  98050261  Edge  wled_ovp_irq
```

Summing "all numeric fields" picks up `98050261`, which is the *hardware IRQ number*, not a count. Real
counts were 69,526 (ovp) and 0 (short) - no storm, no latched fault. Correct parse: sum `$2 .. $(NF-4)`.
Any future IRQ accounting must skip the header line and use that range.

**Correction 2 — storage storm follow-up that also went nowhere.** With `dpms=Off`, brightness was swept
0 → 160 → 1024 → 3000 and the OVP counter did not move at any level, so the counter is not
brightness-dependent either. Nothing to fix in `qcom-wled` on this device.

**Harvester v4** (`harvest4.sh`) now logs the top three IRQ movers by *name* each 2 s, plus `phoc`, `dpms`,
load and the printk-liveness probe. Idle baseline at the greeter: `arch_timer:+884 fault:+520 mmc0:+84`
per 2 s - clean, nothing pathological on an idle system.

**Standing picture after all the exonerations**

| theory | status | evidence |
|---|---|---|
| GPU runtime suspend | dead | `power/control=on`, froze anyway |
| CPUs 5-7 | dead | offlined, froze anyway |
| PMIC IRQ storm | symptom | masked at PMIC, froze anyway |
| eMMC width / storage | dead | 9.3 GB fsync load, survived |
| GPU rendering only | dead | pixman also dies, just later (247 s vs 77-107 s) |
| IRQ storm | open, now measurable | v4 tracker deployed, needs one login to settle |

**The one constant**: death follows the display becoming active with a real session. Userspace stops
writing first (harvester's last sample), the kernel keeps printing (DPU frame-event overflow, from IRQ
context), then the SoC resets with an empty pstore - a hardware reset, never a panic.

## 2026-10-25 23:20 IST — CORRECTION: software rendering is NOT immune; the common factor is the display commit path

**Correction to the "CONFIRMED: it is the GPU" entry above.** That conclusion was drawn too early. The user
confirmed the pixman boot was responsive when they reported "no freeze", and the harvester shows it stopped
at **t=247 s** — later than the GPU boots (77-107 s) but it still died, this time with **no panic and an empty
pstore** (a hardware reset, not a kernel panic).

So both rendering paths die; GPU just does it sooner. The honest reading:

- GPU rendering → more frames/sec → dies at 77-107 s.
- Software rendering → fewer frames/sec → dies at ~247 s.
- Both commit frames through the same **DPU/DSI** path, and login is when continuous commits begin.
- Therefore the prime suspect moved from freedreno to **the display commit path**, and "GPU compositing is
  the cause" is withdrawn.

**Also corrected**: a hard reset with empty pstore is not a panic. Earlier resets that DID leave ramoops
(`Rebooting in 120 secs`, softlockup traces) came from `softlockup_panic=1`. The mute resets are hardware
resets — the SoC is reset without the kernel getting a chance to write anything.

**Failed test, recorded so it is not retried**: `echo off > /sys/class/drm/card0-DSI-1/dpms` returns EACCES
even as root — the attribute is `-r--r--r--` on this kernel, so DPMS cannot be toggled from sysfs and a
mode-set stress loop is not possible that way. A first attempt that wrapped `tee` in `sudo` inside a loop
silently did nothing (sudo credential not carried per iteration); any future privileged loop must run inside
one `sudo -n sh -c '...'`.

**Next test (prof11, staged)**: `WLR_DRM_NO_ATOMIC=1` added to `/etc/profile.d/90-violet-pixman.sh`, i.e.
software rendering **plus legacy modesetting** instead of atomic commits. Survives → the atomic DPU commit
path is the hang (and GPU rendering with `NO_ATOMIC` becomes a candidate for a fast-but-stable phone).
Dies → display is cleared too and the search moves to the rest of the session bring-up.

**Operational mistake to avoid**: kexec was attempted while the phone was already on mainline. `kexec -e` only
works downstream→mainline; mainline→mainline drops the gadget and requires a physical power cycle. Always
check `uname -r` starts with `4.14` first.

## 2026-10-25 23:00 IST — CONFIRMED: the freeze is the GPU/compositor path. Software rendering is stable.

**prof9** (identical kernel and DT to prof8, only `WLR_RENDERER=pixman` restored in
`/etc/profile.d/90-violet-pixman.sh`): user logged in, **no freeze**. Verified at t=166 s:
`phoc=7711`, `phoc env: WLR_RENDERER=pixman WLR_RENDERER_ALLOW_SOFTWARE=1`, still holding 3 DRM fds
(same compositor, KMS path unchanged, only rasterisation moved off freedreno), GPU `runtime_status=suspended`
because nothing is using it.

**Conclusion.** With GPU rendering the system hard-locks 21-80 s after login (prof7/prof8) or at ~320-345 s
(prof4/prof6); with software rendering it survives. Everything else — eMMC 8-bit, PMIC mask, CPUs 5-7 — was
varied and did not change the outcome. **The GPU is the hang.** The earlier eMMC timeouts and the
`kick_all_cpus_sync` stalls are downstream damage once the GPU wedges the bus, not the cause.

**What is *not* the GPU problem** (all previously tested and wrong):
- Runtime suspend/repower: pinned `power/control=on` on `5000000.gpu` + `506d000.gmu`, still froze.
- Clock/power-domain bring-up: `&gcc { power-domains = <&rpmhpd RPMHPD_CX>; }` fixed `RCG did not turn on`
  and EGL works (`GL_RENDERER FD612`, `Mesa 26.2.4`), so context creation is fine — it is sustained
  rendering that kills it.
- Driver binding: `5000000.gpu` is bound to `adreno`, RGMU firmware `a612_rgmu.bin` + `a630_sqe.fw` load.

**One loose end worth knowing**: `506d000.gmu` has **no driver bound**, so
`gcc`/`gpucc ... sync_state() pending due to 506d000.gmu` never resolves. In 7.2 the GMU is parsed by the
parent adreno driver (`a6xx_gmu.c` has no platform_driver), so the orphan device may be cosmetic — but it
means those clock controllers never reach sync_state, and it is the first thing to check if GMU/RGMU
power sequencing is suspected.

**Next GPU experiments, cheapest first**
1. `echo 435000000 > /sys/class/devfreq/5000000.gpu/max_freq` (and `min_freq`) with GPU rendering on: if it
   survives, this is an OPP/voltage problem at the high points, and 5 boot-time
   `cpu cpu0: failed to update OPP for freq=...` messages say the OPP/voltage plumbing is already suspect.
2. Try the same at a single mid OPP (650 MHz) to bisect the frequency.
3. Only then go into the driver: RGMU/IFPC sequencing, `a6xx_pm_resume` ordering, and the v8 Adreno 612
   series (`20260312-qcs615-spin-2-v8-0-fca38edcd6e6@oss.qualcomm.com`) which is newer than 7.2.10.

**Working configuration right now**: mainline 7.2.10 kexec'd from r10, `WLR_RENDERER=pixman`, eMMC 8-bit
`non-removable` (CQE removed, 52 MHz cap), PMIC cleanup_irq mask patch, `WDT=off cpuidle.off=1`.

## 2026-10-25 22:50 IST — eMMC fix alone did not stop it; freezes accelerating (321 s -> 107 s -> 77 s); testing the software-rendering control

**prof7** (8-bit + non-removable, CQE auto-enabled, HS200 at full clock): login t=86 s, dead t≈107 s.
**prof8** (8-bit + non-removable, `/delete-property/ supports-cqe`, `max-frequency = <52000000>`): login, dead t≈77 s.
Both still show `mmc0: new HS200 MMC card` — note `max-frequency` caps the clock but does *not* stop the core from
selecting HS200 mode, so 52 MHz + HS200 timing is an inconsistent combination that probably should not be trusted.

**The harvester v2 printk probe did its job and produced a clean negative:**
```
[t=71] printk=ALIVE (hermes-hb-20-71)
[t=73] / [t=75] / [t=77]   <- samples stop here
```
`printk` was alive to t=71 s, then the 2-second file write itself stopped. So this is a **hard lockup with printk
still working right up to the end** — no panic, no stall report, no `PRINTK-STUCK`. The earlier mute freezes are
therefore not a printk bug; the machine simply stops executing.

**Trend across boots, which matters more than any single number:** prof4 died ~345 s, prof6 ~321 s, prof7 ~107 s,
prof8 ~77 s. Death arrives earlier every cycle. Candidate explanations: (a) something degrades with each
kexec-from-r10 cycle (hardware state left behind), (b) a resource that accumulates, or (c) the eMMC/fs is
getting worse — note `EXT4-fs (mmcblk0p86): error count since last fsck: 16` with an htree error on inode 2
(the userdata root dir) on every boot, and the rootfs is a loop image living on that partition.

**Control test now running (prof9)**: `WLR_RENDERER=pixman` restored in `/etc/profile.d/90-violet-pixman.sh`
(software rendering), everything else identical. This is the one configuration that has ever survived long
(`touch23`: 2.7 h), but that boot never logged in — so this is the first true A/B on the GPU path.

## 2026-10-25 22:45 IST — PMIC storm patch did NOT stop the freeze; the real cause is eMMC command timeouts

**Correction to the previous entry.** Masking the unmapped PMIC interrupts was a genuine fix — after it, the storm
went from `16677 callbacks suppressed` + repeated `cleanup_irq` to a single `cleanup_irq apid=143 per=0x11` at
33.8 s and nothing more. But the freeze still happened (login t=245 s, dead t≈305 s), so **the storm was a
symptom, not the cause**. Do not chase it further as the root cause.

**What the third boot's netconsole actually showed**
```
[312.9] mmc0: sdhci_msm: ----------- VENDOR REGISTER DUMP -----------
[321.0] rcu: INFO: rcu_preempt detected stalls on CPUs/tasks: 6-...0 idle=11b4/1/0x4000000000000000
[331.0] After 10 seconds, these CPUs still haven't responded to the NMI: 6
[331.0] mmc0: Timeout waiting for hardware cmd interrupt.
[331.2] NMI backtrace for cpu 7:
          _raw_spin_unlock_irqrestore+0x24 (P)
          sdhci_timeout_timer+0x54/0xd4
          call_timer_fn / __run_timer_base / run_timer_softirq
```
So the sequence is: **eMMC command timeout → sdhci timeout path → a CPU stops taking even NMIs → RCU stall →
anything calling `kick_all_cpus_sync()` (seccomp/BPF text_poke) blocks forever → panic.**

This also explains the repeated `EXT4-fs (mmcblk0p86)` errors: the rootfs is a **loop image on mmcblk0p86**, so
every file operation is loop → eMMC. Storage stalls therefore look like a whole-system freeze, and login (session
state, logs, service starts) is the reliable way to generate the needed write load.

**Root cause found in the DT, and it was our omission**
`talos.dtsi`'s `sdhc_1` is an EVK node; it sets `qcom,dll-config`/`qcom,ddr-config` but leaves `bus-width` and
`non-removable` to the board. Our `&sdhc_1` override only set `status = "okay"` — verified against the compiled
DTB, which had **no `bus-width` and no `non-removable`**. Consequences: the controller ran the eMMC **1-bit**, and
mmc treated it as a **removable** card, so a command timeout triggered rescan/re-init rather than a retry.
The vendor DT (`qcom,bus-width = <8>`, `qcom,nonremovable`, `bus-speed-mode = "HS400_1p8v","HS200_1p8v","DDR_1p8v"`)
is the reference.

**Fix applied (DT-only, ~1 min build)**
```dts
&sdhc_1 {
	status = "okay";
	bus-width = <8>;
	non-removable;
};
```
Verified in the compiled DTB: `bus-width = <0x08>; non-removable;`. Note `make arch/arm64/boot/dts/qcom/x.dtb`
doubles the path on this tree — use `make dtbs`.

**Deliberately NOT enabled yet**: `mmc-hs200-1_8v` / `mmc-hs400-1_8v`. Both need 1.8 V VCCQ switching, and violet's
vendor DT declares no `vqmmc-supply` (the bootloader leaves the rails on). Get 8-bit DDR working first, confirm
`mmc0: new DDR MMC card ... 8-bit` in dmesg, and only then try the higher speed modes.

**If this does not fix it**, the next suspects in order: (1) `qcom,dll-config` mismatch — DT says `0x000f642c`,
the live dump showed `0x00b7642c`; (2) missing `vmmc`/`vqmmc` rails making VCCQ marginal under load;
(3) `supports-cqe`/ICE path; (4) the eMMC itself (but r10 runs for hours, so the hardware is fine).

## 2026-10-25 22:35 IST — CPUs 5-7 EXONERATED; the freeze is a PMIC interrupt storm pinning CPUs in the chained handler

**Test:** booted mainline with CPUs 5-7 hot-removed (`psci: CPU5/6/7 killed`, `nproc=5`), all instruments live.
User logged in at t=443 s (`phoc` 3664 → 21272), froze at t≈505 s. **Offlining those cores changed nothing.**

**Second trace (console-ramoops-0, 889 lines, panic at 519.28 s)** — a *different* CPU and a *different* task:
```
watchdog: BUG: soft lockup - CPU#1 stuck for 11s! [sshd-auth.pam]
CPU#1: 100% system, 0% softirq, 1% hardirq, 0% idle
CPU: 1 PID: 24336 Comm: sshd-auth.pam      <-- an SSH child doing prctl(PR_SET_SECCOMP)
Call trace:
  smp_call_function_many_cond+0x43c (P)
  kick_all_cpus_sync → __text_poke → aarch64_insn_copy
  → bpf_arch_text_copy → bpf_jit_binary_pack_finalize → bpf_int_jit_compile
  → __bpf_prog_select_runtime → bpf_prepare_filter → bpf_prog_create_from_user
  → do_seccomp → prctl_set_seccomp → __arm64_sys_prctl
SMP: failed to stop secondary CPUs 0,(2),4
```
Note the failing set is now **0,2,4** — i.e. not 5-7, and not even the CPU running the trace. So the
unresponsive CPUs are whichever ones are stuck at that moment. `kick_all_cpus_sync()` is a *symptom*: it
requires an IPI ack from every online CPU, so it is the first thing to die when CPUs stop taking IPIs.
Also note it was **my own sshd child** (seccomp install) that triggered it, not Firefox — so "Firefox
causes the freeze" was always a coincidence of who happened to install a seccomp/BPF filter.

**Root cause candidate, now with a concrete mechanism** — the PMIC interrupt storm:
```
[274.5] spmi spmi-0: cleanup_irq apid=158 sid=0x0 per=0x48 irq=4
[274.5] print_irq_desc: 16677 callbacks suppressed     (irq 17 = SPMI parent, IRQ_LEVEL)
[ 35.3] spmi spmi-0: cleanup_irq apid=143 sid=0x0 per=0x11 irq=4   (usb-vbus-regulator@1100, DT: disabled)
[ 0.307] WARNING: drivers/spmi/spmi-pmic-arb.c:787 at pmic_arb_chained_irq, CPU#0: swapper/0/0
```
`per=0x11` is `usb-vbus-regulator@1100` (`status = "disabled"` while the phone sits on VBUS); `per=0x48` has
no node at all. Both are *inside* the bus APID range, so they go through `periph_interrupt()` →
`cleanup_irq()`, which clears the latch **but never clears the PMIC peripheral interrupt enable**. The source
re-asserts immediately, the chained handler re-enters with IRQs off, and a CPU stays pinned there long enough
to miss IPIs — which is exactly the `kick_all_cpus_sync` hang. This is the half of the kexec-from-vendor
problem the earlier patch (the `spurious spmi irq received for apid=%d` branch) did not cover.

**Patch applied** (`drivers/spmi/spmi-pmic-arb.c`, `cleanup_irq()`): after clearing the latch, also write
`QPNPINT_REG_EN_CLR` for that peripheral, mirroring the out-of-range-APID branch. Build started 22:37.

**Wrong turns, recorded so they are not repeated**
- GPU runtime suspend: exonerated (pinned `power/control=on` on `5000000.gpu` + `506d000.gmu`, still froze).
- "CPUs 5-7 wedge": exonerated (offlined them, still froze; failing set became 0,2,4).
- "Firefox/Settings cause it": wrong — it is whichever task installs a seccomp/BPF filter next.
- `HARDLOCKUP_DETECTOR`: built in, but the kernel prints `watchdog: NMI not fully supported` →
  `Hard watchdog permanently disabled`. Only **softlockup** detection works on this GIC configuration.

## 2026-10-25 22:20 IST — UI FREEZE DIAGNOSED: CPUs 5-7 stop answering IPIs; BPF JIT free is only the messenger

**What was lost before, and why.** Two earlier freezes left nothing: the 90-s `sessprof.py` run died mid-capture
(`/tmp` is **tmpfs**, so the JSONL was RAM), `ramoops` was wiped by a cold power cycle, and `logbookd.db`'s
newest rows belonged to the *previous* boot. Lesson: on this device, evidence must land on ext4 (`/var/log`)
and/or leave the machine (netconsole).

**Instrumentation that finally worked**
- 2-s `dmesg` harvester appending to `/var/log/sess-harvest.log` (ext4) with `sync` — survived a reset.
- `CONFIG_SOFTLOCKUP_DETECTOR=y`, panic on softlockup, `watchdog_thresh=5`.
- `CONFIG_NETCONSOLE=y` + configfs target → `10.11.12.1:6666`, verified with a `/dev/kmsg` test line.
- `CONFIG_PSTORE_CONSOLE=y` — `console-ramoops-0` **survived the reset** and held the backtrace.
- `CONFIG_HARDLOCKUP_DETECTOR=y` + `ARM64_PSEUDO_NMI=y` built, but at boot the kernel says
  `watchdog: NMI not fully supported` → `Hard watchdog permanently disabled`. The NMI path is unusable on
  this GIC config; **softlockup is what caught it**, so do not expect per-CPU NMI backtraces here.

**The trace (console-ramoops-0, 831 lines, panic at 386 s)**
```
watchdog: BUG: soft lockup - CPU#0 stuck for 13s! [kworker/0:1:10]
CPU#0: 97% system, 0% softirq, 4% hardirq, 0% idle   (all 5 samples)
Workqueue: events bpf_prog_free_deferred
pc : smp_call_function_many_cond+0x43c
Call trace:
  smp_call_function_many_cond → kick_all_cpus_sync → __text_poke → aarch64_insn_set
  → bpf_arch_text_invalidate → bpf_prog_pack_free → bpf_jit_binary_pack_free
  → bpf_jit_free → bpf_prog_free_deferred → process_scheduled_works → worker_thread
SMP: stopping secondary CPUs
SMP: failed to stop secondary CPUs 5-7
Rebooting in 120 secs
```

**Reading it.** CPU0 is not wedged — it is *waiting*: `kick_all_cpus_sync()` broadcasts an IPI and blocks
until every online CPU acknowledges. CPUs **5-7 never acknowledge**, so CPU0 spins in
`smp_call_function_many_cond` at 97-98 % system time until the softlockup watchdog panics. The same CPUs
then fail to stop at panic time, which is independent confirmation that they are unreachable, not just slow.

So the freeze is **not** a GPU fault, **not** memory pressure, and **not** the BPF subsystem being broken.
It is CPUs 5-7 going unresponsive; `kick_all_cpus_sync` is simply the first thing that *notices* by requiring
a reply from them. This is the same family as the earlier "these CPUs still haven't responded to the NMI: 7"
RCU stalls, now reproduced with a stack instead of a stall message.

**Why Firefox/Settings looked guilty.** Anything that frees a BPF JIT image goes through `text_poke` →
`kick_all_cpus_sync`. Browser sandboxes and seccomp-heavy apps free BPF programs routinely. Before the
freeze the box also showed, on netconsole:
```
[279.9] spmi spmi-0: cleanup_irq apid=158 sid=0x0 per=0x48 irq=4
[279.9] print_irq_desc: 14285 callbacks suppressed      (irq 17 = SPMI parent, level-triggered)
[345.2] spmi spmi-0: cleanup_irq apid=143 sid=0x0 per=0x11 irq=4
```
`per=0x11` is `usb-vbus-regulator@1100`, which our DTS keeps `status = "disabled"` while the phone sits on
VBUS; `per=0x48` has no node at all. These are real unhandled level-triggered PMIC interrupts
(`cleanup_irq` = "no irq mapping, clear and move on"), and 14 285 suppressed reports on the parent IRQ says
they re-assert constantly. Keep them on the suspect list for *why* CPUs 5-7 get stuck, but they are not yet
proven causal.

**Test queue (cheapest first)**
1. `net.core.bpf_jit_enable=0` → BPF programs interpreted, so the `text_poke`/`kick_all_cpus_sync` free path
   disappears. If the freeze stops, the mechanism is confirmed and the user gets a usable phone meanwhile.
2. Offline CPUs 5-7 (`/sys/devices/system/cpu/cpu5..7/online = 0`) with the JIT still on. If the freeze stops,
   it pins the wedge to those cores rather than to the IPI path.
3. Settle the PMIC interrupt storm: enable `pm6150_vbus` (claim irq 4) and identify `per=0x48`.

**Do not repeat**: chasing GPU suspend (pinned `power/control=on` for `5000000.gpu` and `506d000.gmu`,
`runtime_status=active` throughout, froze anyway) or blaming a specific app.

## 2026-10-24 (night) — the "silent" hang is NOT silent: CPU 7 stops answering NMIs (OPEN, untested)

**Evidence, from the ramoops ring of the most recent mainline boot** (`pstore-hang-2026-10-24.txt`,
89 KB pulled off the phone; text bit-garbled as usual but readable — `pstore-clean.txt` is the
printable-filtered copy). Five RCU stall episodes at t = **354, 573, 729, 875, 1011 s**:

```
rcu: INFO: rcu_preempt detected stalls on CPUs/tasks:
rcu:    7-...0: (11 ticks this GP)
rcu:    (detected by 4, t=21004 jiffies, g=49361, q=3214 ncpus=8)
rcu:    Sending NMI from CPU 4 to CPUs 3:
rcu:    After 0 seconds, these CPUs still haven't responded to the NMI: 7
rcu:    rcu_preempt kthread starved for 9996 jiffies!
```

- **CPU 7 never answers an NMI, in all five episodes.** `g=49361` is identical every time, i.e. RCU
  is stuck in ONE grace period for ~11 minutes: CPU7 never reports a quiescent state.
- The detector runs on CPUs 1/4/5 and their backtraces show userspace PCs in `Comm: gmain`, so the
  rest of the SoC is executing normally while one core is gone. This is why nothing appears on
  screen / over ping: the freeze is not a kernel-wide panic and produces no oops.
- Boot log in the same ring: `psci: PSCIv1.1 detected in firmware`, `Using standard PSCI v0.2
  function IDs`, `PSCI_GET_INFO_TYPE not supported`, and
  **`cpuidle PSCI: Initialized CPU PM domain topology using OSI mode`**. The RCU GP kthread's own
  backtrace is `cpuidle_enter_state -> cpuidle_enter -> do_idle`.
- Caveat: that boot ran >= 1021 s, so it is probably the *bare phoc* run, not a phrog one (the ring
  was overwritten). It still proves the failure class exists without phrog — and it names a CPU.
- Side findings in the same ring: `spmi spmi-0: cleanup_irq apid=158 sid=0x0 per=0x00` with
  `bad_chained_irq` at 25.8/88.7/301.2 s (unhandled PMIC IRQs, same class as the old storm patch),
  and `EXT4-fs (mmcblk0p86): error count since last fsck: 16` (the known corrupt vendor partition).

**Hypothesis.** CPU7 enters a PSCI OSI idle state it never returns from. `talos.dtsi` carries the
**EVK's** idle states (`little_cpu_sleep_0/1`, `big_cpu_sleep_0/1`, `cluster_sleep_0/1/2`), and
`violet-sm6150.dts` has **no** psci/idle override anywhere (672 lines, zero matches). Firmware
advertises PSCIv1.1 with OSI, so the kernel hands idle entry to XBL/ATF with EVK latencies. Once the
core is gone, RCU starves, then anything holding a lock it owns or with an IRQ affined to it wedges —
which is the 20-40 s phrog death. Under this reading the **63 atomic commits and the 16-byte
FB_DAMAGE_CLIPS blob are innocent** (msm has no partial-update support; the property is inert), and
the stall evidence predates any phrog run.

**Artifacts prepared (all offline, nothing flashed/flashed-ready):**
- `tools/cpu-wedge-watch.sh` — 1 Hz `/proc/stat` sampler that prints `WEDGED cpus:N` the moment a
  core stops accumulating jiffies, then snapshots dmesg + /proc/interrupts. Pushed to the phone's
  `/tmp/` already. Uses only /proc, nothing that can hang the bus.
- `tools/idle-wedge-test.sh <variant> [phrog|phoc]` — one boot + instrumented session + log pull.
- `kernel/.../qcom/violet-sm6150-noidle.dts` / `-noa76idle.dts` (+ built `.dtb`, `dt-validate` rc=0,
  verified the `domain-idle-states` properties are actually gone): PSCI idle states stripped so
  cpuidle falls back to WFI.
- `kexec-test.sh` now honours `DTB_SRC` so a variant DTB can be kexec'd without touching the tree.

**Test matrix (decision rules):**

| variant | change | if it survives 5 min |
|---|---|---|
| `maxcpus7` | `maxcpus=7` | it is CPU7 — and it is a workaround (lose one A76) |
| `cpuidle-off` | `cpuidle.off=1` | the wedge is in PSCI idle entry/exit, not DRM |
| `no-idle-dtb` | DTB, no domain idle states | OSI/hierarchical idle is the culprit, WFI is fine |
| `no-a76-idle-dtb` | DTB, only cpu6/7 lose states | the A76 per-core states specifically |
| `teo` | `cpuidle.governor=teo` | state-selection/load related rather than a broken state |

None survive -> go back to the DRM/compositor theories (cursor plane, multi-plane, modifiers).
Run order: `cpuidle-off` first (cheapest, most decisive), then `maxcpus7`, then the DTB variants.

**Measured 2026-10-24 (later) — first two runs INVALID, corrected here so nobody cites them.**

- `cpuidle-off`: watcher ran 379 s with 0 `WEDGED` lines, but the run log says
  `greetd ok phoc= phrog=` — **both pids empty. No session ever started.** An idle SoC survives 11+
  min in the older notes anyway, so this measured nothing about the hypothesis.
- `baseline`: the ssh link died right after boot (`Network is unreachable`) and the session start never
  executed; same idle-SoC outcome.
- Both failures had the same root cause: every `ssh` reused an address/interface captured once per run,
  and the NCM gadget re-enumerates (u1/u4) with a different link-local across a kexec. Fixed: `rssh`/
  `rscp` re-resolve on every call, and the watcher now logs `phoc=/phrog=` counts per sample so a
  "survival" cannot be claimed without a session.
- Also found: greetd on mainline is `status: crashed` with a stale pidfile ("already started", no
  process) and `error: check_children: greeter exited without creating a session`. So
  `rc-service greetd restart` silently produces no compositor. The harness now falls back to
  `/usr/libexec/phrog-greetd-session` directly when `pgrep -x phoc` is empty.
- **First valid data point:** starting the greeter session directly wedged the SoC within ~6 s (USB
  gadget gone, no return in 60 s, no kernel message) on the *default* tree. That is the reported failure,
  reproduced, and it confirms the trigger is the session, not the watcher.

**Corollary on the hypothesis: still untested.** Nothing so far distinguishes the PSCI-OSI idle theory
from a DPU/compositor-side hang; the earlier "cpuidle-off survived" claim was an artefact.

**Tooling rules learned the hard way (now baked into `tools/idle-wedge-test.sh`):**
1. `kexec-test.sh` arms the APSS watchdog with `WDT=ext` = bark 0xffffe (~32.0 s) / bite 0xfffff
   (~32.7 s). Mainline has no driver to handle or pet it, so the bark storms IRQs and **the eMMC dies**
   (`mmc0: Timeout waiting for hardware cmd interrupt` at 33.27 s, full SDHCI dump) — that looks exactly
   like the wedge under test. Every run must either disable it from inside mainline (`wdt-disable.py off`,
   `EN=0`) or be read as a <=32 s experiment.
2. With `EN=0` a hung mainline **never self-recovers**: USB disappears entirely and the phone needs a
   ~15 s Power hold. So `baseline` now defaults to `KEEP_WDT=1` (armed, auto-recovers because it dies
   inside the 32 s window) and only "should survive" variants disable it.
3. `dmesg` is restricted on this image — `dmesg` without sudo returns nothing and looks like a clean log.
   Always `sudo -n dmesg`.
4. The USB gadget re-enumerates under a different name (u1/u4) and a different link-local across a kexec,
   so discovery must rescan every `enp0s20f0u*` each poll; a hardcoded interface makes the run look dead.
5. **`wdt-disable.py off` is sticky across kexec.** It clears `WDT0_EN`; `kexec-test.sh`'s `WDT=ext` path
   only rewrites BARK/BITE/RST and never sets `EN` again, so once any run has disabled it, later runs have
   no watchdog at all — confirmed in the baseline log (`after: EN=0 BARK=77fd3 BITE=8ffca`). A full power
   cycle is the only thing that re-arms it, which is why a wedged mainline now needs a manual Power hold.

**Next runs, in order:** `baseline` with `KEEP_WDT=1` (prove the harness reproduces), `maxcpus7`
(excluding CPU7 enough?), `no-a76-idle-dtb` (the A76 per-core states?), then `teo`.

**Blocker to clear first: the greeter does not start on mainline.** `greetd` is `status: crashed` with a
stale pidfile; `rc-service greetd restart` yields no phoc. Any run is meaningless until a session exists.
`tools/phrog-logged.sh` (push to `/usr/local/bin/`, point `[default_session] command` at it) captures
phoc/phrog output in `/tmp/phrog-session.log` — the stock session pipes to `logger` and this image runs
no syslogd, so failures are silent. Order: get phoc up (seat / DRM master / renderer), *then* the ladder.
If phoc itself is what wedges the SoC within seconds, the ladder becomes irrelevant and the DPU/cursor
theories come back — that is the fork in the road after the next run.

**Why the DTB is the right lever (vendor comparison, 2026-10-24 night).**
`~/violet-mainline/dt/ref/base-sm6150.dtsi` — the vendor tree violet actually ships — declares:

```
psci {
	compatible = "arm,psci-1.0";
	method = "smc";
};
```

**No `power-domain-*` children, no `domain-idle-states` anywhere.** The `idle-cost-data` values in that
file belong to the scheduler's energy model (`core-cost`/`cluster-cost`), not to PSCI idle states. The
vendor kernel idles through Qualcomm's own `lpm-levels` driver, so the firmware on a retail violet has
never been exercised with the EVK's PSCI OSI state layout. Mainline's `talos.dtsi` adds all of it
(`cpu_pd0..7` with `little/big_cpu_sleep_0/1` + `cluster_pd` with `cluster_sleep_0/1/2`), the kernel sees
`psci: OSI mode supported` and takes that path — a code path the phone's XBL/ATF was not provisioned for.

That makes both measurements the predicted outcome: `cpuidle.off=1` survives, baseline loses CPU7. It
also means the honest fix is a board DTS that either (a) declares no idle states (WFI — what
`no-idle-dtb` tests) or (b) later models violet's real states once someone ports the vendor LPM config;
copying the EVK's numbers is what got us here.

Also noted: the vendor cmdline carries `rcu_nocbs=0-7 rcupdate.rcu_expedited=1`; mainline's kexec cmdline
carries neither. Worth one A/B run, since `rcu_nocbs` changes where callbacks run relative to a wedged CPU.

**Status: 1 of 5 variants measured.**

## 2026-10-25 - GPU: enabled for real (RCG fixed by the GCC CX vote), UI now hardware-rendered

Question asked was "is the rendering still software?", so this was measured rather than assumed.

### The missing piece was one DT line
`gcc: clock-controller@100000` in `talos.dtsi` has only `#power-domain-cells` (it is a *provider*); it
has no consumer link to the CX rail. Upstream added one in commit `5ad7eb6a944e`, merged after our
7.2.10 base. Added to `violet-sm6150.dts`:
```dts
&gcc { power-domains = <&rpmhpd RPMHPD_CX>; };
```
Result on the next boot (`touch24`, DT-only change, no kernel relink):
- `gpu_cc_gx_gfx3d_clk_src: RCG did not turn on` (previously at 0.234 s) **is gone**.
- `/sys/class/devfreq/5000000.gpu/available_frequencies` = 435 500 650 745 845 MHz, `cur_freq` 435 MHz idle.
- `msm_dpu ... bound 5000000.gpu (ops a3xx_ops)` as before (`a3xx_ops` is the shared component_ops, not an
  A3xx fallback), firmware loaded: `qcom/a630_sqe.fw`, `qcom/a612_rgmu.bin`.

### GPU proven with a direct EGL probe
`/tmp/egl-probe2.py` (ctypes, GBM platform + surfaceless fallback) on `/dev/dri/renderD128`:
```
EGL_VENDOR  : Mesa Project
GL_VENDOR   : freedreno
GL_RENDERER : FD612
GL_VERSION  : OpenGL ES 3.2 Mesa 26.2.4
```
So the A612 is a working GLES 3.2 device. Two ctypes traps worth remembering: `EGL_PLATFORM_GBM_KHR` is
0x31D7 (0x31DD is surfaceless and returns NULL with a gbm device), and every EGL/GLES symbol needs
explicit `argtypes`/`restype` or the call truncates a pointer and segfaults (exit 139).

### Why the UI was still software
`/etc/profile.d/90-violet-pixman.sh` (downstream-era workaround, from when there was no DRM GPU node)
forced `WLR_RENDERER=pixman` + `WLR_RENDERER_ALLOW_SOFTWARE=1` into every session. Renamed to
`.disabled`, greetd restarted. phoc now runs with no renderer override and holds
`/dev/dri/renderD128` (fds 17/18) with `libgallium-26.2.4.so` mapped - i.e. wlroots' default gles2 path
on freedreno. Greeter session (`gnome-session --session=phrog`, `/usr/sbin/phrog`) up, `dpms=On`,
no adreno/a6xx/IOMMU faults, GPU idling at 435 MHz.

### Notes / cleanup
- The two "suspected GPU fixes" from the research sweep (add `qcom_branch_set_force_mem_core/periph_on`
  to `gpucc-qcs615.c`, and re-order `a6xx_pm_resume` to vote GX before the gfx3d clock) turned out to be
  **unnecessary here**: the clock tree comes up correctly once CX is held. Do not apply them blindly.
- `dummy vdd/vddcx` messages are still expected on a6xx (genpd supplies the power); not a defect.
- `90-violet-pixman.sh.disabled` should be deleted from the image rather than left on disk, and the fix
  belongs in the device package if violet's mainline rootfs is ever rebuilt.

## 2026-10-25 - TOUCH WORKS (verified with real events)

`touch23` (mainline 7.2.10-sm6150, kexec from r10) - probe now succeeds:
```
[    5.063893] msm_dpu ae01000.display-controller: bound ae94000.dsi (ops dsi_ops)
[    4.966826] novatek-nvt-ts 0-0001: Error reading from 0x78: -6
[    5.184749] novatek-nvt-ts 0-0001: Error reading from 0x78: -6
[    5.393188] novatek-nvt-ts 0-0001: Detected 1080x2340 touchscreen with 10 max touches
```
`/proc/bus/input/devices` count went 1 -> 2 (`pm8941_pwrkey`, `nt36672a-ts`), `/dev/input/event1`
created. Note the panel bound at 5.06s again - i.e. NOT delayed - which independently confirms the
blocking-probe diagnosis.

Real-event capture from `/dev/input/event1` while the user swiped the panel:
```
944 events / 192 frames
ABS MT_X = 695 -> 692 -> 688 -> 683 -> 678      (monotonic drag)
ABS MT_Y = 1526 -> 1541 -> 1557 -> 1573 -> 1593
KEY BTN_TOUCH = 1        ABS MT_TRACKING = 18
```
Coordinates are inside the 1080x2340 space and vary smoothly frame-to-frame => genuine touch input.

### The complete root cause, in order
1. **Wrong i2c address**: register map is at **0x01** (`I2C_FW_Address`), not 0x62 (`I2C_HW_Address`,
   hardware-command window only). The vendor DT's `reg = <0x62>` is inert because that driver hardcodes
   the address per transfer. Every earlier experiment NACKed regardless of rails/polarity/timing.
2. **Probe ran before the chip had power**: touch VCC is the panel bias (LCDB), enabled only when the
   DSI/panel driver binds.
3. **Waiting for it in probe could never work**: the panel's deferred probe runs on the same
   single-threaded `deferred_probe` workqueue the sleeping probe occupies, so each extra second of retry
   pushed the panel out by the same amount (measured 5.6s / 15.1s / 38.6s for 0.4s / 9s / 30s windows).
   Fix = return from probe immediately and poll from a delayed_work on the system workqueue.

### State of the code (local patches, not upstream-shaped yet)
- `violet-sm6150.dts`: `touchscreen@1`, `reg = <0x01>`, reset GPIO 88 taken `GPIOD_ASIS` and never
  written, `vcc-supply = <&pm6150l_lcdb>`, `iovcc-supply = <&vreg_l13a_1p8>`.
- `novatek-nvt-ts.c`: `nvt_ts_probe()` only claims regulators + reset GPIO and schedules
  `nvt_ts_init_work`; that work does rails -> one 0x78 read -> retry every 200ms for up to 30s -> parse ->
  register input device/IRQ.
- Follow-up for upstream submission: replace the delayed_work hack with the proper panel-follower
  ordering (`drm_panel_add_follower`, power+read in `panel_prepared`), which is what the unmerged patch
  "Input: novatek-nvt-ts - support being panel follower" does; our behaviour then becomes the same
  without the 500ms polling window.

### Remaining work on violet
- GPU (A612): verify `a6xx_pm_resume()` votes GX before enabling `gpu_cc_gx_gfx3d_clk`, and add the
  missing `force_mem_core`/`force_periph_on` branch programming to `gpucc-qcs615.c`.
- ABL: rebuild the boot image in violet's stock format (header v0, `Image.gz-dtb`, base 0x80000000,
  pagesize 4096, os_version 9.0.0) and zero the dtbo, instead of header v2 + standalone DTB.

## 2026-10-25 - GPU + ABL: research corrections worth keeping

- **`bound ... (ops a3xx_ops)` is NOT an A3xx fallback**: `a3xx_ops` is the single `component_ops`
  struct in `adreno_device.c` used for every Adreno; the message comes from `drivers/base/component.c`.
  Identification parses the *compatible string* (`qcom,adreno-612.0` -> chip id 0x06010200) and looks it
  up in `a6xx_catalog.c`. So the GPU is being identified as A612 correctly.
- **`supply vdd/vddcx not found, using dummy regulator` is normal on every a6xx board**; power comes
  from genpd (gpu node `RPMHPD_CX` + gmu node `gpucc CX_GDSC`/`GX_GDSC`) scaled by OPP required-opps.
  Do not add regulator supplies to "fix" it.
- Real suspects for `RCG did not turn on`, in order: (a) upstream `a6xx_pm_resume()` votes GX **before**
  enabling `gpu_cc_gx_gfx3d_clk`, and the gfx3d RCG lives in the GX block so it can never report on
  while GX is collapsed - verify locally whether our tree deviates; (b) `gpucc-qcs615.c` is missing the
  `qcom_branch_set_force_mem_core()`/`force_periph_on()` programming that `gpucc-sm6115.c` and
  `gpucc-sm6125.c` apply to `gpu_cc_gx_gfx3d_clk`. That missing gpucc work is the "separate series"
  deferred by the A612 patch set and still absent from mainline.
- **ABL refusal, best leads**: violet's own LineageOS BoardConfig builds `Image.gz-dtb` with header v0
  (`--base 0x80000000 --kernel_offset 0x8000 --ramdisk_offset 0x01000000 --tags_offset 0x100 --pagesize
  4096`, separate 8MB dtbo). Our image is header v2 + standalone DTB. Community practice for ABL-era
  devices is `fastboot erase dtbo` / zero-fill it - ginkgo's bring-up journal documents 24 fastboot
  returns caused by "ApplyOverlay: ufdt apply overlay failed" from a stock dtbo. Also: never judge an
  image with `fastboot boot` (dies in ABL's decompressor); flash and reboot.

### touch21 result: missed the panel by 185 ms
Node is now `touchscreen@1`/`reg = <0x01>`, driver retries 150x60ms. Log:
```
[    0.617702] novatek-nvt-ts 0-0001: Error reading from 0x78: -6      <- probe starts early
[   14.905718] novatek-nvt-ts 0-0001: Error reading from 0x78: -6      <- window exhausted
```
150 attempts, 0.6s -> 14.905s, all NACK. Panel side, same boot:
```
[   15.090603] msm_dpu ae01000.display-controller: bound ae94000.dsi (ops dsi_ops)
[   15.576760] DSIDBG enable_video
```
**The retry window ends 185 ms before the panel binds** - i.e. before the panel has powered the
LCDB bias the touch chip sits on. `phoc` starts at t=31.61s (from /proc/<pid>/stat starttime), so the
chip is answerable from ~15.1s onward, while the compositor only appears at 31.6s.
(Note the panel bound at 15.09s on this boot but at 5.604s on an earlier one - the timing varies with
probe order, so the window needs real headroom rather than a tuned constant.)

Fix in flight: retry window widened to **500x60ms = 30s**, which covers the observed 5.6-15.1s panel
bind range with margin. Probe is async, so this delays only the touch device, not boot.

Reminder of why this is worth the wait: the very same transfer succeeds from userspace once the panel is
up - `reg 0x78 -> 28 d7 12 24 04 38 09 24 0e 0a 00 01 01 01 08` = 1080x2340, 10 touches, chip-id 0x08.

Long-term the correct fix is still panel-follower ordering (register `drm_panel_add_follower()`, do the
power-on + parameter read in the `prepared` callback), which removes the guesswork entirely; the upstream
patch for exactly this is unmerged as of 7.2.10.

### touch22: the retry loop was itself the problem (self-defeating)

With a 30s window the probe still failed - and this time the log showed why:
```
[   38.235969] novatek-nvt-ts 0-0001: Error reading from 0x78: -6    (500 attempts)
[   38.621903] msm_dpu ae01000.display-controller: bound ae94000.dsi   <- panel, again AFTER us
[   54.910000] phoc start
```
Userspace read on the same boot at t=121s: `reg 0x78 -> 28 d7 12 24 04 38 09 24 0e 0a 00 01 01 01 08`.

Correlation across the three boots is the whole story:

| boot | touch retry window | panel bound at |
|---|---|---|
| touch20 | 0.4 s | 5.60 s |
| touch21 | 9 s | 15.09 s |
| touch22 | 30 s | 38.62 s |

The panel's probe defers and is retried on the **single-threaded `deferred_probe` workqueue** - the same
worker our probe occupies while it sleeps. So every extra second we wait pushes the panel out by the same
amount, and the chip (powered by the panel's LCDB bias) can never answer. **No retry constant can win**;
waiting in probe is structurally wrong.

### Fix implemented: non-blocking init work
`nvt_ts_probe()` now only gets the regulators + reset GPIO and returns, scheduling
`nvt_ts_init_work` (delayed_work on the system workqueue) 500ms later. That work:
- enables the rails, does ONE 0x78 read, disables the rails;
- on -ENXIO reschedules itself every 200ms, up to 150 tries (30s) - without holding the probe worker;
- on success parses the parameters and registers the input device / IRQ.
This is the same shape as the vendor kernel's fb-notifier work and as the unmerged upstream
"panel follower" patch, but it needs no DRM plumbing and no DT change.
Build in flight; expected outcome: `Detected 1080x2340 touchscreen with 10 max touches` and an
`event1` device once the panel powers the chip (~5-15s after boot).

## 2026-10-25 - TOUCH SOLVED IN PRINCIPLE: wrong i2c address + panel-rail timing

Parallel research sweep (5 subagents) paid off. Two facts, both verified locally, explain every
negative result so far:

### 1. The controller's register map is at address 0x01, not 0x62
Oracle: the vendor driver's own header, `~/violet-pmos/kernel/drivers/input/touchscreen/nvt_touch_f7b/nt36xxx.h`:
```
#define I2C_BLDR_Address 0x01
#define I2C_FW_Address   0x01
#define I2C_HW_Address   0x62
```
Every data read/write in `nt36xxx.c` passes `I2C_FW_Address` (0x01); 0x62 is used only for the two-byte
hardware commands (0x69 bootloader reset, 0xA5 idle). The vendor DT's `reg = <0x62>` is decorative - that
driver hardcodes the address per transfer and never reads `client->addr`, so we copied a value that was
never load-bearing. Mainline reads its 0x78 parameter block at 0x62 and gets a clean NACK.

Verified live on a running mainline boot (userspace i2c-dev, same adapter i2c-0 that the driver uses):
```
probe 0x01: ACK
reg 0x78 -> 28 d7 12 24 04 38 09 24 0e 0a 00 01 01 01 08
probe 0x62: reg 0x78 read failed: errno=6 (ENXIO)
```
Decoding those 15 bytes against `novatek-nvt-ts.c`'s own offsets:
| field | offset | bytes | value | verdict |
|---|---|---|---|---|
| width  | 0x04 | 04 38 | 1080 | matches violet panel |
| height | 0x06 | 09 24 | 2340 | matches violet panel |
| max_touches | 0x09 | 0a | 10 | <= NVT_TS_MAX_TOUCHES |
| buttons | 0x0a | 00 | 0 | no buttons |
| irq_type | 0x0b | 01 | FALLING | valid index |
| chip_id | 0x0e | 08 | 0x08 | **= nvt_nt36672a_ts_data.chip_id** |
So the part is a genuine NT36672A, correctly wired and speaking the protocol mainline expects.

### 2. Probe runs before the chip has power
Driver probe reads at t=5.36s. `msm_dpu ... bound ae94000.dsi` happens at t=5.604s. The touch's VCC is
the panel bias rail (LCDB), which the panel driver only enables when it binds - i.e. ~250ms after the
touch probe already gave up. Userspace reads at t=43s succeed; at probe time they cannot.
This is exactly the failure mode of the still-unmerged upstream patch *"Input: novatek-nvt-ts - support
being panel follower"* (Minnekhanov/Boiano, 2026-07-18): "Without this probing touchscreen before panel
sometimes randomly fails with I2C read errors."

### Find and fix in flight
- DTS: node renamed `touchscreen@1`, `reg = <0x01>` (was @62).
- Driver: probe retry window widened 20x20ms -> **150x60ms (~9s)** so it spans panel power-on; the
  correct long-term fix is panel-follower ordering (power the touch in `drm_panel_prepared`), which is
  what that upstream patch does.
Rebuilding `Image` now; expect the probe to succeed inside the window and register an input device
(1080x2340, 10 touches).

### Why every earlier attempt failed (for the record)
Wrong address (0x62) meant every transfer NACKed regardless of rails, polarity, pulse, high-Z, retry
count or bus speed. The `-110 -> -6` improvement, all the polarity work and the LCDB rail change were
real but irrelevant while the address was wrong.

## 2026-10-25 - Xiaomi OSS kernel repo (MiCode) checked: no new touch data, real GPU reference

Repo has two relevant branches: **violet-p-oss** (Android P, LA.UM.7.9.r1-03500-sm6150.0) and
**violet-q-oss** (Android Q, LA.UM.8.9.r1-04400-SM6xx.0-1).

Findings:
- Neither branch contains a violet board file. `arch/arm64/boot/dts/qcom` on violet-q-oss has 670
  files, of which 66 are sm6150/talos - all generic (`sm6150-idp.dtsi`, `sm6150-*_f7b.dtsi`). Grepping
  every entry for "violet" returns **nothing**. Xiaomi does not publish violet's device DTS.
- Our local vendor tree **is this source**: `sm6150-gpu.dtsi` 14268 B and `sm6150-gdsc.dtsi` 5346 B
  download byte-for-byte identical in size to `~/violet-pmos/kernel/.../qcom/`.
  => **nothing new for touch is available here**; the idp/f7b nodes we already read are all there is.

What it *does* give, saved to `dt/ref/sm6150-gpu.dtsi` + `dt/ref/sm6150-gdsc.dtsi`: the authoritative
GPU configuration, which maps straight onto our three GPU defects:
- `regulator-names = "vddcx", "vdd"` with `vddcx-supply = <&gpu_cx_gdsc>`, `vdd-supply = <&gpu_gx_gdsc>`
  - GPU power is **GDSC-based, not PMIC rails**;
- `clocks = <&clock_gpucc GPU_CC_GX_GFX3D_CLK>` plus `qcom,gpu-qdss-stm` and `gpubw`;
- `qcom,gpu-speed-bin = <0x6004 0x1fe00000 21>` and pwrlevels up to 845 MHz.

### Consequence for the GPU work item (root cause identified)
Mainline has everything needed: `gpucc-qcs615.c` (talos binds `qcom,qcs615-gpucc`), an **a612** entry in
`a6xx_catalog.c` (`a612_hwcg`, `a612_rgmu.bin`), and the device already ships `a612_rgmu.bin` +
`a612_zap.mdt/.b0x` in `/lib/firmware/qcom/`. Yet it binds `a3xx_ops` with dummy vdd/vddcx.
The cascade starts at the clock: `gpu_cc_gx_gfx3d_clk_src: RCG did not turn on` -> no GX_GFX3D_CLK ->
the GPU core cannot be read/identified -> driver falls back to a3xx ops -> supplies never get votes.
So the GPU fix is a **gpucc/GDSC clock bug**, not missing support: get `GPU_CC_GX_GFX3D_CLK` (and the
GX GDSC) running and the rest should follow.

## 2026-10-25 - GPU status on mainline (new finding, separate from touch)

Asked whether Ubuntu Touch has GPU rendering, so I checked our own mainline GPU at the same time.
It is **not** working, and dmesg says why:

```
[    0.235447] gpu_cc_gx_gfx3d_clk_src: RCG did not turn on
[    5.612528] adreno 5000000.gpu: supply vdd not found, using dummy regulator
[    5.619731] adreno 5000000.gpu: supply vddcx not found, using dummy regulator
[    5.629078] msm_dpu ae01000.display-controller: bound 5000000.gpu (ops a3xx_ops)
```

Three separate defects:
1. the GPU binds **`a3xx_ops`** - wrong family. Adreno 612 (SM6150) is a6xx-generation, so the model
   derived from our DT compatible is a 3xx part;
2. **`gpu_cc_gx_gfx3d_clk_src: RCG did not turn on`** - the gfx3d clock never comes up (clock
   controller wiring / parent rates for sm6150 GPU CC);
3. `vdd` and `vddcx` supplies missing -> dummy regulators, so no GPU power vote.

Consequence: `/dev/dri/renderD128` exists (the DPU's node) and Mesa ships `msm_dri.so`/`zink_dri.so`, but
there is no usable 3D engine - the phoc session is software-rendered. Fixing this is a self-contained
work item (`&gpu` node in talos.dtsi: correct compatible for the A612 part, GPU CC clocks, vdd/vddcx
rails from pm6150l/pm6150, and the gpu iommu/cx gdsc), independent of touch.

Ubuntu Touch comparison: its port does have working accelerated graphics, because it never touches a
Linux GPU driver - Mir composites through Android's hwcomposer and GLES runs on the vendor Adreno blobs
via libhybris (mardy's working list for violet: "Mir, with graphics and input: Unity8 starts and is
usable"). Caveat: the violet port exists only on the **outdated 16.04 xenial** channel;
devices.ubuntu-touch.io reports "This device isn't ported yet" for 20.04 and 24.04.

## 2026-10-25 - Ubuntu Touch question, and the beryllium blueprint (negative)

### Is Ubuntu Touch's violet support useful?
No, not for mainline. The UT port (mardy, 2020-21) is **Halium 9**: LineageOS 16.0 Android-9 base,
vendor kernel **4.14.83**, `vendor/violet-perf_defconfig`, libhybris. It runs the same downstream
Novatek driver as our r10, so it transfers no mainline touch knowledge - it is the vendor stack with a
different userspace. Its deviceinfo/halium-boot recipe is also Android-boot-image based, so it does not
help with our ABL/DTB refusal either.
Where it IS relevant: as a *fallback product* it gives a working Linux phone with touch+display today,
because it never leaves the vendor kernel. Different tradeoff, not a step toward mainline.

### The one real lead it surfaced: a working mainline NT36672A port
Mainline's `sdm845-xiaomi-beryllium-tianma.dts` runs the SAME controller (`novatek,nt36672a-ts`) on a
Xiaomi device, so I used it as a blueprint. Differences from our node:
- `vcc-supply = <&lab>` - the **panel bias rail**, not a generic PMIC LDO
- `iovcc-supply = <&vreg_l14a_1p8>` - 1.8 V DSI rail (we already match this role with l13)
- `panel = <&display_panel>` - inert for this driver (it never reads it)
- address **0x01**, not 0x62 (per-board; the driver uses `client->addr` verbatim)

Applied the rail part: our panel's bias is `pm6150l_lcdb` (its own avdd/avee), so touch `vcc-supply`
was moved from `vreg_l7e_3p0` to `&pm6150l_lcdb` (phandle verified = regulator@ec00). DTB-only change.
Boot (`touch19`): **still `-6`**, `probe 0x62: NO ACK`.
`regulator_summary` shows lcdb enabled with 2 voters (`ae94000.dsi.0-avdd`, `-avee`) and reporting
0mV - i.e. LCDB is up but exposes no voltage, so it is not a measurable 3 V source for the touch. The
touch's own votes are absent because the driver releases its enables when probe fails.

So the panel-bias theory is dead too, and with it the last vendor-informed idea available in software.

## 2026-10-25 - touch: driver-side variables exhausted

### High-Z reset (vendor parity) - negative
The working kernel has gpio 88 `MUX+GPIO UNCLAIMED` (nothing drives it, hardware pull decides).
Tried exactly that: driver requests the GPIO `GPIOD_ASIS` and never writes it in probe; DTS pinctrl
reduced to `function="gpio"` + `bias-disable` (no output property, no bias). Result: still `-6`
(`Error reading from 0x78: -6` x20). Greeter unaffected (`phoc=3621 phrog=4261 dpms=On`).

### Everything tried on the driver/power side, all negative
| variable | states tried | result |
|---|---|---|
| reset polarity | ACTIVE_HIGH/output-low, ACTIVE_LOW/output-high | -6 both |
| reset timing | static level, 10ms assert+release pulse, never driven (high-Z) | -6 all |
| rails | dummy, l7e+l8e, l7e+l13a, l11e+l13a (killed eMMC), seven forced always-on, all rails (killed boot) | -110 -> -6, never ACK |
| probe retry | 1 read, 20 reads x 20ms | 20/20 NACK at 27ms spacing |
| driver present? | A/B with node `status="disabled"` | same NACK without the driver |
| bus identity | verified r10 `i2c-1 -> i2c@884000 -> novatek@62`; mainline `i2c-0` = same controller | correct bus |
| bus speed | 100k default, 400k | no change |
| reset pin state | output, input, high-Z | no change |

`0x68` ACKs on the same adapter on every boot; `0x62` never does. The chip is electrically present
(no ENXIO timeout hang) but refuses its address.

### Board topology (new detail)
The touch node comes from the **IDP reference design**, `sm6150-idp.dtsi` includes
`sm6150-novatek-i2c_f7b.dtsi` - there is no violet-specific touch node. Pin layout is one connector:
panel reset `tlmm 91`, panel TE `tlmm 90`, touch reset `tlmm 88`, touch IRQ `tlmm 89`. Panel rails come
from `dsi_panel_pwr_supply`; the vendor's commented-out touch `vcc_i2c` was `pm6150_l13`, which r10
names as the **dsi-display** rail.

### Where the answer must be now
No software-visible enable remains. Either
1. the touch's VDD comes from something mainline cannot see (load switch / PMIC GPIO / panel module
   boost that only the ABL or the vendor panel driver turns on), or
2. the controller needs the panel's power-up *sequence* (VDD -> VDDIO -> reset deassert with timing)
   before it will answer, which neither a static pin nor a pulse from the touch driver reproduces.
Telling 1 from 2 needs a measurement at the connector on a mainline boot vs an r10 boot, or an ABL
boot (blocked by the DTB refusal above).

### ABL refusal: identity is NOT the cause (new, rules out the obvious)
Extracted the DTB that ABL *accepts* from `images-r9/boot-r10.img` with `unpack_bootimg`:
- it is a single FDT (magic `d00dfeed`, 630728 bytes), not a qcdt table
- root props: `qcom,msm-id = 163 0`, `qcom,board-id = 22 0`, `qcom,msm-name = "SM6150"`
- root also has `model`, `compatible`, `#address-cells`, `#size-cells`, `interrupt-parent`

Ours (as patched by `mk-bootimg.sh`) is `qcom,msm-id = 163 0`, `qcom,board-id = 22 0` - identical.
Also confirmed: **neither image carries AVB** (`AVB0`/`AVBf` absent in both, both start with `ANDROID!`),
so AVB is not the discriminator either.

Remaining differences that could matter, in order of plausibility:
1. vendor DT is 630KB vs our 91KB - it declares the full PMIC/regulator/interconnect set the ABL may
   sanity-check or overlay against;
2. DTB size/placement (`dtb_offset` 0x01f00000, header v2 with dtb - both images use it);
3. the dtbo overlay application (needs `__symbols__` in our DT *and* targets that exist).

**No further software inference is possible**: ABL prints nothing on the panel (splash + "powered by
android" then fastboot) and never hands off (pstore still holds 4.14 vendor output, so our kernel never
ran). Diagnosing this needs UART on the board, or a byte-level diff of the two headers - not more boots.

## 2026-10-25 - tried the real-ABL-boot route again: blocked (known), phone restored

Goal was to test whether a real ABL hand-off (rather than kexec) is what the touch controller needs.
Built `boot-mainline.img` from the current kernel + DTB with `mk-bootimg.sh` and flashed it to `boot`
twice (once with `__symbols__`, once without). **Both were refused by ABL**: the device drops straight
back to fastboot (`18d1:d00d`, serial `cb0bdec5`) and never exposes USB.

That re-confirms the 2026-10-13 result already recorded above: *"ABL accepts our kernel outright; our
device tree is the sole blocker"*. Everything listed there was already matched (PE header/CONFIG_EFI,
msm-id/board-id, text_offset 0x80000, code0/code1, memory node named `memory`, __symbols__, applyable
replacement dtbo, vendor reserved-memory map) and it is still refused.

**The screen is repaired now**, so unlike when this was first found, ABL's refusal message can simply be
read off the panel - flash a refused image and watch the display instead of guessing.

Conclusion: **a real ABL boot of mainline is not available yet**, so the kexec hypothesis for touch
cannot be tested. Touch work continues on kexec.

Notes made along the way:
- `fastboot fetch` is unsupported on this ABL, so the boot partition cannot be backed up over fastboot.
  The revert image is `~/violet-pmos/images-r9/boot-r10.img` (66621440 bytes); the partition is 64MiB,
  so the saved file is the same content plus padding - the sha mismatch is size, not corruption.
- busybox `reboot` silently ignores the `bootloader` argument, and `reboot(2)` with
  LINUX_REBOOT_CMD_RESTART2 + "bootloader" returns EINVAL on both r10 and mainline. Entering fastboot
  needs the physical Power+Vol- combo.
- Nothing was written except the `boot` partition; `dtbo`, `misc`, `vbmeta` and userdata untouched.
- Restored afterwards: `fastboot flash boot images-r9/boot-r10.img` -> r10 (`4.14.356-openela-rc1-perf`)
  up again at t=20s.

### Next touch experiment (building)
Vendor parity on the reset pin: the working kernel has gpio 88 **MUX+GPIO UNCLAIMED** (high-Z, hardware
pull decides). Mainline has only ever driven it as an output, in both polarities, plus a pulse. Patched
`novatek-nvt-ts.c` to request it `GPIOD_ASIS` and not write it during probe, and the DTS pinctrl state
to `bias-disable` with no output property - i.e. the same electrical state the working kernel has.

## 2026-10-25 (later still) - touch: what is ruled out, and the kexec hypothesis

### Confirmed, so it stops being re-litigated
- Bus identity is right: on r10, `i2c-1 name=Geni-I2C of=i2c@884000` and
  `/sys/bus/i2c/devices/1-0062/of_node -> /soc/i2c@884000/novatek@62`. Mainline's `i2c-0` is the same
  controller (its `0-0062` device is the one from the board DTS). No bus mix-up.
- The working kernel does **not** drive the touch reset: vendor pinctrl debugfs on r10 reads
  `pin 88 (GPIO_88): (MUX UNCLAIMED) (GPIO UNCLAIMED)` - nothing claims it. Pin 89 is claimed only
  as an irq (`3000000.pinctrl:89`).
- Vendor driver does nothing either: `NVT_TOUCH_SUPPORT_HW_RST 0` and the `vcc_i2c` regulator block
  is `#if 0`. So the working state is created entirely by the ABL / hardware defaults.
- Userspace scanning cannot be validated on r10: the vendor GENI driver refuses i2c-dev transfers
  (`errno=107 ENOTCONN`) on the very bus the driver is using. On mainline i2c-dev works, so a NACK
  there is a real measurement.
- A/B v2 (rails forced on, `status = "disabled"`, mainline touches nothing): `0x62` still NACKs while
  `0x68` ACKs. So neither the driver's reset handling nor missing rail votes explain it.
- Forcing `regulator-always-on` on **every** rail kills the boot: console stops at 0.236s inside RPMh
  regulator init (`ldo1: Setting ...`, `smps1: Setting ...`, then dead). Never do that again; the
  seven-rail set (l7e, l9e, l10e, l17a, l18a, l19a, l16a) is the most that survives.
- The novatek probe retry patch works as intended (fired 20x, 27ms apart, all -6). The part simply
  never answers, so "the chip is slow" is dead as a theory.

### Test in flight
Driver now pulses reset (assert 10ms -> release) instead of leaving a static level, on the theory
that this TDDI needs an edge rather than a level.

### If the pulse fails: the kexec hypothesis
Every measurement so far has been taken on a **kexec** boot, which skips everything the ABL does at
power-on - and the vendor kernel works only because of ABL/hardware defaults. If the panel/touch is
brought up by the bootloader (TDDI: the controller sits in the panel module and shares its reset
domain), a kexec'd mainline may never see it awake no matter what the driver does.
Next step then would be a real ABL boot of mainline (flash a boot image instead of kexec), so the
normal power-on init runs, and re-check whether `0x62` ACKs.

## 2026-10-25 (later) - touch: power was the wall; -110 became -6

### Correction: the stalled boot was NOT the touch chip
The touch10 boot died in initramfs with

    [pmOS-rd]: initramfs version: 3.12.5-r0
    mmc0: Card stuck being busy! __mmc_poll_for_busy     (repeating forever)

pstore (`console-ramoops-0`, 75809 bytes) shows userspace started fine and then the **eMMC** died.
Cause: the touch node had been given `vcc-supply = <&vreg_l11e_2p9>`, and the r10 regulator summary
names that rail's consumer outright:

    pm6150l_l11  2950mV  use=1  ->  7c4000.sdhci        <- this is the eMMC supply
    pm6150_l12   1800mV  use=1  ->  7c4000.sdhci
    pm6150_l13   1800mV  use=1  ->  soc:qcom,dsi-display
    pm6150_l11   1800mV  use=2  ->  88e2000.qusb
    pm6150_l17  3075mV   use=3  ->  ae90000.qcom,dp_display, usb-pdphy
    pm6150l_l7  3000mV   use=0  ->  deviceless (vendor DT marks it regulator-always-on)

The novatek probe failed, devm released the supplies, and the eMMC's rail went down mid-boot.
**Rule: never claim vreg_l11e_2p9 as a touch supply.** Nothing in the vendor summary has a touch
consumer at all, because the vendor driver models nothing (see below).

### Vendor driver reality (nt36xxx.c, nvt_touch_f7b)
- `nt36xxx.h:81: #define NVT_TOUCH_SUPPORT_HW_RST 0` -> the reset GPIO code is compiled out, so the
  vendor **never drives gpio 88**. The chip is out of reset by hardware/ABL default alone.
- The whole `vcc_i2c` regulator block is `#if 0` ("modify disable vcc_i2c ... 2018-09-25").
- It msleeps 10ms after POR, then calls `nvt_ts_check_chip_ver_trim()`, whose early transfers FAIL
  (`CTP_I2C_WRITE error, ret=-107` x3-4) and only then succeed, ~100ms in.

### A/B that cleared the driver of blame
With `touchscreen@62 { status = "disabled"; }` (mainline touching nothing: no reset drive, no rails),
`0x62` still did not ACK while `0x68` did. So the driver was not what kept the chip silent.

### What actually changed the error
Keeping every plausible supply rail on (`regulator-always-on` on vreg_l7e_3p0, l9e, l10e, l17a,
l18a, l19a, l16a) changed the probe error from

    Error reading from 0x78: -110   (ETIMEDOUT - the controller drags SDA, no power behind it)
to
    Error reading from 0x78: -6     (ENXIO - prompt address NACK: the IO side is now powered
                                     and the bus talks to a live but silent chip)

Mainline's `regulator_init_complete()` powers down rails the firmware left enabled but that nothing
claims, which is precisely the touch's situation. Both reset polarities give -6 afterwards, so the
pin level is not what gates it (consistent with the vendor never driving that pin at all).

### Test in flight
Patched `novatek-nvt-ts.c` probe to retry the `0x78` parameter read 20x with 20ms gaps (~400ms)
instead of a single attempt after one 100ms sleep, mirroring the vendor's retry behaviour.
Rebuilding Image; next boot will tell whether the part was simply slow to answer.

## 2026-10-25 - greeter comes up on mainline unaided (evdev built in)

Rebuilt the kernel with `CONFIG_INPUT_EVDEV=y` and `CONFIG_FUSE_FS=y` (were `=m`, and no modules are
installed for this kernel at all). New `Image` 32020488 bytes, LTO relink ~25 min.

First boot afterwards, with **nothing done by hand** (no insmod, no manual greetd start):

    phoc=3613  phrog=4251  greetd=3464   rc-service greetd: started
    /dev/input/event0 present            /dev/fuse present
    dpms=On  enabled=enabled             loginctl: session for uid 108 on seat0/vc7

So the greeter now starts itself at boot. The earlier blank screen on mainline boots was exactly
this: greetd started, phoc died on `libinput initialization failed, no input devices`, nothing was
ever drawn. Any "phosh is up" result before this depended on a manual `insmod evdev.ko` after boot.

Remaining: **touch**, so the greeter cannot be operated yet (only pm8941_pwrkey is registered; the
Novatek controller still does not answer - see the section above).

### Harness fixes worth keeping
`kexec-test.sh`'s `phone()` picked `first fe80 in ip neigh` after `ping -c1 ff02::1`, which returns the
host's own reply and leaves stale link-locals from earlier boots in the table - so runs kept firing at
a dead address and silently never kexec'd ("Cannot find device ..."/ssh timeout, no console file).
It now pings with `-c2` and validates each candidate by actually ssh-ing to it.

## 2026-10-25 - touch: bus up, chip silent (open)

### What works now
`&qupv3_id_0` + `&gpi_dma0` enabled in the board file -> the SoC GENI I2C bus finally exists:

    /sys/bus/i2c/devices/i2c-0, device 0-0062
    geni_i2c 884000.i2c: Bus frequency not specified, default to 100kHz   (now overridden to 400k)

So the earlier "no i2c adapters at all" was purely the disabled QUP wrapper, and the vendor's
`qupv3_se1_i2c` really is `i2c@884000`, so the node is on the right bus at the right address.

### What is still failing
    novatek-nvt-ts 0-0062: Error reading from 0x78: -110
    novatek-nvt-ts 0-0062: probe with driver novatek-nvt-ts failed with error -110

`-110` is ETIMEDOUT, and a raw bus scan from userspace agrees: `tools/i2c-scan.py` ACKs **0x68**
(an undeclared device on that bus) but never 0x62. So the bus, its power and its pull-ups are fine
and the touch controller itself is not responding.

Tried and ruled out, one boot each:
- reset polarity both ways: `GPIO_ACTIVE_LOW` (logical 0 -> physical HIGH, which is what the vendor
  drives) and `GPIO_ACTIVE_HIGH` (physical LOW). Same -110 either way.
- explicit pin mux for gpio88 (`output-high`) and gpio89 (`input, bias-pull-up`).
- real rails instead of the regulator-fixed dummies: `vcc-supply = <&vreg_l7e_3p0>` (the vendor's
  always-on L7C, 3.0V) and `iovcc-supply = <&vreg_l8e_1p8>`. The driver enables them and releases
  them on failure (`ldo7` shows use=1, `ldo8` use=0 in regulator_summary).
- `clock-frequency = <400000>` on i2c1.

Vendor ground truth worth keeping:
- `sm6150-novatek-i2c_f7b.dtsi`: `novatek,reset-gpio = <&tlmm 88 0x00>`,
  `novatek,irq-gpio = <&tlmm 89 0x2001>`, and `//vcc_i2c-supply=<&pm6150_l13>` **commented out**.
- `nt36xxx.c` only logs `novatek,irq-gpio` at parse time, meaning the reset-gpio path is compiled
  out (`NVT_TOUCH_SUPPORT_HW_RST`), so **the vendor never drives reset 88** - the chip is simply
  left running by hardware/firmware.
- Vendor boot log shows `CTP_I2C_WRITE ... ret=-107` three to four times, then a successful chip-ID
  read (`buf = 0A 00 00 72 66 03`, "This is NVT touch IC") about 100 ms later. So the controller
  answers on the vendor kernel, after early transport errors.
- The vendor's only regulator is `vcc_i2c` at 1.8V from `pm6150_l13`, and it is not modelled, so no
  rail is voted by the vendor driver either.

### Caveat on the userspace scan
`i2c-scan.py` against r10's own buses returns -110/-107 for 0x62 as well, so `/dev/i2c-N` on the
vendor kernel does not reach the controller the driver is using. Do not read a clean "no ACK" on
mainline as absolute proof the part is dead - but combined with the driver's own -110 it is good
evidence the controller is not currently answering.

### Next candidates, cheapest first
1. gpio88 may not be reset at all (vendor ignores it) - maybe a power enable or unrelated. Try the
   node with reset-gpios pointing at a pin we know is harmless, to see if driving 88 is what stops
   the chip from answering.
2. Rails not yet tried as `vcc-supply`: `vreg_l5a_2p5`, `vreg_l16a_2p4`, `vreg_l17a_3p0`,
   `vreg_l18a_3p0`, `vreg_l19a_2p7`, `vreg_l9e_2p9`, `vreg_l10e_3p2`, `vreg_l11e_2p9`.
3. Compare `regulator_summary` on r10 and mainline line by line for rails that are on in one and
   off in the other; that diff was never completed.

## 2026-10-24 (late) - phosh runs on mainline; touch needs the QUP wrapper enabled

### CONFIG_INPUT_EVDEV=m was the whole phosh blocker
`greetd` "crashed" and phoc died with `libinput initialization failed, no input devices`.
Not a seat problem: the boot-time greeter log proves mainline gives exactly what r10 gives -
`XDG_SESSION_ID=c1`, `cgroup 0::/c1`, `Seat: seat0; vc7`, `Class: greeter`. Earlier "no backend
was able to open a seat" readings were the greeter inheriting an **ssh session's cgroup**
(`0::/c11`, `Service: sshd`) whenever greetd was launched from a shell, including via
`rc-service greetd start` (OpenRC runs the init script in the caller's context).

Cause: `CONFIG_INPUT_EVDEV=m` and **no mainline modules installed** - `/lib/modules/` contains only
`4.14.356-openela-rc1-perf`, so all 663 `=m` drivers in this config are absent at runtime. With no
evdev there is no `/dev/input/` at all; `pm8941_pwrkey` had `Handlers=kbd` with no `eventN`.

Proof: built `drivers/input/evdev.ko` from the same tree (`vermagic 7.2.10-sm6150`), `insmod` ->
`/dev/input/event0` appeared. Started greetd from a fresh cgroup (`tools/seat-test.sh`) ->
`phoc=17479 phrog=17620`, `dpms=On enabled=enabled`, and the session held for 196 s with DPMS
cycling On->Off->On->Off on idle blanking and **no SoC wedge**.

Durable fix: `CONFIG_INPUT_EVDEV=y` and `CONFIG_FUSE_FS=y` (fuse only feeds glycin/portal).

### Touch: two separate bugs, both now addressed
1. Board DTS enabled `&i2c1` but not its parent - `qupv3_id_0: geniqup@8c0000` is `status =
   "disabled"` in `talos.dtsi`. A child of a disabled bus is never instantiated, which is why
   `/sys/bus/i2c/devices/` was completely empty and there was no `i2c-1`. Now the board sets
   `&qupv3_id_0 { status = "okay"; }` and `&gpi_dma0 { status = "okay"; }` (i2c1's dmas point at it).
2. The touch node itself: vendor DT `/soc/i2c@884000/novatek@62` (compatible `novatek,NVT-ts`,
   reg 0x62, irq gpio 89, reset gpio 88, **no supplies**) vs mainline's `novatek-nvt-ts` which
   requires `vcc` + `iovcc` by name -> two `regulator-fixed` always-on rails stand in for now.

DTB builds and validates; probe still unobserved because every boot since has died for an unrelated
reason (below).

### Rule: kexec mainline -> mainline does not boot
The only kexec that reliably works is **r10 -> mainline**. Firing `kexec-test.sh` while the phone is
already on mainline gives a dead boot with no USB, no interface and no console file (seen again on
the touch5 run). Always cycle back to r10 first, then kexec.

## 2026-10-24 (evening) — seat blocker isolated, touch node added

### The greeter blocker is a seat/session problem, not a hang
On mainline `greetd` sits in `status: crashed` and `phoc` dies instantly with
`libseat: No backend was able to open a seat` / `Unable to create seat: Function not implemented`.
Same rootfs, same greetd, same PAM, same config on r10 gives a working session:
`c6 uid=108 greetd seat0 tty7`, phoc 6848, phrog 6981.

Instrumented the greeter (`/usr/local/bin/phrog-logged.sh`, wired via
`/etc/phrog/greetd-logged.toml`, original kept at `/etc/conf.d/greetd.bak`) and caught it:
when greetd is launched from an ssh shell — including via `rc-service greetd start`, because
OpenRC runs the init script in the caller's context — the greeter inherits **my ssh session**:
`0::/c11`, `XDG_SESSION_ID=unset`, and `loginctl session-status` describes c11 as
`Service: sshd / Class: user / Leader: sshd-session`. `pam_elogind` therefore sees an existing
session and never creates one on seat0, so phoc gets a session with no seat.

Ruled out on mainline: `/dev/tty7` is greetd-owned, `active vt: tty7`, `seat0` does list
`drm:card0 [MASTER]`, `greetd-greeter` PAM has `pam_elogind.so` (a duplicate line was added by
mistake and restored), and the kernel has CGROUPS/CPUSETS/MEMCG/NAMESPACES/VT/FRAMEBUFFER_CONSOLE
built in. `CONFIG_FUSE_FS=m` is why `/dev/fuse` is absent — unrelated, worth `=y` later.

Consequence: **no phosh/phrog session has actually run on this tree.** Every "survived N minutes"
run had `phoc=`/`phrog=` empty. The only valid seat test is the boot-time path, so greetd now
launches the instrumented wrapper at boot and writes `/tmp/phrog-session.log` before phoc starts.

### Touch: DT node added, probe still unverified
Vendor node read off a working r10 boot: `/soc/i2c@884000/novatek@62`, `compatible "novatek,NVT-ts"`,
`reg 0x62`, irq gpio 89, reset gpio 88, and **no supply properties at all**. mainline's
`novatek-nvt-ts` requires both `vcc` and `iovcc` by name, so the board file got two
`regulator-fixed` always-on rails (they vote nothing; replace with the real LDOs when known).

    i2c@884000 == i2c1 in talos.dtsi, qup_i2c1_data_clk pinctrl already on the SoC node
    touchscreen@62 { compatible "novatek,nt36672a-ts"; interrupts <89 EDGE_FALLING>;
                     reset-gpios <&tlmm 88 ACTIVE_LOW>; vcc/iovcc }

DTB builds and `dt-validate` rc=0; node verified in the binary. **Probe not yet observed.**
The two boots that were supposed to test it did not fail at the probe — `kexec-touch.log` shows
`after: EN=3 BARK=ffffe BITE=fffff`, i.e. the APSS watchdog was armed and bit at ~32 s, killing
eMMC. Two lessons, again: always `WDT=off` for observation runs, and a console ring that stops at
`udevd`/switch_root says nothing about drivers that probe after userspace starts — use live
`sudo dmesg` for those.

### Failure modes now distinguishable
- ring holds only r10's tail, last line `kexec_core: Starting new kernel` → mainline produced **zero**
  output; kexec jump itself failed (seen once).
- ring ~700 lines ending at `udevd` on switch_root → mainline reached userspace, then died.
- live kernel answers but `pidof phoc` empty → session/seat, not a hang.

## 2026-10-24 (later) — GPU + display together; phosh greeter hard-hangs mainline (OPEN)
**Working:**
- Display from boot (prefetch fix), GPU (freedreno FD612, GLES 3.2, eglprobe 5/5) at the same time.
- Display + GPU as ONE DRM device (ginkgo style): boot WITHOUT `msm.separate_gpu_kms=1` -> card0 has
  DSI-1 + renderD128, "bound 5000000.gpu". Use this from now on.
- Big console font: CONFIG_FONTS=y, CONFIG_FONT_TER16x32=y + cmdline `fbcon=font:TER16x32`.
- r10 GPU firmware step: r10's PIL looks for a612_zap.mdt/.b0x in /lib/firmware (top level), was only in
  /lib/firmware/qcom/ after the Elixir restore -> copied; kgsl_open OK again.
- New helper: `ml-boot.sh <tag> [phoc]` (kgsl on r10 -> kexec, one DRM device, big font, optional bare
  phoc via greetd). Scripts now auto-detect the USB interface (it moved from enp0s20f0u4 to u1).
- strace 7.2 + libdw installed on the phone (from Alpine edge/main).

**Open blocker: starting phrog (phosh greeter) hard-hangs the SoC ~20-40 s later.**
- Hard hang: ping to the phone stops; kernel log (dmesg -w over a pre-opened ssh, pstore, on-disk copy every
  2 s) shows NOTHING at the hang; no oops/lockup/RCU message; watchdog later resets to r10.
- Happens with GPU and without GPU (GPU init failed), with separate or one DRM device.
- NOT the cause (each tested alone on mainline for >=60 s, all fine): bare phoc (11+ min), DPMS off/on via
  wlopm, backlight 0/1024, gsd-power, wayvnc, udisksd, upowerd, feedbackd, callaudiod, gvfs gphoto2/afc/mtp
  monitors, goa-daemon, 60 vblank waits (16.7 ms), 2700 legacy page flips of dumb buffers, 400 MB eMMC
  write + 20k file reads, mdp_lut_clk on, rot_clk on.
- phrog's own syscalls before the hang are harmless (reading .desktop files). Session D-Bus activations, in
  order: gvfs Daemon, a11y Bus, CallAudio (never reports success), Feedback, dconf, atspi Registry, gvfs
  Metadata, UDisks2/MTP/Goa/GPhoto2/Afc volume monitors, OnlineAccounts, Identity; system side: upowerd,
  udisksd, accounts-daemon, xdg-desktop-portal(-phosh), evolution, gnome-calls, gnome-contacts; glycin image
  loaders via bwrap.
- phoc during phrog: ~63 DRM_IOCTL_MODE_ATOMIC commits, each with a 16-byte CREATEPROPBLOB (likely
  FB_DAMAGE_CLIPS), then the hang. Next idea: drm.debug=0x116 atomic-state dump streamed live to see the
  last commit's planes/properties; and DeepSeek research (prompt given to the user).
- Config hygiene: greetd stays on the stock config (/etc/phrog/greetd-config.toml restored after a crash had
  emptied it; a crash also emptied a wrapper -> always `sync` after writing on the phone).

## 2026-10-24 — DISPLAY WORKS on mainline: the DSI stall was the DPU prefetch start
- Root cause: DPU 5.x needs the programmable fetch to start one line later than mainline programs it.
  Vendor sde_encoder_phys_vid.c: `if (m->delay_prg_fetch_start) vfp_fetch_start_vsync_counter += horiz_total;`
  (set for SM8150, SC8180X, SM7150, SM6150, SM6125, Atoll). Our mode needs wc 24 - (vbp 8 + vsw 3) = 13
  fetch lines = the whole VFP, so mainline started the fetch on the first line after active
  (0x2e5935); r10 uses 0x2e5e41 (+1292 = one line). Symptom: DSI MDP FIFO over/underflow from the first
  frame, lanes back to STOP (0x1f0f), DSI dynamic pclk/byteclk never active.
- Found via the ginkgo lead (item 0 below): first by clearing INTF_CONFIG bit31 live, which turned the
  link healthy instantly (FIFO 0x1010, LANE 0x1f00, CLK 0x9047c3 = r10); the user saw the colour test.
- Fix: dpu_encoder_phys_vid.c programmable_fetch_config(): add horiz_total when
  hw_intf->mdss_ver->core_major_ver == 5. Clean boot: 0 FIFO errors, prefetch on, start 0x2e5e41,
  all DSI status = r10.
- Real fixes to keep (besides this): LCDB regulator driver, DSI vdda = l3e (1.232 V), PHY rail l4a
  925 mV, PHY LDO 0x1c, lane swap <1 2 3 0>, HS_TIMER_CTRL 0x3fd08, PLL ICP 0x3f, upstream byte-clock
  rounding. To re-check one by one when cleaning up: deferred video-engine enable, DSI PHY reset BIT(24),
  TPG/DMA_FIFO_CTRL/TRIG_CTRL tweaks, 288 MHz MDP clock + forced max core clk, dispcc table.

## 2026-10-24 — touch enabled on r10 (downstream pmOS)
- Touch was disabled on purpose by `/etc/udev/rules.d/90-violet-disable-touch.rules` (from package
  device-xiaomi-violet-1-r8: `LIBINPUT_IGNORE_DEVICE=1` for "NVTCapacitiveTouchScreen", added while the
  panel was broken). Renamed to `.disabled`, udev reloaded, greetd restarted -> touch works in phosh/phrog.
  NOTE: a device package upgrade will reinstall the rule; drop it from the package in pmaports.
- The NVT driver requests `novatek/shenchao_nt36672a_miui_f7b.bin`; installed it from the downstream tree
  (`~/violet-pmos/kernel/firmware/novatek/*.ihex`, objcopy -I ihex -O binary) into
  /lib/firmware/novatek/. Its flash update still fails (Resume_PD write-enable I2C NACK) but the chip runs
  its own flash firmware and reports touches; the file is probably not required.
- Elixir's vendor lives in `super`; the old `vendor` partition (p86) has a corrupt root dir.
- Mainline touch (later): chip is NT36672A on qupv3_se1 I2C 0x62, irq gpio 89, reset gpio 88; mainline
  driver novatek-nvt-ts ("novatek,nt36672a-ts") exists.

## 2026-10-23 — display: panel repaired; LCDB driver, DSI fixes; video handoff still stalls
**Status at end of day:** the panel now lights up under mainline (grey-white), but shows no picture: the DSI
video engine never transmits the DPU's pixels (video FIFO overflows from the first frame, lanes stay idle).
Fixed today: panel power (new PM6150L LCDB regulator driver), DSI PHY LDO 0x1c, lane swap (`data-lanes = <1 2 3 0>`),
HS_TIMER_CTRL 0x3fd08. Debug code is still in the tree (listed under point 7 below; point 8/9 add a TPG clear, DMA_FIFO_CTRL and TRIG_CTRL test). Next: replicate the
downstream DSI/INTF enable ORDER.

Setup: Elixir was flashed for the repair; pmOS restored (fastboot: dtbo/vbmeta/misc from
device-backup/pre-elixir-2026-10-18, boot-r10.img, rootfs-r9.img, then extras tar). Note: the r10
"kgsl_open" step timed out on the first boot after restore (GPU not up on mainline that boot).

Ground truth: r10 shows the pmOS login screen, so panel + rails are fine; mainline-only problem.
Mainline greetd crashes (no GPU), so only fbcon/fb0 tests apply.

Findings (in order):
0. LEAD from ginkgo (relayed from a side session, 2026-10-24): github.com/rafitadev/GinkgoMainlineAndroid
   (Redmi Note 8, SM6125/DPU 5.4, NT36672A 1080x2340, 4-lane video, DSI 6G v2.3, 14nm PHY, mainline
   DPU+DSI) went from "backlight, no image" to pixels on 2026-08-17. Their FIFO notes match ours:
   0x55551011/0x55551019 = HS FIFO empty (often with STOP); 0xdddd1011 = HS already dropped to STOP;
   0xcccc1019 = MDP over+underflow + 4-lane HS over/underflow -> prefetch / dual-engine mismatch.
   Healthy: FIFO 0x1010, LANE_STATUS 0x1f00, CLK_STATUS 0x9047c3 (= r10). Tests, in order:
   (1) prefetch: ginkgo prefetch on -> 0x1010 for 21 ms then 0xcccc; prefetch off -> fine. INTF_1
       CONFIG bit31 (0xae6b804 0x80800000) is the prog-fetch enable (set on BOTH kernels); start
       0x170 differs by exactly 1 line (1292). wc_lines 24 > vfp 13 on violet.
   (2) their 14nm hs_cycle: DSI_EN low -> CLK_CTRL |= DYNAMIC_FORCE_ON -> LANE_CTRL bit24=1, clear DLN
       force-stop -> hold SOFT_RESET 20 ms -> CLK_CTRL 0x23f -> DSI_EN=1, wait 20 ms.
   (3) drop our DSIDBG sw-reset-on-FIFO-error hack (a sw reset in video mode wrecks the FIFO).
   (4) one boot in non-burst sync-event mode (VID_CFG0 0x9130), their only end-to-end config.
   Repo files worth reading: ginkgo-dsi-err-status5-analysis.md, thinking.md,
   scripts/display-bringup-loop.sh. Use their numbers as reference only (DPU 5.4 vs our 5.3).

1. Panel answers DCS reads on mainline: power mode 0x9c (booster, sleep-out, normal, display on).
   NB: a BTA read in prepare triggered a DSI error storm + reset -> removed.
2. DSI error bits (NOT underflow as first thought; status=5 = TIMEOUT|FIFO):
   fifo_status 0xdddd1011 (video MDP FIFO overflow, per-lane HS FIFO over/underflow), timeout_status 1.
   Error irq stormed (~16k/s) after the panel repair -> watchdog reset at ~16 s.
3. r10 vs mainline DSI register diff (debug-backup/dsi_r10.txt vs dsi_mainline*.txt):
   - PHY CMN_LDO_CNTRL: r10 0x1c, mainline 0x3c (pll_db_commit_14nm hardcodes the MSM8996-rev2 value;
     downstream uses 0x3c only for 8996 rev2). FIXED -> 0x1c (dsi_phy_14nm.c). Not sufficient alone.
   - LANE_SWAP_CTRL: r10 1, mainline 0. FIXED via data-lanes = <1 2 3 0> (mainline maps the inverse
     permutation: <3 0 1 2> gave 3). Stopped the error storm.
   - HS_TIMER_CTRL: mainline never programs it (0xffff); downstream writes 0x3fd08. FIXED in
     dsi_host.c (VID_CFG0 setup). HS TX timeouts gone.
   - lane TIMING_CTRL_5/6/9 differ by 1 (0x21/0x09/0x02 vs 0x20/0x0a/0x03), PLL 0x8b4/8b8 differ: open.
4. Panel analog rails: PM6150L LCDB (SID 5, 0xEC00) was OFF on mainline (ENABLE_CTL1=0, no VREG_OK);
   r10 switches it off before kexec. NEW driver drivers/regulator/qcom-lcdb-regulator.c
   ("qcom,pm6150l-lcdb": MODULE_EN 0x46 bit7, poll INT_RT_STS bit0); panel avdd/avee -> &pm6150l_lcdb.
   Result: screen went from black to uniform grey-white (panel powered, no valid video).
5. DSI test pattern (msm.dsi_tpg=1 debug switch): link runs exactly like r10 (FIFO 0x1010, lanes
   active 0x1f00, CLK_STATUS dyn pclk/byteclk on) -> DSI host/PHY/HS path works; screen black
   (pattern likely black). With the DPU feeding it: lanes idle (0x1f0f), dyn pclk off, FIFO overflow.
   => fault is DPU INTF_1 -> DSI video handoff.
6. DPU INTF_1 is at 0xae6b800 (catalog offsets are relative to 0xae01000). HAZARD: /dev/mem read of
   0xae6a800 (= INTF_0, DP, unclocked) hangs the SoC. INTF_1 diff r10 vs mainline: only CONFIG2
   DATA_HCTL_EN + DISPLAY_DATA_HCTL (mainline sets, r10 0). Disabling it: no change (reverted).
7. MDP core clock: dispcc table 256/307 entries all /3 of a fixed 576 MHz PLL -> always 192 MHz
   (mode needs ~192.4). Forcing 288 MHz (table 192/288 + max core clk) removed the UNDERFLOW bit but
   the overflow + stall remain -> not the root cause (experiment still in tree).
Debug code currently in tree (remove before patches): DSIDBG/DSIREG/INTFREG in dsi_host.c,
msm.dsi_tpg in dsi_manager.c, forced core clk in dpu_core_perf.c, 288 MHz entry in dispcc-qcs615.c.
8. More negative results (2026-10-23, all with LCDB on): DSI sw reset after each FIFO error (overflow
   returns every frame); TPG_DMA_FIFO_MODE (TEST_PATTERN_GEN_CTRL bit2) was left set on mainline ->
   cleared to 0 in video setup, no change; byte_intf clock = byte/2 as downstream; DSI cfg entry
   (v2.3.0 -> sdm845_dsi_cfg) correct; r10 runs disp_cc_pll0 at 921 MHz / MDP 307 MHz but DSI PLL
   dividers equal to mainline.
   State: DSI and INTF_1 registers now match r10 except status/counters, ERR_INT_MASK0, TRIG_CTRL
   bit12 (BLOCK_DMA_WITHIN_FRAME), DMA_FIFO_CTRL (0x050: r10 0x00110000), MISR, lane TIMING_CTRL
   5/6/9 (+-1) and PLL 0x8b4/0x8b8. Symptom: DSI video FIFO overflows from the first frame, lanes
   stay in stop state, DSI dynamic pclk/byteclk never become active -> DSI video engine never starts
   transmitting DPU pixels (TPG path works). Next: log downstream's DSI/INTF enable write ORDER
   (sde/dsi-staging) and replicate; try the remaining register diffs (DMA_FIFO_CTRL, TRIG_CTRL bit12,
   lane timings).
9. DMA_FIFO_CTRL=0x00110000 + TRIG_CTRL without BLOCK_DMA_WITHIN_FRAME (both now equal to r10):
   no change. Remaining static diffs: ERR_INT_MASK0, MISR, lane TIMING_CTRL_5/6/9, PLL 0x8b4/0x8b8.
   => most likely an enable-ORDER / handshake difference, not a static register value.
10. Downstream enable ORDER traced on r10 (function tracer over a screen off/on; saved in
   debug-backup/r10_display_cycle_trace.txt): host_init (video_engine_setup, timing) -> ctrl_en ->
   PHY clamp -> HS clocks/PLL -> DSI soft reset -> panel reset + init cmds -> video_engine_en ->
   INTF setup_timing_engine/prg_fetch -> flush -> INTF enable_timing_engine -> backlight.
   Mainline set VID_MODE_EN before the panel cmds; now deferred to a new DSI bridge .enable
   (msm_dsi_host_enable_video: sw reset + VID_MODE_EN). First version wrongly also set CMD_MODE_EN
   (DSI_CTRL 0x1f7) and one boot hung before SSH; fixed (0x1f3). Result: no change in the stall.
   Also: INTF_1 runs at ~62 fps on mainline (frame counter advances); MDP_TOP equal except clock
   force-on/status and IRQ enables; DSI TIMING_DB_MODE is 0 on both (no flush needed).
   The pmOS splash the user saw was from an r10 reboot, not mainline. fb0 gets blanked (blank=4)
   during mainline boot.
11. More eliminations (2026-10-24): writing r10's PHY lane TIMING_CTRL_5/6/9 and PLL 0x8b4/0x8b8
   into a running mainline (tools/dsi_transplant.py) + display off/on: no change. DISP_CC compared
   (tools/dispcc_peek.py): byte0 divider 0x20d8 = 1 (byte_intf = byte/2) on BOTH; only difference
   disp_cc_mdss_rot_clk (0x2010) on in r10, off in mainline -> turned on + display off/on: no change.
   The VIDEO_MDP_FIFO_OVERFLOW bit is live (cannot be cleared): the DSI never pulls pixels from its
   input FIFO, while INTF_1 runs at ~62 fps and the TPG path transmits fine.
12. DTS bug: DSI controller vdda was <&vreg_l4a_0p8> (that is the PHY rail). Vendor: dsi_ctrl
   vdda-1p2 = pm6150l_l3 (1.232 V), PHY vdda-0p9 = pm6150_l4. FIXED: vdda-supply = <&vreg_l3e_1p2>
   (now enabled, 1232 mV). refgen: vendor names a refgen core supply but sm6150 wires none (dummy OK).
   MDSS top (0xae00000) identical r10 vs mainline. Stall unchanged after the rail fix.
   PHY ULPS clamp (vendor phy_clamp_base 0xae01400 + 0x54) is 0 on both: not clamped.
13. DPU blocks compared (tools/dpublocks.py; HAZARD: reading unused/clock-gated pipes on mainline
   hung the SoC -> read only the active CTL_0/LM_0/PP_0/DMA0 there; r10 forces clocks on so all read
   fine): LM_0 and PP_0 identical; CTL_0 differs only by pipe choice (r10 scans out VIG0, mainline
   DMA0; DMA0 programmed 1080x2340). Full DISP_CC (0xaf02000-0xaf02200) identical except PLL0
   (921 vs 576 MHz), rot_clk(+src) and mdp_lut_clk off on mainline. => every static register in the
   path matches; the difference must be in sequencing / hidden state.
   PHY_SW_RESET with BIT(24)|BIT(0) like downstream (mainline sets only bit 0): no change (debug edit).
14. Clean hand-off test: on r10 stopped greetd and disabled all CRTCs via DRM SETCRTC(fb=0)
   (tools/drm_off.py; driver unbind is not allowed) before kexec -> identical stall. Not r10 leftovers.
   r10's own backlight was at 4095; halved (user is in a dark room: keep brightness <= 1024).
15. 2026-10-24 late: the "PLL 0x8b4/0x8b8/0x8fc" diffs are PLL_DIV_FRAC_START1/2 and PLL_ICP_SET.
   ICP: downstream icpmset=icpcset=7 (0x3f), mainline hardcodes 4<<3|4 (0x24) -> set 0x3f in
   dsi_phy_14nm.c (kept, matches downstream); FRAC differs by ~5 ppm (irrelevant). No visible change.
   Panel "all pixels on" (DCS 0x23, sent during init via panel_novatek_nt36672e.allon=1): screen stays
   black -> a video-mode panel needs a running video stream even for that. Runtime DCS writes time
   out (-110) because the stalled video engine never gives a BLLP window.
   LCDB block (0xec00-0xecff) is byte-identical r10 vs mainline (STS3/4 = 0 on r10 too).
   Order verified with logs: enable_video 0.832 s -> INTF_1 timing engine 0.853 s -> first FIFO error
   0.870 s. r10's force_hs_clk_lane skips clock-gating config. MDP clock is 288 MHz in all these runs.
   Full transplant of r10's DSI ctrl config into running mainline (tools/dsi_full_transplant.py):
   only DMA_BASE, MISR_VIDEO_CTRL, ERR_INT_MASK0 still differed; after copying + video restart: still
   stalled => the DSI controller config is identical; the cause is outside it (PHY/PLL hidden state,
   clocks, or DPU INTF output behaviour).
   Next ideas: port downstream's 14nm PHY + PLL enable sequence write-for-write; or a hand-off test
   where mainline does NOT re-init DSI/PHY/PLL and adopts r10's running link.
16. Step-back review (2026-10-24): checked upstream instead of only downstream. Found
   msm-fixes 6cd33b6f4155 "drm/msm/dsi: round 6G byte clock rate to the PLL-achievable value"
   (mainline re-applied the link clock before EVERY DCS command -> PLL re-lock each time; our
   drm.debug log showed exactly that during panel init). Backported into dsi_host.c (keep).
   Result: no clock re-sets during init any more, but the video stall is unchanged.
   Key reference: upstream qcs615-ride (same SoC, DSI0 video -> DSI-to-DP bridge, data-lanes
   <0 1 2 3>) is supported in this very tree, i.e. SM6150 DSI video mode works upstream. So the
   remaining differences to that working setup are: our panel (TDDI NT36672A), lane swap, the
   mode/clock, and kexec from r10. Next: diff our display DT/flags against qcs615-ride, and look
   for a cold-boot path to rule kexec out completely.
17. KEXEC RULED OUT (2026-10-24): blanking fb0 powers MDSS_CORE_GDSC fully off (pm_genpd: off-0,
   display-subsystem suspended); unblank re-runs the whole bring-up on power-on-reset hardware ->
   identical stall (fifo dddd1011, lanes idle). So mainline's own sequence breaks it from a clean
   slate. Also: DSI PHY rail PM6150 L4 raised to 925 mV (r10 value, was 880) - no change, kept.
   PLL start sequence (VREF_CFG1 0x10, CMN_PLL_CNTRL 1, poll lock+ready) identical to downstream.

## 2026-10-18 (late night) — display chain wired (panel still broken, picture unverifiable)
- Fixes needed: dispcc GDSC without HW_CTRL + XO branch always on (0007), DSI PHY supply `vcca` (0008), panel compat in binding (0009), panel mode flags video|burst|LPM (0006), board DTS display block (0001).
- Result on kexec boot: `card1-DSI-1` connected/enabled 1080x2340, `/dev/fb0` (msm-kmsdrmfb), WLED backlight, 5 harmless `dsi_err_worker` lines at init, stable. GPU still renders 5/5 cycles with display up.
- Not verifiable: actual picture (panel broken). The dispcc `power-domains` experiment was not needed and was removed.
- Open: LCDB for AVDD/AVEE, cold boot without kexec, upstream cleanup.

## 2026-10-18 (night) — repeat-power-cycle bug FIXED
Root cause: the RGMU GPUSTART OOB was released at the end of `hw_init()` (copied from downstream, where it is re-raised around GPU accesses). On this driver the
GPU is then left alone while powered, the RGMU power-collapses GX (IFPC) as soon as the GPU idles, and the next job runs on a GPU that lost its state, e.g. the CCU
then writes with the upper address bits dropped (`*** gpu fault ... iova=0xc08000` for a BO at `0x100c08000`). Fix (patch 0004): hold the OOB from resume until
suspend. Found with a `msm.rgmu_dbg` bitmask that disabled suspend/init steps one at a time (bus halt: irrelevant; RGMU slumber / GX handover: required, skipping
hangs the SoC; "don't clear OOB after hw_init": all runs pass). Verified on the clean patched tree: 5 consecutive EGL clears with idle gaps all return [64,128,191,255],
the GPU reports `suspended` when idle, Turnip enumerates. Open: display (DSI/panel), cleaning/upstreaming, booting without kexec.

## 2026-10-18 (evening) — repeat-power-cycle diagnosis; package builds
- **The package builds**: `pmbootstrap build linux-postmarketos-qcom-sm6150` (APKBUILD in `~/violet-pmos/pmaports/device/testing/`, copy in `pkg/`) produced
  `linux-postmarketos-qcom-sm6150-7.2.10-r0.apk` with `boot/vmlinuz`, `boot/dtbs/qcom/violet-sm6150.dtb`, `boot/config`, `kernel.release`. Not yet booted from that apk (still kexec).
- Freeze diagnosis: the "lockup" on 2nd+ power-ups was partly my fault: skipping the AHB fence for the RGMU (`fenced_write`) lost the GX wake-up. With the fence kept
  (patch 0004 updated) the failure becomes a **GPU SMMU TRANSLATION fault** (`*** gpu fault: ttbr0=... iova=0xc08000 dir=WRITE type=TRANSLATION source=CCU`) in the
  first job after a power cycle; the first power-up works. Ruled out: SRAM init (completes every cycle), SMMU context-bank registers (identical TCR/TTBR except the new TTBR0),
  the 99 GPU registers downstream writes at wake (identical every cycle, mainline differs from downstream in 18 but the same each cycle). Wide register dumps (0..0xc000)
  hang the SoC (RPMH timeouts): don't. Hypotheses left: first cycle relies on hardware state left by the downstream kernel that survives kexec (GMEM/CCU/UCHE related),
  or TLB/ASID handling after the SMMU loses power.

## 2026-10-18 (later) — tidy-up: clean patch series
The working changes are now a 6-patch series against vanilla 7.2.10 in `patches/` (verified with `patch --dry-run`, rebuilt, and re-tested on the phone: same
behaviour as the instrumented tree: first power-up renders, later cycles still lock up). Instrumented versions are in `debug-backup/`. `README.md` describes the workflow,
`pkg/linux-postmarketos-qcom-sm6150/` has the patches, final config and a DRAFT APKBUILD (untested). Dropped as not needed for the kexec route: the arm64 `head.S` PE/text_offset
hacks, the `-@` dtc flag, `dd.c`/`pinctrl-msm.c`/`qcom_scm*.c` debug prints, the scm bandwidth values and `auth_and_reset` experiment. Still in the DTS but only needed for the old
ABL experiments: vendor reserved regions, imem, `/firmware/android`, the `memory` node name.

## 2026-10-18 — MILESTONE: GPU renders on mainline (Mesa freedreno + Turnip on violet)

`vkprobe.py` => `Turnip Adreno (TM) 612`; `eglprobe.py` (surfaceless GLES) => `freedreno / FD612 / OpenGL ES 3.2 Mesa 26.2.4`, and a `glClear` +
`glReadPixels` returns the exact colour [64,128,191,255], i.e. the GPU executes command streams on 7.2.10-sm6150. What it took (all in the local tree):
- **Zap shader rejection (0xffcfffbb) = Linux enabling the TZ SHM bridge.** `qcom_tzmem_init()` calls `QCOM_SCM_MP_SHM_BRIDGE_ENABLE`; once on, TZ rejects every
  PAS_INIT_IMAGE whose buffer is not a registered bridge. Downstream 4.14 never enables it. Fix: add `"qcom,sm6150"` to `qcom_tzmem_blacklist[]`
  (log shows `SHM Bridge not supported`); then `PAS_INIT_IMAGE` returns 0. (sm7150/sm8150/sdm845 are already in that blacklist.)
- `bcm_acv` in `interconnect/qcom/qcs615.c` lacks `.enable_mask = 0x8` (downstream ACV vote is `0x60000008`). Real bug, fixed.
- scm bandwidth vote `icc_set_bw(path, 393600, 3936000)` (downstream `scm_pas`: ab=393.6 MB/s, ib=3.936 GB/s) via `&{/firmware/scm} interconnects = <&aggre1_noc MASTER_CRYPTO ... &mc_virt SLAVE_EBI1 ...>`.
- RGMU bring-up port (see "GPU power-up: SOLVED" above) + `adreno_has_rgmu()` in the GMU-less checks. GMU regs need `(reg<<2) - gmu->mmio_offset`.
- `msm.separate_gpu_kms=1` on the cmdline (no display master yet), firmware under `/lib/firmware/qcom/`.
**Known gaps:** (1) power cycling (runs 55-57): the first power-up renders correctly with NO runtime-PM forcing (pixel [64,128,191,255]). Matching the downstream
wake/slumber trace fixed `hw_init` on every cycle: OOB GPUSTART is cleared at the end of `hw_init` (so the OOB-set ack works in suspend); slumber = OOB set, bus halt, OOB clear,
`0x3c45` 1/2/0, power counter off, `0x23b82=1`, mask irqs, then, if `SPTPRAC_PWR_CLK_STATUS` bit6 is clear (GX still on), take GX with the CPU via `pm_runtime_get/put(gxpd)`.
Remaining: on 2nd+ cycles the first submitted job locks the GPU up (hangcheck, rptr 17 / wptr 81) although `hw_init` returns 0; some cycles `hw_init` returns in 0.4 ms
(suspicious). Suspects: per-cycle SMMU/pagetable (ttbr0) state, UCHE/hwcg re-programming, `needs_hw_init` paths, secure-mode packet on re-init.
(2) the very first init races the first client. (3) display: DSI PHY/panel not wired, `&mdss` oopses.
(4) everything is still debug-quality code (`GPUDBG`/`ZAPDBG`/`PROBE-START`/`TLMM-DIR` prints); needs cleanup + patches into a pmaports kernel package.
(5) boot path is kexec from the downstream kernel (ABL still refuses our DTB).

## 2026-10-17 — BREAKTHROUGH: mainline boots on violet via kexec from the downstream kernel (no ABL, no screen)

**Route:** r10 (= r9 + `CONFIG_KEXEC` + `CONFIG_DEVMEM`, flash only `boot`, `images-r9/boot-r10.img`) boots normally
(ABL is happy), then `kexec-test.sh` loads the mainline `Image` + our DTB + r9 initramfs and `kexec -e`s. ABL never sees the
mainline DTB, so the ABL refusal problem is bypassed. The console is read back from pstore/ramoops after a reset.
Tooling: `kexec-test.sh [tag]` (builds DTB with a real `/memory` node because ABL normally supplies RAM), `wdt-disable.py`.
`kexec-tools` 2.0.32-r2 (Alpine community aarch64) is copied to the phone's /tmp each run (not installed in the image).

**Findings (runs 1-5, logs `kexec-run*-console.txt`):**
- Mainline 7.2.10 boots to userspace init (initrd unpacked, crng init) with violet's DTB. Machine model `Xiaomi Redmi Note 7 Pro`.
- The ~14 s resets were the **downstream APSS watchdog (0x17c10000, bark 0x77fd3 / bite 0x8ffca ticks @32 kHz ≈ 15.6/17.6 s)** biting,
  because mainline has no watchdog driver wired. `wdt-disable.py` zeroes `WDT0_EN` (offset 8) via /dev/mem; with `NOWDT=1` the
  kernel runs indefinitely (run 4 ran >170 s). Default keeps the watchdog armed = automatic recovery, no button press needed.
- **DTS bug fixed:** pm6150l RPMh `qcom,pmic-id` must be `"c"` (vendor resources are `smpc*`), not `"e"` (error was
  `smps1: could not find RPMh address for resource smpe1`).
- **SPMI IRQ storm (kexec artifact):** downstream leaves PMIC peripheral irqs enabled on apids outside the range of DT consumers
  (apid 141-143); pmic_arb ignored them (WARN_ONCE) and the level irq 91 storms forever. Local patch in `spmi-pmic-arb.c`
  clears and `EN_CLR`s them. After that: no storm, clean log to the watchdog bite. (Probably not needed on a cold ABL boot.)
- imem (0x146aa000) is not readable from Linux (bus error, xPU-protected), so that route is closed.
- ramoops text is bit-garbled in places (cache attribute mismatch between kernels); still readable.
- `[Firmware Bug]: Kernel image misaligned at boot` appears under kexec (image placed at a non-2 MB address), harmless.

**Next:** wire `&usb_1` + QUSB2 PHY in the DTS so the mainline kernel shows up as a USB gadget (then SSH/log without pstore),
eMMC supplies, DSI/panel, GPU bring-up (`gpu_cc_gx_gfx3d_clk_src: RCG did not turn on` is the first GPU hint).

**Later the same night (runs 6-21) — mainline reaches the Adreno as a DRM device:**
- Hang #1 `1700000.interconnect` (aggre1_noc): its QoS register writes hang the probing CPU. Fixed with `&aggre1_noc { /delete-property/ clocks; }`
  (no clocks => `qos_requires_clocks` skips QoS programming).
- Hang #2 TLMM probe: reading pin `gpio0`'s ctl register hangs the CPU (TZ/xPU-protected). `&tlmm { gpio-reserved-ranges = <0 4>; }` fixes it.
  (`tlmm-bisect.sh` automates finding more such pins; none needed so far.)
- USB: `&usb_1_hsphy` (vdd=L4, pll=L11, dpdm=L17) + `&usb_1 { dr_mode="peripheral"; maximum-speed="high-speed"; phys=<&usb_1_hsphy>;
  qcom,select-utmi-as-pipe-clk; }`. Without `select-utmi-as-pipe-clk` dwc3 fails with `failed to enable ep0out` (no SS PHY => no pipe clock).
  Needs `USB_CONFIGFS`/`USB_F_NCM` built in (initramfs has no modules for the mainline kernel). Host then sees `xiaomi,violet`.
- eMMC: `sdhci_msm` works as is; the pmOS initramfs finds the rootfs and **boots the full pmOS userspace on mainline 7.2.10** (SSH over NCM).
- **GPU:** needs `msm.separate_gpu_kms=1` on the cmdline (no display master yet) and firmware in `/lib/firmware/qcom/`
  (`a630_sqe.fw`, `a612_rgmu.bin`, `a612_zap.mbn|mdt+b0x`). Result: `/dev/dri/card0` + `/dev/dri/renderD128`, `[drm] Initialized msm 1.13.0 for 5000000.gpu`.
- **Zap shader: still rejected (-22).** (An earlier note here claiming it was "solved by ordering" was WRONG: in those runs `hw_init` failed in
  `cp_init`, which runs *before* the zap load, so the zap was never attempted.) Facts: TZ returns `0xffcfffbb` (= downstream's `-3145797`) for
  `PAS_INIT_IMAGE` in <1 ms, identically for pas_id 12/13/14, for every buffer placement (coherent <4 GB, cached pages, 64-bit coherent, the
  reserved `pil-gpu` region), from any CPU (0/2/4/6), after `PAS_SHUTDOWN`, with the `.mbn` or `.mdt`+`.b0x` forms, and with the metadata byte-identical
  to the file downstream uses (hash31 e83944e1). Downstream's call (trace in `gpu_zap_trace.txt`): `scm_pas` bus vote (master 125, ab=393.6 MB/s,
  ib=3.936 GB/s) then `func 0x42000201 args 0x82,0xd,<phys>` takes ~17 ms (TZ hashing with the crypto engine), then `PAS_MEM_SETUP 0x42000202
  (0xd, 0xf1000000, 0x1000)`, then `PAS_AUTH_AND_RESET 0x42000205 (0xd)`. Mainline mimics the vote with `&{/firmware/scm} interconnects` but every BCM goes out
  saturated (`0x6fffffff`, interconnect sync_state pending) and the BCM at `0x5006c` is sent `valid=0` (`0x40000000`) vs downstream's `0x60000008`.
  Leading suspects: the BCM/crypto-engine vote (compare `rpmh_send_msg` lists in `gpu_zap_trace.txt` vs `mainline-trace47.txt`), or a TZ state set up by
  something downstream does earlier. Running without the zap kills the phone (SECVID_TRUST_CNTL write = permission violation -> reset).
  Unexplored idea: let downstream KGSL bring the GPU up (RGMU + zap) and have mainline adopt the running GPU.
- **GPU power-up: SOLVED (run 40).** Root cause of the junk register reads (`0x5c00bd00`) was my own port: GMU registers must be accessed with
  `GMU_BYTE_OFFSET = (reg << 2) - gmu->mmio_offset` (mmio_offset = 0x6d000; the GMU window starts 0x6d000 into the GPU space). Writing at `mmio + (reg<<2)` hit
  unrelated MMIO. With correct addressing the downstream-style RGMU sequence works: ITCM load, `PCC_CTRL` 0->1, `PCC_INIT_RESULT` set, RGMU fw version 0x00020011,
  OOB GPUSTART acked, `RBBM_STATUS` reads real values and `cp_init` (CP_ME_INIT) completes. The sequence (captured from downstream ftrace with
  `trace_event`s `kgsl`, `clk`, `regulator`, `scm`, `rpmh`; `gpu_ctx_trace.txt`): CX gdsc on, gmu clk -> 200 MHz (gpll0), enable gmu/cxo/axi/memnoc/smmu_vote,
  PLL1 + gx_gfx3d clocks, irq clear/mask (0x1F991/0x23B04/0x1F993/0x23B06), `GENERAL_7=1`, ITCM, power counter, IFPC hyst, `RGMU_CX_INTR_GEN_EN=0x20060`,
  `AO_INTERRUPT_EN=8`, `HOST2GMU_INTR_EN_2/3`, fence range `0x80a008a0`, fence ctrl 0, `0x23B82=0` (BCL), `PCC_CTRL` 0 then 1, then OOB GPUSTART
  (`0x1F994=0x10000`, ack in `0x1F992`). The CPU must NOT take the GX gdsc for RGMU (RGMU owns it). `a612_rgmu.bin` is a PCC register save/restore
  table, not CPU code (REA/objdump showed 16-byte records). Also needed: `adreno_has_rgmu()` alongside `adreno_has_gmu_wrapper()` in `fenced_write` & friends.

- Debug prints currently in the local tree (not for upstream): `ZAPDBG` in `qcom_scm.c`, `qcom_scm-smc.c`, `adreno_gpu.c` (auth_and_reset-anyway experiment),
  `PROBE-START` in `drivers/base/dd.c`, `TLMM-DIR` in `pinctrl-msm.c`, and the stale-SPMI-irq quench in `spmi-pmic-arb.c`.
- **Open:** enabling `&mdss` (DPU) fails: dispcc branch clocks cannot enable (`clock enable failed, ret:-16`), then oopses in the msm-mdss error path;
  needs the DSI PHY (provides the dispcc parents) wired first. Leave `&mdss` disabled until then.
- Display/screen is not needed for any of this; the observation channel is the rootfs itself: `/etc/local.d/90-mainline-probe.start` writes
  `/var/log/mainline-run.txt` (dmesg, dwc3 regdump, clk_summary) and reboots after ~65 s unless `/etc/mainline-stay` exists.
- Watchdog: `wdt-disable.py ext` pushes the downstream APSS watchdog bite to ~32 s (20-bit counter max) as a fallback.

## 2026-10-13 — PAUSED HERE. Phone is on r9 and working. Blocker: ABL refuses our DTB.

**State of the phone (verified at pause):** running r9 -- `4.14.356-openela-rc1-perf #10-postmarketOS`,
DT model `VIOLET` (vendor DTB), USB/NCM up, ssh fine. `boot` = r9 from `images-r9/boot-r9.img`,
`dtbo` = the stock image from `device-backup/dtbo-p60.img`, `misc` erased. Nothing is broken.

**Everything for the mainline attempt is built and waiting:**
`~/violet-mainline/boot-mainline.img` = mainline 7.2.10-sm6150 `Image` + `violet-sm6150.dtb`
(117 KB, carrying the vendor memory map, imem, `/firmware/android`, `__symbols__` and the ABL keys)
+ r9's initramfs, with r9's `pmos_root_uuid` so only the boot partition changes.
Helper scripts: `mk-bootimg.sh`, `flash-test.sh` (flash + observe + auto-restore), `dtbo-test.sh`,
`variant-a.sh` / `variant-b-flash.sh` (bisection), `dtbo-mainline.img` (our board overlay).

**What is now proven**
- ABL **accepts our kernel** (my kernel + vendor DTB booted). **Our device tree is the only blocker.**
- `fastboot boot <img>` is useless on this device -- it always runs the *flashed* partition. Only a
  real flash tests an image. (This invalidated an earlier bisection; don't repeat it.)
- A refused image returns the device to **fastboot in ~10 s** -> flash iteration is safe, no buttons.
- The `dtbo` partition holds a VIOLET board overlay whose phandle fixups resolve only against the
  vendor DTB: `fdtoverlay -i violet-sm6150.dtb -o out dtbo-entry-0.dtbo` -> `FDT_ERR_BADOVERLAY`.
  ABL applies it every boot, which is why every earlier DTB variant failed.

**Matched/fixed, and it is STILL refused** (each verified in the built image by a real flash):
PE header/`CONFIG_EFI`, `qcom,msm-id`/`board-id`, `text_offset = 0x80000`, `code0` = branch /
`code1` = 0, memory node named `memory`, `__symbols__` present, an applyable replacement dtbo, and
the vendor's full reserved-memory map + `qcom,msm-imem@146aa000` + `/firmware/android`.

**The screen was damaged when this was written - it has since been REPAIRED (2026-10-25), so ABL's
own message can now be read on the panel.** That makes reading the refusal on screen the cheapest
route to the answer: flash a refused image, watch the display. (Kept for context: at the time this
was the blocker.) Other channels, best first:

1. **Distinguish "ABL refused" from "kernel started and died instantly".** pstore is empty, which is
   consistent with both (nothing reaches the console either way). Android records the restart reason
   in **imem** (`restart_reason@65c`, `boot_stats@6b0`) -- but r9 has no `/dev/mem`. **Cheapest fix:
   enable `CONFIG_DEVMEM` in the downstream kernel, rebuild, flash, and read imem** -- that is a
   proven-safe cycle now, and it would say whether ABL ever handed off.
2. **The ABL UART** (`earlycon=msm_geni_serial,0x880000`): needs physical access to the pads, but it
   is the definitive channel if it can be obtained.
3. Continue guessing: the one class not yet tried is that ABL validates something about the **boot
   image as a whole** rather than the DTB (e.g. a required node *inside* the DTB at a fixed path that
   must exist for its patch step) -- but see (1) first, it is cheaper than more blind cycles.

**Also remember:** the shenchao panel driver is done and compiling
(`panel-novatek-nt36672e.c` + `novatek,nt36672a-shenchao`), the DSI wiring in the DTS is still to do,
`CONFIG_DRM_PANEL_NOVATEK_NT36672E` is **not** enabled yet (the A variant is), and the mainline
kernel has no eMMC supply wiring yet.

## 2026-10-13 (vendor-node port, offline — phone parked awaiting one button press)

**Confirmed by flashed-once bisection (not `fastboot boot`, which is useless here):**

| flashed image | ABL | outcome |
|---|---|---|
| vendor kernel + vendor DTB | accepted | boots (that is r9) |
| vendor kernel + OUR DTB | **refused** | back to fastboot in ~10 s |
| OUR kernel + vendor DTB | **accepted** | booted, no USB (a mainline kernel with vendor-shaped nodes binds nothing) |

**=> ABL accepts our kernel outright; our device tree is the sole blocker.**

**Overlay mechanism found (real, but not sufficient):** the `dtbo` partition holds a VIOLET board
overlay (`model = "VIOLET"`, `msm-id 0x163`, `board-id 0x22`) whose fragments use phandle fixups
(`trip = <0xffffffff>`, `cooling-device = <0xffffffff …>`) resolved against the *vendor* DTB's
symbols. Against a mainline DTB:

    fdtoverlay -i violet-sm6150.dtb -o out dtbo-entry-0.dtbo   -> FDT_ERR_BADOVERLAY
    fdtoverlay -i violet-sm6150.dtb -o out our-overlay.dtbo    -> rc=0

ABL applies that overlay on every boot, so this is why *every* variant of our DTB was rejected --
including after matching the PE header, `board-id`/`msm-id`, `text_offset`, `code0`, the memory node
name and `__symbols__`. A replacement dtbo that applies cleanly was built and flashed
(`dtbo-mainline.img`, ~/violet-mainline/dtbo-test.sh) and our DTB was **still** refused, so ABL wants
more than an applyable overlay.

**Conclusion: ABL patches specific nodes BY NAME, and a mainline DTB lacks them.** Ported verbatim
from violet's own vendor DTB (read back off the device) into `violet-sm6150.dts`:

- reserved-memory: `hyp_region@85700000`, `xbl_aop_mem@85e00000`, `sec_apps_region@85fff000`,
  **`removed_region@86200000`** (45 MB, ABL's removed-memory record), `camera_region@8ab00000`,
  `modem_region@8b000000`, `video_region@92e00000`, `wlan_msa_mem@93300000`,
  `cdsp_region@93500000`, `adsp_region@95300000`, `ipa_fw_region@97100000`,
  `ipa_gsi_region@97110000`, `qseecom_region@9e400000`, `cdsp_sec_mem@9f800000`,
  `cont_splash_region@9c000000`, `dfps_data_region@9d000000`, `disp_rdump_region@9d100000`
  -- all with violet's own addresses and the vendor's `removed-dma-pool`/`shared-dma-pool`
- `qcom,msm-imem@146aa000` with its children (`restart_reason@65c`, `boot_stats@6b0`,
  `kaslr_offset@6d0`, `mem_dump_table@10`, `dload_type@1c`, `pil@94c`, `diag_dload@c8`)
- `/firmware/android` = `boot_devices`, `vbmeta { parts }`, `fstab { vendor }`

Labels on the added regions were dropped: ABL matches node *names*, and mainline already owns some of
those labels (`pil_video_mem` collided). `dt-validate rc=0` (its remaining complaints are about the
vendor/Android nodes not being in mainline's bindings, which is expected and unavoidable).

**Built and ready to flash:** `boot-mainline.img` (kernel 31596552 B, dtb 117473 B with the vendor
nodes + `__symbols__` + the ABL keys, r9 initramfs, r9's `pmos_root_uuid`).

**BLOCKED ON ONE THING:** the phone is parked running OUR kernel + the VENDOR DTB (it booted, but a
vendor-shaped DTB gives a mainline kernel no USB, so it is unreachable). My `variant-b-flash.sh`
exited on its success path without restoring r9 -- that was a mistake. **The boot partition currently
holds that image**, so a plain power-cycle re-enters it; the phone needs **Volume Down + Power** to
reach fastboot, then `fastboot flash boot images-r9/boot-r9.img` restores it (dtbo backup is
`device-backup/dtbo-p60.img`, stock image verified).


**RESULT: still refused after matching every identifiable difference.** Confirmed by control that
this is a genuine refusal, not a broken reboot path (r9 flashes and boots through the identical
sequence). Fixes applied and each verified by a real flash+observe cycle:

| fix | verified in the Image? | outcome |
|---|---|---|
| disable `CONFIG_EFI`/`EFI_STUB` (PE `MZ` header at offset 0) | yes, no `MZ` | still refused |
| inject `qcom,msm-id <0x163 0>` + `qcom,board-id <0x22 0>` | yes | still refused |
| `head.S` `text_offset` 0 -> `0x80000` (match vendor) | yes | still refused |
| `head.S` `code0` = branch, `code1` = 0 (vendor layout) | yes, `0x1465103e` | still refused |
| drop the zero-size `/memory` node (ABL supplies RAM) | yes | still refused |

Header parity with the vendor kernel at this point: no PE header, `text_offset 0x80000`,
`code0` = branch / `code1` = 0, `flags 0xa`, `reserved 0`, `magic ARM\x64`, `pe_header_offset 0`.
Same page size, header version, and load addresses in the boot header.

**=> the remaining cause is not in the arm64 header or the DTB. It needs the message ABL prints on
the phone's screen (invalid image / not signed / an error code). Nothing else observes it: pstore is
empty because the kernel never reaches a console, `logfs` holds no ABL log, `misc` only had the
`bootonce-bootloader` BCB (cleared, made no difference), and `fastboot getvar all` is empty.**

**Bisection summary** (`fastboot boot` is NOT a valid test on this device -- see below):

| image | ABL result |
|---|---|
| vendor kernel + vendor DTB | accepted |
| vendor kernel + OUR DTB | accepted (ran with our DTB: DT model became VIOLET via the dtbo overlay) |
| OUR kernel + vendor DTB | refused |
| OUR kernel + OUR DTB | refused |

**=> the discriminator is the KERNEL image, not the DTB.**

> *[note added 2026-10-25 11:15, docs split]* This table is the invalid `fastboot boot` reading. "DT model became VIOLET" is also the vendor DT's model, i.e. the flashed partition ran. The flashed-once table above (kernel accepted, our DTB refused) is the valid one, and the PAUSED and 2026-10-25 entries use it.

**Two operational corrections that matter a lot:**

- **`fastboot boot <img>` does NOT boot the supplied image on this device.** With the vendor kernel,
  our kernel, the vendor DTB and our DTB it always ended up running the **flashed** partition (uname
  stayed 4.14, DT model stayed the vendor's). It is a fancy reboot, not a test. Only a real flash
  exercises an image. This invalidated several earlier "it boots!" readings.
- **A refused image is recoverable with no button press.** Flashing the mainline image puts the device
  back in **fastboot** within ~10 s, so `fastboot flash boot images-r9/boot-r9.img` restores r9
  immediately. Measured four times. **Flash iteration on this device is safe** -- no Volume-Down
  ritual. `flash-test.sh` automates flash + observe + auto-restore.

**Untried routes if the screen is unreadable:** boot the image from the **recovery** partition
(triggered via the `misc` BCB `boot-recovery`) -- a different ABL code path; and building the kernel
as `Image.gz`. Both are cheap but speculative.

## 2026-10-13 (later) — device tree DONE and validating; shenchao panel added; boot-test tooling ready

**Device tree finished and clean:**
- Added the two fixed clocks, overrode `pil_gpu_mem` to violet's 0x97115000, enabled `sdhc_1`
  (violet's vendor DT declares no vmmc/vddio at all — the bootloader leaves those rails on, and
  mainline treats them as optional).
- **The GPU needs `firmware-name` on the `zap-shader` node.** `adreno_gpu.c` reads it from the DT
  ("the firmware is signed with a (potentially) device specific key, having the name come from
  gpulist was a bad idea") and fetches it with `request_firmware_direct()` — i.e. **verbatim, no
  `qcom/` fallback probing**. Violet's node says `firmware-name = "qcom/a612_zap.mbn"`, and the file
  to install there is the **ROM's `a612_zap.elf` (14240 B)**, *not* the upstream linux-firmware qcs615
  blob (14256 B) which TrustZone rejects.
- Still `dt-validate rc=0` after every change.

**Panel (the real blocker for a usable display) — solved at the driver level:**
- Mainline's `panel-novatek-nt36672a.c` models init as fixed **2-byte** DCS writes
  (`struct nt36672a_panel_cmd { const char data[2]; }`). Violet's shenchao panel needs a **325-byte**
  init sequence, so that driver cannot express it.
- `panel-novatek-nt36672e.c` uses the modern `mipi_dsi_dcs_write_seq_multi()` API with
  variable-length sequences — the right mechanism. Wrote a generator (`~/violet-mainline/gen-panel.py`)
  that decodes the vendor's packet stream
  (`[dt] [last] [vc] [ack] [wait_ms] [dlen_hi] [dlen_lo] [payload...]`) and emits C:
  **325 bytes -> 36 packets, all consumed, 38 DCS writes + delays.**
- Added a `novatek,nt36672a-shenchao` compatible + mode (1080x2340@60, 4 lanes, RGB888,
  h 90/2/120, v 13/3/8, clock 183257 kHz, burst + LP-mode + non-continuous clock, 67x145 mm) via
  `~/violet-mainline/add-shenchao-panel.py`. **The driver compiles clean.**
  (TODO upstream: fold into `nt36672a.c` and retire the 2-byte model.)

**Boot-test tooling ready:**
- `~/violet-mainline/mk-bootimg.sh` — builds `boot-mainline.img` = mainline `Image` + `violet-sm6150.dtb`
  + the **r9 initramfs**, with r9's geometry and **the same baked `pmos_root_uuid`**, so only the boot
  partition changes and the existing rootfs is reused (no 3 GB write per iteration). `quiet splash` is
  dropped so the console output gets captured.
- `~/violet-mainline/run-test.sh {boot|flash|revert|pstore}` — enters fastboot over ssh (no buttons),
  tries **`fastboot boot`** first (non-destructive), and has `revert` + `pstore` for reading the
  ramoops log left by a failed mainline attempt.

**Deferred (not needed for the first boot test):** DSI/panel node wiring in the DTS — violet's display
PHY/panel rails are **not** in `sm6150.dtsi`; they are in the vendor display dtsi, now fetched to
`~/violet-mainline/dt/ref/base-sm6150-sde*.dtsi`. The values needed:

| Consumer | Vendor rail | Our mainline label |
|---|---|---|
| DSI PHY `vdda-0p9` | `pm6150_l4` | `vreg_l4a_0p8` (LDO4, 875-975 mV) |
| panel `vddio` | `pm6150_l13` | `vreg_l13a_1p8` (LDO13, 1.8 V) |
| panel `lab` / `ibb` | pm6150l BOB / inverting rail | `vreg_bob` models `lab`; **mainline's pm6150l has no `ibb` resource**, so the negative rail may not be modellable — check on the first display iteration |

The mainline panel driver wants supplies named `vddio`/`vddpos`/`vddneg`, so `lab` -> `vddpos` and
`ibb` -> `vddneg`. Panel reset/te GPIOs: `reset-gpios = <&tlmm 91>` and `te-gpios = <&tlmm 90>`
(from violet's display dtsi). Also needed before the display comes up: a binding entry for
`novatek,nt36672a-shenchao` in `Documentation/devicetree/bindings/display/panel/`.

## 2026-10-13 — DTS validates clean; config killers caught before any flash
**Done, no phone touched:**
- Wrote `arch/arm64/boot/dts/qcom/violet-sm6150.dts` in the local 7.2.10 tree: SoC (`talos.dtsi`) +
  `pm6150.dtsi`/`pm6150l.dtsi`, `chosen`/`aliases` on uart0, the two fixed clocks the SoC needs,
  violet's reserved-memory (ramoops + `pil_gpu_mem` moved to 0x97115000), `&gpu { status = "okay" }`,
  and the pm6150/pm6150l LDO/SMPS rails under `&apps_rsc` (violet's vendor values).
- Added violet's binding entry to `Documentation/devicetree/bindings/arm/qcom.yaml` (the schema
  requires an explicit `items` entry for a new board — mirroring the EVK's shape).
- **`make ARCH=arm64 LLVM=1 qcom/violet-sm6150.dtb` builds in 0.58 s and `dt-validate` returns
  `rc=0` with no findings.**

**Three real errors the loop caught (each would have cost a flash):**
1. `talos.dtsi` references `sleep_clk` / `xo_board_clk`; the **board** must define them (32 kHz and
   38.4 MHz fixed clocks, as the QCS615 EVK does).
2. `pil_gpu_mem` is at **0x97715000** on the EVK but **0x97115000** on violet — must be overridden or
   the allocator eats the zap/GPU region.
3. **The sm7150-derived defconfig leaves the sm6150 drivers OFF**: `# CONFIG_PINCTRL_QCS615 is not
   set`, `# CONFIG_INTERCONNECT_QCOM_QCS615 is not set`, and the clock symbols absent entirely. Fixed
   by enabling `QCS_GCC_615`, `QCS_GPUCC_615` (the GPU's clock controller), `QCS_DISPCC_615`,
   `QCS_VIDEOCC_615`, `QCS_CAMCC_615`, `PINCTRL_QCS615`, `INTERCONNECT_QCOM_QCS615`. Without these the
   SoC comes up dead — this is the single most valuable thing the local ladder found.
   Also enabled `DRM_PANEL_NOVATEK_NT36672A` and `TOUCHSCREEN_NOVATEK_NVT_TS`.

**Config saved to** `~/violet-mainline/pkg/config-postmarketos-qcom-sm6150.aarch64`
(`CONFIG_LOCALVERSION="-sm6150"`; verified `=y` for QCS_GCC_615, QCS_GPUCC_615, QCS_DISPCC_615,
PINCTRL_QCS615, INTERCONNECT_QCOM_QCS615, DRM_MSM, QCOM_IOMMU, PSTORE_RAM, PSTORE_CONSOLE).

**In flight:** full `make ARCH=arm64 LLVM=1 Image modules dtbs` (log:
`~/violet-mainline/build-sm6150.log`).

**Known next steps:** shenchao panel desc in `panel-novatek-nt36672a.c` (only `tianma,fhd-video` is
matched today) + DSI wiring; eMMC supplies; USB; touch; then the pmOS packages; then the QEMU `virt`
control boot; then flash and read the ramoops log.

## 2026-11-02 13:00-13:35 IST — item 1 (reboot/shutdown hang) measured: NOT a service hang; suspend kills the USB gadget but does not by itself freeze the shutdown

**Symptom being fixed:** `sudo reboot` shows plymouth for a few seconds, then the phone freezes; after ~1 min a 10 s power-button hold is the only way out (user's report, plan item 1).

### What the frozen boot's own ramoops says (build #183, `logs/pstore-2026-11-02-13/dmesg-ramoops-0`)
One panic, at 965 s uptime, 1295 lines, from a *clean* boot — full timeline (t in s):
```
642.47  PM: suspend entry (s2idle)          647.97  PM: suspend exit   (5.5 s, no button pressed)
642.59  dwc3-qcom a600000.usb: port-1 HS-PHY not in L2
647.99  dwc3-qcom a600000.usb: failed to enable ep0out        <- gadget broken by the resume
647.51  novatek-nvt-ts 0-0001: Error reading from 0x00: -6
650.3   wlan0 re-associated (WiFi survived, USB did not)
903.83  q6afe/tasdev: amp 0 shutdown (session teardown)      909.5  amp 0 shutdown: 0
922.76  rfkill: input handler enabled
923.78  ipa: received modem offline event; remoteproc1: stopped remote processor modem
944.80  rcu: INFO: rcu_preempt detected stalls — CPU1 not responding
946-963 ath10k: failed to start hw scan / failed to transmit: -108 (the WLAN is only taken down here)
954.80  After 10 seconds, these CPUs still haven't responded to the NMI: 1
963.52  watchdog: BUG: soft lockup - CPU#2 stuck for 22s! [kworker/2:1]  (100% system, 1% hardirq)
965.4   panic -> "SMP: stopping secondary CPUs" -> "SMP: failed to stop secondary CPUs 1" -> frozen
```
**Reading it.** No OpenRC service blocked. A CPU (1) stopped answering IPIs ~21 s before the stall was
reported, i.e. at 923.8 s — the same 0.02 s as the modem stop. Everything after (RCU stall, the
`kick_all_cpus_sync` softlockup in a BPF-free workqueue, the panic) is downstream of that one dead core.
This is the same family as the 2026-10-24/25 stall analysis (`PROGRESS.md` 3600-3712), and note the
`cleanup_irq` mask patch **is** in #183 with **zero** `cleanup_irq` lines on this boot — so that patch
did not cover this instance.

### Plan item 1 suspects, measured and killed (all on the live phone, no reboot)
| suspect | measurement | verdict |
|---|---|---|
| `hexagonrpcd-adsp-sensorspd` stop hangs | `phone/hex-stop-measure.sh`: rc-service stop returned in **2 s**, rc=0, daemon gone, restart ok | **not it** (this boot; the daemon was blocked in `fastrpc_internal_invoke` at the time, and still left) |
| modem stop / rmtfs ordering | `phone/modem-stop-wedge-test.sh`: `rc-service violet-modem stop` with ath10k live -> modem `offline` in 0.3 s, **90 s clean**, no rcu/lockup lines | **not it on its own** |
| D-state in sync/umount | both clean reboots today unmounted all 4 filesystems (loop0p1, mmcblk0p86/p74/p71) | **not it** |

### The user's suspend hypothesis: gadget half CONFIRMED, freeze half NOT sufficient
Suspend/resume was suspected because the freeze boot had suspended and today's clean reboots had not.
Reproduced deliberately (hook restored, `echo mem > /sys/power/state`, rtc wake +15 s):
```
299.30 PM: suspend entry (s2idle)   302.72 port-1 HS-PHY not in L2
305.10 failed to enable ep0out      305.10 novatek-nvt-ts 0-0001: Error reading from 0x00: -6
305.98 PM: suspend exit
```
After that resume `/sys/class/udc/a600000.usb/state` = **not attached** while configfs still lists
`usb-signaller-developer/UDC = a600000.usb`: the elogind hook's `post` step rebinds the UDC and dwc3
fails, so **USB is dead and the phone is reachable only over WiFi**. That is the hook bug the handoff
predicted, now with a two-for-two repro (frozen boot + today).
**But** a reboot issued from exactly that state completed: pstore ends `[628.53] reboot: Restarting
system`, 4 filesystems unmounted, phone back in 50 s. So a broken gadget is a real bug, **not the cause
of the shutdown freeze**. 3 of 3 reboots today were clean (19 s, 19 s, ~30 s).

### Instrumentation that works, and one that does not
- **Works:** 2 s `dmesg` harvester on ext4 with `sync` (`/var/log/shutdown-harvest.log`) — survived
  every reset; laptop-side `dmesg -wT` stream; pstore console.
- **Does NOT work: `rc_logger`.** OpenRC 0.63.2 ignores it: set `rc_logger="/var/log/rc.log"` in
  `/etc/rc.conf`, restarted a service -> file still 0 bytes. So the handoff's `/var/log/rc.log` plan is
  dead on this build.
- **Does NOT work (so far): the inittab stage trace.** `phone/install-shutdown-trace.sh` rewrote
  `::shutdown:/sbin/openrc shutdown >>/dev/kmsg 2>&1` (backup `/etc/inittab.bak-hermes`), yet the next
  shutdown produced **0** `rcsh:` lines in both the harvester log and pstore, while the same shutdown did
  unmount everything. Treat as unverified; the service-stop stage is still unmeasured.
- **Hands-free recovery:** `qcom_wdt` at `/dev/watchdog0` — 30 s, `MAGICCLOSE` **not** supported,
  `SETTIMEOUT` not supported, so once opened it can only be cleared by a reset. Arming it just before a
  reboot (`host/reboot-test.sh`, `WATCHDOG=1`; `phone/reboot-from-here.sh`) means a frozen shutdown
  self-resets instead of needing the 10 s power hold. Verified it arms and does not fire on 3 clean runs
  (shutdown+soc reset ~15-20 s < 30 s).

### Changes made to the phone today (revert list)
1. `softlockup_panic` was set 1 -> 0 for the diagnostics, but it is a **boot-time default at 1** on this
   kernel: after the 13:32 reboot it reads 1 again. So a future wedge will panic again (~22 s) and the
   panic path hangs in `SMP: failed to stop secondary CPUs` -> power-button hold. Setting it to 0 per
   boot is what buys an inspectable, non-panicking stall.
2. Sleep hook **moved back** to `/etc/elogind/system-sleep/no-hexagonrpcd-on-suspend.sh` (was in
   `/root/sleep-hook-off/`). It is now known to break the gadget on resume -> USB dead until reboot.
3. `/etc/inittab` shutdown line carries the `>>/dev/kmsg` trace; revert with
   `phone/install-shutdown-trace.sh --revert`.
4. `sleep-inactive-{battery,ac}-type` are still `'nothing'`: `gsettings set` over ssh silently no-ops
   (needs the phoc session bus), so idle suspend stays off and USB stays up — left as found.

### Open
- The freeze did not reproduce in 3 reboots today; 2 of the 3 plan suspects are dead and the third
  (suspend) is only half-right. Next measurement must name the OpenRC stage: the `/dev/kmsg` trace needs
  a working form (or per-service markers) before the next freeze is worth chasing.
- The wake source of the 5.5 s resume in the frozen boot is still unknown (`pm_wakeup_irq`,
  `wakeup_sources` were not captured before the panic).

## 2026-11-02 13:45-14:35 IST — suspend/resume root-caused (two separate bugs); shutdown freeze reproduced, stage now known

New cable, both devices moved to <lan>.x (laptop .11, phone .7); USB gadget is `enp0s20f0u4`.

### Bug A — ADSP firmware crashes on resume if `hexagonrpcd` is alive during sleep
Confirmed by driving it the wrong way on purpose: suspended via `/sys/power/state` (which does **not** run
the elogind hook), so hexagonrpcd stayed up. On resume:
```
[1731.20] remoteproc remoteproc0: recovering adsp
           remoteproc0 state = crashed
[2448.30] remoteproc remoteproc0: can't lock rproc adsp: -4
[2448.30] remoteproc remoteproc0: Boot failed: -4
```
It cannot be restarted from userspace (`echo start > state` fails with -EINVAL/-EINTR); the boot is left
without sensors and without audio until a reboot. The elogind hook (variant C below) prevents it on the
paths that matter (Phosh idle / power button / `loginctl suspend`).

### Bug B — dwc3 cannot re-enable its control endpoint on resume, so USB never comes back
Every s2idle resume (with or without the hook unbinding the UDC) logs
```
dwc3-qcom a600000.usb: port-1 HS-PHY not in L2      (diagnostic only, suspend proceeds)
dwc3-qcom a600000.usb: failed to enable ep0out      (on resume)
```
and `/sys/class/udc/a600000.usb/state` stays **not attached** while configfs still lists the gadget:
USB is dead for the rest of the boot, WiFi keeps working. Measured recoveries:
| action | result |
|---|---|
| write the UDC name into the gadget's `UDC` file again (configfs rebind) | **no effect**, no kernel messages at all |
| `echo a600000.usb > /sys/bus/platform/drivers/dwc3-qcom/unbind` then `bind` | **USB back in ~4 s**, `state=configured`, host re-enumerates, ssh works — no reboot |
So `patches/0036` does the driver-level rebind after resume. It is a workaround for a dwc3-qcom resume
bug (the controller is not re-initialised, ep0 stays unconfigured), **not** a fix.

### What is installed (patches/0036)
- `/etc/elogind/system-sleep/no-hexagonrpcd-on-suspend.sh` (variant C): stops hexagonrpcd, unbinds the UDC
  **only when nothing is attached** (dwc3_gadget_suspend has nothing to soft-disconnect then and returns
  -EAGAIN, which aborts the whole suspend — that is what the original hook was for), and after resume does
  the dwc3-qcom rebind if the UDC did not come back on its own. Verified via `loginctl suspend`:
  logbookd `e-suspend: Operation 'suspend' finished`, then `sleep-hook(post): after driver rebind:
  state=configured`, USB usable.
- new service `violet-udc-repair` (default runlevel): same repair for resumes that bypass elogind, plus an
  ADSP check that logs `ADSP WEDGED - sensors/audio need a reboot` when it cannot be recovered.
  It refuses to act when `/run/openrc/softlevel` is `shutdown` (see suspect below).
- `gsettings set ... sleep-inactive-{battery,ac}-type suspend` **needs phosh's session bus**, not the ssh
  environment: read it from `/proc/<phosh>/environ` (`unix:path=/tmp/dbus-XXXX`). Without it, `set`
  silently no-ops and `get` still prints the old value — that is why the handoff's keys kept reading
  `'nothing'`.

### Shutdown freeze (item 1): second occurrence, and the stage is now known
A plain `sync; reboot` over WiFi at 14:15 froze: no USB, no WiFi for ~4 min. The 2 s harvester on ext4
survived and shows the shutdown reaching the **end** of OpenRC's work:
```
[622.9] Stopped ZRAM swap device /dev/zram0  [ ok ]
[623.3] EXT4-fs (loop0p1): unmounting ...   (all four filesystems)
        <- log ends here; no "reboot: Restarting system"
```
So the hang is in the **final kernel reboot path**, not a blocked service and not a mount/umount stall —
the opposite end from the 11:19 panic dump (which wedged before unmounting, with CPU1 dead and
`SMP: failed to stop secondary CPUs 1`). Both are the "a CPU stops answering IPIs" family.
**Suspect introduced by this session, to rule out first:** `violet-udc-repair` unbinds dwc3-qcom when the
gadget is stopped at shutdown (configured -> not attached), i.e. it could race the kernel shutdown. The
`softlevel=shutdown` guard is in the script now, and the next A/B test is: 2 reboots with the service
stopped vs 2 with it running.
Console-ramoops of that freeze was overwritten by the power-button reset, so the harvest log is the only
evidence that survived — the harvester is worth keeping on by default.

## 2026-11-02 14:45 IST — prior art checked for the two suspend bugs (the standing "search first" rule)

**ADSP crash on resume — confirmed prior art, our hook matches pmaports.**
pmaports MR 5400, `google-sargo: stop HexagonRPCD on suspend` (Richard Acayan, 2024-07-30) — commit
`fe00027849`, message verbatim: *"There is a bug in FastRPC when waking from suspend. Since HexagonRPCD is
currently only useful for a few moments when the ADSP is requesting the sensor registry, it can just be
stopped without affecting sensor support. Add a pre-suspend hook to stop HexagonRPCD so it doesn't crash
the ADSP when the device wakes up."* That is exactly bug A and exactly what our variant-C hook does, so it
is not a violet-specific mystery: it is a known FastRPC/ADSP defect, worked around in userspace upstream
too. Nothing in mainline `hexagonrpc` fixes it (issues tracked at github.com/linux-msm/hexagonrpc).

**dwc3 `failed to enable ep0out` on resume — the two upstream fixes that match this area are ALREADY in
our tree, so neither is the missing piece.**
- `usb: dwc3: gadget: Fix controller timeout at dwc3_gadget_suspend()` (Roger Quadros, 2023): split
  suspend into `dwc3_gadget_soft_disconnect()` and a `soft_connect()` that issues the core soft reset
  before re-enabling run/stop. **Present** in `drivers/usb/dwc3/gadget.c` (our `dwc3_gadget_suspend()`
  and `dwc3_gadget_soft_connect()` are that shape).
- `usb: dwc3: gadget: Bail out in pullup if soft reset timeout happens` (Krishna Kurapati / Thinh Nguyen,
  2023): if `dwc3_core_soft_reset()` returns -ETIMEDOUT, do not go on to set up event buffers and start
  the gadget. **Present**: our `dwc3_gadget_soft_connect()` does `ret = dwc3_core_soft_reset(dwc); if (ret)
  return ret;`.
- `usb: dwc3: qcom: re-enable wakeup interrupts on failed resume` (Qualcomm, 2026-09): about
  `clk_bulk_prepare_enable()` failing partway in `dwc3_qcom_resume()`. Not our case — our clocks and the
  interconnect come back (the only abort-path symptom we see is `port-1 HS-PHY not in L2`, which is a
  diagnostic, not an error return).
**Therefore:** the soft reset is *succeeding* in our case; the failing step is the EP0 **command**
(`__dwc3_gadget_ep_enable(ep0out, DWC3_DEPCFG_ACTION_INIT)` → `dwc3_gadget_ep_cmd()` times out →
`"failed to enable ep0out"` in gadget.c:3011). Upstream has no patch for that, and it is not purely
suspend-specific either: the same message appears at **boot** on earlier builds in
`logs/archive/misc/mainline-run14.txt` (t=1.29 s) and `logs/archive/kexec/kexec-tlmm2-console.txt`
(t=1.33 s). So it is an intermittent EP-command timeout of this controller, which a suspend/resume cycle
makes much more likely — not a suspend-sequencing bug we can fix by reordering the glue driver.

**Consequence for the plan:** the userspace repair (driver-level re-probe of `dwc3-qcom`, ~4 s, verified)
is presently the honest remedy, and it is what a kernel-level fix would do anyway (re-init the core after a
failed gadget start). The kernel experiment worth one build (NOT written as a patch yet, and not obviously right — see below):
in `dwc3_gadget_soft_connect()`, `__dwc3_gadget_start()`'s return value is **ignored** (`gadget.c:2817`),
so after a failed ep0out enable the code still calls `dwc3_gadget_run_stop(dwc, true)`. At minimum that
return should be checked and the gadget left disconnected (same philosophy as the 2023 "bail out if soft
reset timeout" patch). A retry after `dwc3_core_init(dwc)` is the stronger version, but note the resume path
already runs `dwc3_core_init_for_resume()` (core.c:2557/2595) *before* `dwc3_gadget_resume()`, so the core is
already re-initialised when the EP command times out — which makes "just re-init again" less likely to be
the real fix and more likely to be the same 4 s workaround expressed in C. Measure before building.

## 2026-11-02 15:00-15:25 IST — plan item 4 VERIFIED (suspend/resume), plus a real audio-inhibit bug found and fixed

Full cycle, `host/suspend-resume-test.sh --loginctl` (elogind path = the one the power button and
idle-suspend use), artefact `logs/suspend-loginctl-2026-11-02_15:01:32`:
```
301.01 sleep-hook(pre): udc state=configured
301.01 PM: suspend entry (s2idle)
303.06 dwc3-qcom a600000.usb: failed to enable ep0out      <- kernel bug, unchanged
303.94 PM: suspend exit
303.95 udc-repair: state configured -> not attached, re-binding a600000.usb (attempt 1)
311.08 sleep-hook(post): after attempt 1: state=configured
```
Result: USB shell OK, UDC configured, **ADSP running**, wlan <lan-ip>, `wake_irq=19`
= `pm8941_pwrkey`. That answers the open question in the plan ("the wake source is unknown"): with a
short press the power key is the wake source. A 10 s hold instead resets the SoC (uptime restarts) — that
is what happened during the first attempt, so the wake-source datum was lost once.

Audio after resume: sink `violet_speaker` (PulseAudio `module-alsa-sink hw:0,2`) stays loaded, `paplay`
returns 0 before and after a cycle. Not audible-verified by a human.

**New bug, found by testing the plan's own criterion "with music playing it must not suspend": it did.**
A 190 s stream with `sleep-inactive-*=suspend`/60 s suspended ~65 s in (RTC alarm woke it, so the phone was
not stranded). Cause: pmOS ships a `sleep_inhibitor` plugin for exactly this (`is-alsa-playing`:
`grep -qF 'state: RUNNING' /proc/asound/card*/pcm*/sub*/status && exit 254`) but
`/etc/sleep-inhibitor.conf` enables only `ssh-session-open` and `apk-running`. Enabled it (patches/0037).
Verified: while playing, `elogind-inhibit --list` shows
`sleep-inhibitor ... sleep ... Plugin ALSA playing  block`, and a repeat 150 s run at a 60 s idle timeout
produced **zero** suspend entries (PASSED).

Two harness bugs found and fixed while doing this (both had produced meaningless verdicts):
- `gsettings` and `paplay` **must run as the login user**: as root, dconf refuses the write
  (`failed to commit changes to dconf: The connection is closed`) and paplay cannot reach the session's
  PulseAudio, so the first version of the audio test armed nothing and played nothing while reporting
  "no suspend".
- the test's "reachable" used to mean "the interface exists"; after a resume the gadget re-enumerates with
  no IPv4 for a second or two, which yielded empty post-captures. It now requires a real ssh round trip.

## 2026-11-02 15:25 IST — item 1: the repair-service race is ruled out; reboot #5 clean

The inittab -> /dev/kmsg trace worked on this shutdown (earlier attempts produced nothing, reason still
unknown), so OpenRC's stop order is now visible in the kernel log:
```
15:25:25  * Stopping user.user ...
15:25:25  * Stopping local ...
15:25:25  * Stopping violet-udc-repair ...
15:25:26  [ ok ]
15:25:27  ipa 1e40000.ipa: received modem stopping event
          (connection reset; phone back on USB, uptime 166)
```
`violet-udc-repair` is stopped **before** the modem/gadget teardown, so the unbind/bind it performs after a
resume cannot race the shutdown. The `softlevel=shutdown` guard stays as belt-and-braces. Reboot was clean.

Running tally for item 1 today: clean at 13:13, 13:22, 13:32 and 15:25; frozen at the 11:19 boot and on the
14:15 `sync; reboot`. The two freezes differ in stage (11:19: CPU1 died before unmounting, panic -> hang at
`SMP: failed to stop secondary CPUs 1`; 14:15: all four filesystems unmounted, then nothing). **New lead:** the
14:15 freeze happened on a boot where the ADSP had crashed and been recovered earlier in the session (the
`/sys/power/state` suspends at 1722/1852 left `remoteproc0: crashed`, `can't lock rproc adsp: -4`). Worth
testing whether a recovered ADSP/modem leaves shutdown wedge-prone - i.e. reproduce by crashing the ADSP,
recovering, then rebooting, which is cheap and does not need a frozen phone to prove.

## 2026-11-02 15:45 IST — plan item 3 (recording quiet) fixed; fix-quality audit of every change

**Item 3, root cause: capture gain, confirmed by measurement.** Sound Recorder writes FLAC stereo 44.1 kHz to
`~/.local/share/org.gnome.SoundRecorder/Recording N` (not `~/Music`, which is why the first searches missed the
files). Decoding the user's own takes and measuring frame RMS (100 ms frames, 0.4 s trimmed at both ends, mean of
the top 20 % of frames) at `ADC1=20`, `TX_DEC0=88`:

| source | speech level | peak |
|---|---|---|
| `Recording 1`, ~30 cm | -28.2 dBFS | -5.8 dBFS |
| `Recording 2`, close | -26.9 dBFS | -6.0 dBFS |
| `dandelions-10s.wav` (music) | -13.8 dBFS | -5.1 dBFS |

So speech sat ~14 dB under song level - exactly the complaint, and the peak was not the problem (crest ~21 dB,
i.e. transients, not loud speech). `ADC1 Volume` is already at its hardware maximum (range 0..20), so the only
knob is `TX_DEC0 Volume` (range 0..124, 1 dB/step, 36 dB of headroom). 88 -> **100** is +12 dB and is the value
alsa-ucm-conf itself uses for the TX-macro path (`+ cset "name='TX_DEC0 Volume' 100"`, codecs/lpass dmics commit
2cc0c7d4). Measured after the change: speech -14.7 dBFS, peak -6.0 dBFS, **0 clipped samples**.
The user confirmed playback at both 30 cm and 5 cm and closed the item.

**Persisted** in `phone/violet-audio-setup` (with the measurements in the comment so nobody "optimises" it back to
88) and installed to `/usr/local/bin/violet-audio-setup` on the phone. The right long-term shape is a UCM
`HiFi.conf` shipping this value instead of a shell script - recorded in the audit below.

**Fix-quality audit, per the user's question ("are these fixes or hacks?").** The criterion used: a *fix* makes the
wrong state impossible (right value / ordering / ownership) and survives an upgrade; a *hack* repairs the state
after the failure or avoids the failing path, and will fight any upstream fix. Result: 11 real fixes, 3 items with
the right value in the wrong packaging, 6 sanctioned workarounds, 7 hacks, 1 component that must not be trusted yet
(`violet-vbat.c`, inverted sign convention), 5 problems with no fix at all (reboot freeze, hardlockup/NMI, APSS
watchdog, camera, NewPipe live 403). The full table is in `docs/STATUS.md` under "Fix-quality audit (2026-11-02)".

**Named explicitly as hacks, so a future session does not mistake them for kernel work:** the
`violet-udc-repair` dwc3 unbind/rebind after resume, the ADSP protection in the elogind hook (bypass it and the
ADSP is dead until reboot), `&aggre1_noc { /delete-property/ clocks; }`, the novatek 30 s polling loop, the panel
init as a vendor blob in a separate driver, the dsi_phy magic values (LDO 0x1c, ICP 0x3f, HS_TIMER 0x3fd08) and
patch 0016's unminimised experiment knobs.

**Harness bugs found today, both of which had already produced a false result** (recorded so they are not repeated):
1. `gsettings` and `paplay` must run as the **login user**. As root, dconf answers `failed to commit changes to
   dconf: The connection is closed` and paplay cannot reach the session's PulseAudio - the first version of the
   audio test therefore armed no timer and played nothing while printing "no suspend".
2. **busybox `find` on violet silently ignores `-newermt`** - every mtime-filtered search returned nothing, which
   made "no file was recorded" look true. List with `ls`/`find` + `-exec ls -l` instead.
Also: `grim` and `wtype` on this device are **0-byte binaries**, so no screenshots over ssh.

## 2026-11-03 (evening) — IMX586 SMIA test: the sensor streams without the 0x3000 init table

Loaded the proposed driver (`patches/proposed/imx586.c` + a `smia_test` block in probe, lane check relaxed to 2 or 4
because the booted DTB still has 2 lanes) on build 7.2.10-sm6150, dtbo erased. Output from the phone:
```
IMX586 detected (id 0586)
SMIA pre: fcnt(0005)=ff lanes(0114)=02 extclk(0136/7)=0c00 mode(0100)=00
SMIA stream-on(0100=01) w=0: fcnt +100ms=06 +200ms=0d mode=01
```
- Frame counter 0x0005 was 0xff (never streamed), then incremented ~7 per 100 ms after writing only `0x0100=0x01`
  (SMIA mode-select; note the stream-ON value is 0x01, the task text's `0x00` is stream-off). **The sensor generates
  frames on the SMIA map with no init table at all.** The 0x3000-block RPi table is not needed to stream and is
  likely wrong for this part (it writes 0x3000=0x00 and never touches 0x0100).
- EXTCLK divisor 0x0136/7 = 0x0c00 = 12.0 MHz (8.8 fixed point), but our MCLK is 24 MHz: the sensor's PLL is
  computed for the wrong input clock, so link rate/pixel clock would be 2x what CAMSS expects. Must write 0x1800.
- 0x0114 (lane mode) = 0x02 at power-on; Sony SMIA usually 0x01=2 lane, 0x03=4 lane — meaning of 0x02 unverified.
- Not yet done: whether CSI IRQs move with 0x0100=1 and a sane PLL/lane setup. Next: stop writing the 0x3000 table,
  set 0x0136/7=0x1800, lane mode, a known SMIA mode (PLL regs 0x0301-0x030f, 0x0342/0x0340 timing, 0x034c-0x034f
  size), 0x0100=1, then check csiphy/csid/vfe IRQs.
The in-tree (2-lane experiment) driver was saved as `patches/proposed/imx586.c.intree-2lane-experiment.bak`.

## 2026-11-03 (late) — IMX586 rewritten to the SMIA map: sensor streams, still no CSI frame

Power-on SMIA defaults read from the sensor: RAW10 (0x0112=0a0a), 8000x6000 full-res output (0x034c=1f40, 0x034e=1770),
line length 0x24e0, frame length 0x17b0, EXTCLK 12 MHz, VT PLL pre=2 mpy=0x168, OP PLL pre=2 mpy=0x18c, binning 0x0901=0x11.
`patches/proposed/imx586.c` (module params `smia=1`, `smia_lanes`=raw 0x0114 value, `smia_test`) now writes ONLY SMIA
registers: EXTCLK 0x1800, pre-PLL dividers doubled (4) to keep the 12 MHz rates, OP mpy 0x129 (aiming at 891 MHz
link, unverified), 2x2 binning, 4000x3000 output, frame length 0x17b0, then 0x0100=1. The 0x3000 table is no longer
written (still in the file, used when smia=0).
Result: sensor streams (frame counter 0x04 after 120 ms) with lane mode 0x01 and 0x03; capture on
csiphy1->csid0->vfe0_rdi0->video0 (SBGGR10 4000x3000, pBAA) still yields 0 bytes, csiphy1 IRQ stays 0; csid0/vfe0 IRQs
tick 1-2 per start (reset-done style, not data). Booted DTB wires the sensor to **csiphy1** with **2 lanes**.
Note: `rmmod imx586` warns (imx586_power_on from cleanup_module, "fail to enable inclk") - remove path resumes the device.
`v4l-utils` installed on the phone via apk (media-ctl, v4l2-ctl). Trial script: scratchpad trial.sh (reload both modules,
link, set formats, capture 6 s, print IRQs).
Next: read CSID/CSIPHY status regs while streaming (lane-detect/ECC/CRC errors), verify the OP PLL actual link rate
(settle count: vendor 0x11 vs ours 0x0e implies the vendor link rate differs), try the vendor lane map.

## 2026-11-03 (night) — CSIPHY1/CSID0 register dump while streaming (SMIA init)

`phone/csi-regdump.py` (python3 + /dev/mem works on the phone; CSIPHY1 = 0xac66000, CSID0 = 0xacb3000) run 4 s into a
capture of the SMIA 4000x3000 stream (sensor streaming, 0 bytes captured):
- All four data-lane blocks (0x000/0x200/0x400/0x600) AND the clock lane (0x700) are programmed even though the DTB
  endpoint has 2 lanes; lane settle reg 0x008 = **0x11** (vendor `phydump.txt` shows **0x0e** - the earlier note had
  these reversed). Everything else in the lane blocks matches the vendor dump (0xd7/0x08/0x50/0x0a/0xb8/0xaa/0x55/0x3f).
- Common block: ours 0x814=0x85 0x818=0x01 0x81c=0x02 0x8b8=0x80 0x8d8=0x04 0x8dc=0x85; vendor 0x814=0xd5, 0x818=0x01,
  0x81c=0, and non-zero 0x830-0x85c (0xff/fb/7f/ef - looks like status/lane-detect bits that ours never sets). Vendor
  dump was taken in an error path, so those may be status snapshots, but 0x814 (lane/clock enable) differs.
- CSID0: 0x100=00100101 0x104=41 0x114=10081188 0x118=124813c8 0x300=802bf007; no error bits visible.
Open: which bits of 0x814 select lanes (kernel writes CTRL5 clk-enable | lane mask), and whether the sensor really
drives clock-lane HS (settle 0x11 implies a faster link than 0x0e; vendor link rate is probably lower than 891 MHz).
Next: try OP mpy for a lower link (e.g. 0x0e settle), set DT lanes to match sensor, rerun the dump.

## 2026-11-03 (night) — E1: sensor on csiphy0, 4 lanes, SMIA init (boot-mainline-cam-csiphy0.img)

DTB: `&camss` port@0 (csiphy0) `data-lanes=<0 1 2 3>`, sensor endpoint `<1 2 3 4>` (both dtsi copies: dt/ and the kernel tree).
Flashed `boot` only (fastboot entered with the raw reboot syscall: `/usr/local/bin/reboot-bootloader` no longer exists
after the userdata rebuild, so `enter-fastboot.sh` fails). Booted 7.2.10-sm6150, dtbo untouched. Rollback image:
`boot-mainline-cam.img`. NB: `mk-bootimg.sh` still emits an image when the DTB build FAILED (it reuses the stale DTB) -
always check the `make` output / `fdtget` first.
Result (module smia_lanes=3, capture 4000x3000 pBAA via csiphy0->csid0->vfe0_rdi0): sensor streams (fcnt=04), but still
0 bytes. CSIPHY0 now matches the vendor dump exactly: 0x814=0xd5, status bank 8b0=04 8b8=80 8c4=10 8d0=02 8d8=04
8dc=d5, lane settle 0x008=0x11 (vendor 0x0e). csiphy0 IRQ 0, csid0 IRQ 1, vfe0 IRQ 2.
Conclusion: the wiring (csiphy0, 4 lanes) is now consistent with the vendor. The receiver config equals the vendor's
except settle. Remaining suspects: sensor MIPI output (PLL/timing 0x0310, 0x0808-0x0813, 0x0820-0x0823) and the 2x
link-frequency (settle 0x11 vs 0x0e). Next (E2): mine the HAL memdump for the vendor's MIPI/PLL registers, set
LINK_FREQ to the real value.

## 2026-11-03 (night) — memdump/asset mining for the vendor MIPI/PLL registers: nothing usable found

Searched `~/violet-ios/cam/`:
- `ofilm_imx586_sensormodule.bin` (and the semco/sunny copies) is only the Chromatix *schema* (588 slaveAddr/registerData/delayUs
  descriptors, 72 B each, whole file = descriptors, no values). It contains no register values.
- `memdump/r*.bin` (251 regions): the only SMIA-looking hits are address lookup tables (`0x136,0x136,0x137,0x137,...`
  and `0x340,0x340,0x341,...` at r99/r127 offsets 0x5199c / 0x529ec) - pairs of addresses, no data.
- Byte-pattern searches for the EXTCLK write (reg 0x0136 = 0x18, 0x00) in LE/BE, 3/4/8-byte records over the memdump,
  camera.qcom.so, sensor_imx586.so, tuned_/semco_ bins: no hits. The vendor's tables are not stored in a form we can
  find by value; they are compiled into the HAL or built at runtime.
Not tried: disassembling camera.qcom.so / sensor_imx586.so (REA) for the register arrays, or capturing the CCI writes
live on the vendor kernel.

## 2026-11-03 (night) — FIRST IMX586 FRAME: vendor register tables recovered and applied

**Capture works.** `/dev/video0` returned a 15,024,000-byte frame (4000x3000 RAW10, pBAA, stride 5008); decoded it is a real image
(creased white fabric; raw range 62-88, black level ~64) - `docs/imx586-first-frame.png` (crude demosaic, no black-level/WB).
What fixed it: the sensor was not given the vendor's register set. Recovered from the Ofilm `*_sensormodule.bin`
(Chromatix binary; 8-byte-field records: a 10-qword record per register `[id,0,id+1,ADDR,1,id+2,2,1,0,1]`, and the data
array after each block as `[value,0]` pairs at `block_end+1`): an init block (103 regs, starts 0x0136=0x18) and five mode
blocks (93 regs each: 8000x6000, 4000x3000, 4000x2250, 2000x1500, 1920x1080). Tables: `patches/proposed/imx586-vendor-tables.h`
(init + 4000x3000). Vendor values: 0x0114=3 (4 lanes), EXTCLK 0x1800, 4000x3000 PLL 0x301=5 0x303=4 0x305=4 0x306/7=0x0158
0x30b=1 0x30d=0x0c 0x30e/f=0x023e 0x310=1, LL 0x2310 FL 0x0bf8, bin 0x0901=0x22 - the 0x3xxx/0x4xxx/0x9xxx tuning blocks
were the missing part (our guessed PLL used 0x30d=4/0x30e=0x129). Driver: `smia=1` writes init then mode, then 0x0100=1;
LINK_FREQ constant changed to 574 MHz (DT still says 891 MHz; the driver accepts either until the DTB is reflashed).
Setup that produced it: csiphy0, 4 lanes, `smia_lanes=3`, csiphy0 -> csid0 -> vfe0_rdi0 -> video0, SBGGR10 4000x3000.
LESSON (cost two invalid runs): **wireplumber opens /dev/video* and /dev/media0**, so `rmmod qcom_camss imx586` silently fails
("in use") and `insmod` then fails with "File exists" - the test runs the OLD module. Stop wireplumber (kill, then relaunch
as `user` with `/var/tmp/wp.env`) before reloading, and check `insmod` output. The earlier "vendor table" run before this was
therefore invalid, and the E1 result stands (only the first load after boot used the new .ko).
Also: no `pkill -f` over ssh (it matches its own command line).
Open: DT link-frequency 574 MHz + reflash; modes other than 4000x3000; exposure/gain/black level; M3 libcamera/app.

## 2026-11-03 (night) — IMX586 capture from a clean boot (boot-mainline-cam-final.img)

DT `link-frequencies` = 574 MHz (both dtsi copies), driver strict on 574 MHz, `smia_lanes` default 3. `imx586.ko` installed at
`/lib/modules/7.2.10-sm6150/extra/imx586.ko` (+ depmod): it autoloads at boot and prints `IMX586 detected (id 0586)`. Flashed
`boot` only (fastboot entered via the raw reboot syscall); rollback `boot-mainline-cam.img` / `boot-mainline-186-rollback.img`.
Without touching any module, `/var/tmp/cap.sh` (link csiphy0->csid0->vfe0_rdi0, SBGGR10 4000x3000, exposure=3000) returned a
15,024,000-byte frame; rendered with black level 64 + gray-world WB it is a clear picture (`docs/imx586-first-frame.png`: plastic
over weave, sharp). Raw range 63-103 -> badly underexposed (signal ~12/1023 over black): exposure/gain control path not yet checked
(frame length 0x0bf8 vs ctrl writes lpfr=3070; verify 0x0202/0x0204 actually apply). Not done: other modes, AE, libcamera/app (M3),
flat-field/colour. Capture helper on the phone: `/var/tmp/cap.sh [exposure] [gain]`; unpacking/render snippet is in this session's notes.

## 2026-11-03 (night) — exposure/gain verified; libcamera streams the IMX586

- Exposure and analogue gain apply: mean raw level (black 64) with exposure,gain = 200,0: 64.2; 1500,0: 65.3; 3000,0: 66.6;
  3000,600: 70.2; 3000,900: 85.0; vblank 12000 with exposure 12000: 74.2 (88.7 at gain 600). The earlier dark frame was a dim
  scene plus the short default exposure, not a broken control. A longer frame (V4L2 vertical_blanking) is needed for exposures
  past ~3000 lines.
- libcamera 0.7.2 (`simple` pipeline handler + software ISP with GPU debayer on FD612) is already installed; `libcamera-tools`
  added with apk. `cam -l` lists `imx586`; `cam -c1 --capture=5` streams 4000x3000 at ~6.1 fps (bytesused 48,384,000 = BGRX 4032-px
  stride), AE range exposure 8-14978, gain 0-978. `docs/imx586-libcamera-frame.png` is a real scene (red/blue swapped in my
  render only: BGRX read as RGB). Warnings to fix for a polished stack: the driver lacks the selection rectangles
  (V4L2_SEL_TGT_CROP/_DEFAULT/_BOUNDS), V4L2_CID_CAMERA_ORIENTATION/LOCATION, a libcamera `imx586` sensor-properties/helper
  entry (soft IPA: "Failed to create camera sensor helper for imx586", so AE/gain are uncalibrated - the image is dim).
- Next (M3): add the selection/orientation controls to the driver, a CameraSensorHelper + properties for imx586 in libcamera (or a
  local override), then try GNOME `snapshot` (installed). wireplumber must be left running; do not rmmod the camera modules
  while it holds them.

## 2026-11-03 (night) — M3: live preview verified in the real camera app (GNOME snapshot)

Driver got selection rectangles (8000x6000) and the fwnode orientation/rotation controls; DT `orientation = <1>`, rotation. Flashed
`boot-mainline-cam-m3.img` (rotation 90): libcamera lists "Internal back camera", the kernel-side warnings are gone.
Launched `snapshot` 51.0 in the user session (needs the session bus address from `phosh`'s environ in /var/tmp/wp.env, `setsid`,
and an unlocked phone - lock screen password is the user's) and captured the phone screen over VNC: a sharp live preview of the
laptop on the desk, **but rotated 180 degrees** -> DT `rotation = <270>` (`boot-mainline-cam-m3b.img`). Colour is bluish
(uncalibrated, no sensor helper / CCM / WB in libcamera's soft ISP). VNC capture: tunnel script in the scratchpad; the tunnel binds
[::1]:5901 only, so use `vncdo -s localhost::5901`.

## 2026-11-03 (night) — vendor colour data applied: libcamera `imx586.yaml`; "no cameras found" incident

Colour: `tuned_ofilm_imx586.bin` (vendor Chromatix) holds the cc13 colour-correction table as 18-float records (9-float 3x3 CCM, then a
CCT trigger range). Extracted 5 CCMs (1-2450 K, 2800-3000, 3600-4200, 4700-5300, 5800-10000 K; first AEC set) into
`phone/imx586.yaml` (+ BlackLevel 4096), installed as `/usr/share/libcamera/ipa/simple/imx586.yaml`. Result via `cam`: natural colours
(yellow bananas, green bottle, orange lid) - `docs/imx586-libcamera-tuned.png`; the earlier blue cast is gone. Not used yet: gamma
(`mod_gamma15`), lens shading (`lsc34`), black level (bls12 - 4096 assumed from the measured 64/1023), per-unit EEPROM calibration (0x50/0x51).
Incident: GNOME Camera said "no cameras found" because my manual `kill` + relaunch of wireplumber (to make PipeWire re-read the tuning)
left **no wireplumber running**; relaunching with a hand-built environment also died within seconds - it must be started with PipeWire's own environment (see `phone/` `wp.sh` approach: copy XDG_*/DBUS_SESSION_BUS_ADDRESS from /proc/$(pgrep pipewire)/environ, `setsid`). PipeWire's libcamera monitor lives in wireplumber, so no
camera node existed. Fix: `setsid` + `< /dev/null` (`/var/tmp/wp.sh`); node `imx586 [libcamera]` is back. A reboot also restores it
(autostart). Rule: after touching wireplumber, check `wpctl status` shows the camera before telling the user to try the app.

## 2026-11-03 (night) — "blue" colour: the binned mode's CFA is RGGB, not BGGR

User reported the app preview was blue and that a lid that is red in real life appeared blue. A direct RAW10 capture (v4l2, no libcamera)
rendered with both Bayer orders settled it: read as RGGB the red/orange lids, orange snack and red-brown cloth are right; read as
BGGR they are blue. The vendor 4000x3000 binned mode therefore outputs **RGGB**; the driver had declared SBGGR10. Fix: `mode.code =
MEDIA_BUS_FMT_SRGGB10_1X10` (`patches/proposed/imx586.c`); module reinstalled and swapped live (wireplumber stopped, `rmmod qcom_camss
imx586`, `modprobe`, wireplumber restarted from PipeWire's environment - `/var/tmp/swap.sh`). Capture/render helpers must now use
`pRAA` / RGGB; libcamera's `cam` and the app need no changes. Earlier "natural colour" judgement of the `cam` frame was made after an
RGB/BGR flip of my own and was wrong; the app screenshot + red lid is the ground truth. Not yet re-verified in the app after the fix
(phone was in use). Also: `cam` cannot open the camera while the app/wireplumber stream is active (it hangs until timeout) - close the app first.

## 2026-11-03 (night) — colour verified in GNOME Camera; why "No Camera Found" kept happening

- **Colour fixed and verified in the app** (UI over VNC, user's lid/jar): with the driver advertising SRGGB10 the preview shows the orange jar lid,
  the red-brown tablecloth and the steel flask correctly; neutral surfaces neutral. (`libcamera` Ccm tuning + RGGB fix.) Still open: the image looks
  hazy/low-contrast (no gamma/contrast curve yet), it opens dark and takes seconds to brighten (the soft IPA's AGC starts from a minimum exposure and
  there is no libcamera sensor helper for imx586), no autofocus (VCM at 0x0c on CCI1 not driven).
- **Root cause of the disappearing camera node:** elogind (`10-violet.conf`: `KillUserProcesses=yes`) sends SIGTERM to every process of an ssh
  session when it ends, including `setsid`/`nohup` ones. Found with `strace -e signal=all` on wireplumber (`SIGTERM si_pid=<elogind> si_uid=0`).
  The libcamera monitor lives inside wireplumber, so each ssh-launched wireplumber died within seconds-to-a-minute and the app showed
  "No Camera Found" / closed. Fix: start wireplumber via the session D-Bus (service file `org.violet.WirePlumber.service`), which puts it in the
  graphical session's cgroup `/c1`. A reboot restores the stock autostart. (Memory note: reference-violet-ssh-processes-die.)
- Working over WiFi: ssh user@<lan-ip> (USB-NCM interface name/addresses keep changing).

## 2026-11-03 (night) — dark start fixed; gamma/contrast cannot come from the tuning file

- Dark start: the soft IPA starts from the sensor's current exposure/gain, so the driver defaults matter. `IMX586_EXPOSURE_DEFAULT` 1608 -> 2800 and
  `IMX586_AGAIN_DEFAULT` 0 -> 500: in GNOME Camera the median luminance at 5 s after tapping the icon is already 93 (steady state 91 at 10 s).
  (Before: it opened dark and brightened over seconds.)
- Vendor gamma15 table (tuned_ofilm_imx586.bin @0x4e90c: 65 points 0..1024, effective exponent ~0.61, i.e. less lifted than sRGB) found, but libcamera's soft
  `Adjust` algorithm takes gamma/contrast from application controls, not from `imx586.yaml`; adding `gamma:`/`contrast:` to the yaml changed nothing
  (measured p1/p99 identical) so they were removed. The soft ISP only honours BlackLevel, Awb, Ccm, Agc (and Adjust's controls) from the yaml.
- Residual: the preview is somewhat hazy/low-contrast (blacks ~34/255, highlights ~165/255); candidates are the missing lens-shading/tone data or real lens haze.
- Tooling: `opencam.sh` (scratchpad) = VNC wake + swipe-up unlock + tap Camera + shots at 2/5/10 s; `swap2.sh` live-swaps imx586.ko and restarts wireplumber via D-Bus.

## 2026-11-03 (night) — rear-main module EEPROM read (factory calibration)

CCI bus 1 (i2c-3), 16-bit register addressing, CCI reads limited to 8 bytes per message (16 -> ENOTSUPP; `phone/camera-cal/i2cr.py`, `eepdump.py`,
plain /dev/i2c-3 ioctls, no i2c-tools needed). Two 8 KB banks, both alias at 0x2000: `0x50` has ~2 KB of data at 0x0000-0x07ff (header
`01 07 13 05 17 07 15 06 3e ff ff ff 1a 2d 04 01 ...` then 16-bit big-endian grids from 0x80) and `0x51` is fully populated (the second half of the
16 KB part). Dumps: `phone/camera-cal/rear-main-eeprom-0x50.bin`, `-0x51.bin`. The Qualcomm CAMX layout for this Ofilm module lives in the HAL's
compiled eeprom map, so the field offsets are not documented here yet.
Consumability: libcamera's soft ISP (0.7.2) takes only BlackLevel, Awb (gray-world, no tuning keys), Ccm and Agc from the tuning file - there is no
lens-shading or per-unit white-balance input, so the EEPROM LSC/AWB data cannot be applied through the tuning file. Using it would need a custom
shader/ISP stage (GPU debayer) or a libcamera patch.

## 2026-11-03 (night) — rear aux (Samsung S5K5E8) and front (OmniVision OV13855) cameras brought up; all three verified in GNOME Camera

Identification (from the vendor HAL strings and `vendor.img`, extracted with `debugfs` into `~/violet-ios/cam2/`): **rear aux = S5K5E8**, **front = OV13855**
(DW9767 VCM, PDAF). Both have `com.qti.sensormodule.<module>_*.bin` data in the same Chromatix format as the IMX586 (parser: `patches/proposed/gen/modparse.py`):
S5K5E8 ofilm = 35-reg init + 4 modes (2592x1944, 1296x972, 1304x980, 800x600, 60 regs each, 2 lanes) + stream seq; OV13855 ofilm = 212-reg common init + modes 4224x3136 / 2112x1568 (4 lanes).
Wiring measured on the phone (scan in the driver probe, rails/clock/reset like the imx586 recipe):
- **front OV13855**: I2C 0x36 on **CCI master 1 (i2c-3)**, chip id read at 0x300b = 0xd855, reset TLMM 37 (active low), MCLK2, **csiphy2, 4 lanes**.
- **rear aux S5K5E8**: I2C **0x18** on **CCI master 0 (i2c-2)** (not 0x10; id 0x5e80 at reg 0x0000), reset TLMM 45, MCLK1, **csiphy1, 2 lanes**. The vendor DT's cci-master numbers for sensors do not match reality (imx586 also differs).
- rails shared with the main camera (vana1_2 gpio4, camera_ldo gpio3, l13a). The VCM at 0x0c / EEPROM 0x50/0x51 belong to the main camera (CCI1).
Drivers: generated from one template (`patches/proposed/gen/gen_sensor.py` -> `s5k5e8.c`, `ov13855.c`; single mode each: S5K5E8 1296x972 SGRBG10 336 MHz link, OV13855 2112x1568 SBGGR10 360 MHz link), DT in `dt/violet-sm6150-camera.dtsi`
(CAMSS ports 0/1/2 = main/aux/front). Modules in `/lib/modules/7.2.10-sm6150/extra/`. Boot image `boot-mainline-cam-multi2.img` was written to `boot` **over WiFi with dd**
(no USB cable: backup `device-backup/boot-before-multi-cam.img`, md5 verified, partition 64 MiB) - fastboot remains the rollback path.
libcamera now lists 3 cameras (`Internal back camera` x2, `Internal front camera`) and GNOME Camera shows a switch button: **front, aux and main were each verified streaming in the app**
(UI over VNC). Tuning: `phone/s5k5e8.yaml`, `phone/ov13855.yaml` (vendor cc13 CCMs by CCT range from `com.qti.tuned.ofilm_*.bin`, black level 4096).
Not done / known limits: single mode per sensor; no autofocus (main camera VCM at 0x0c, aux VCM at 0x0c? on CCI0 not driven; front DW9767 not driven); orientation of aux/front not verified
(DT rotation 270 is a guess for both); CFA order of the new sensors was guessed (S5K5E8 GRBG, OV13855 BGGR) and looks right; no lens-shading/gamma: libcamera's soft ISP cannot consume them.

## 2026-11-04 — violet-qg replaces violet-vbat (vendor profile, batt-id, real temperature)

`patches/qg/violet-qg.c` (+ `gen_profiles.py` -> `violet-qg-profiles.h`) replaces `violet-vbat`: the three vendor LC_M6300 profiles, discharge/charge SoC-OCV tables, capacity vs temperature (4016 mAh at 29 C, was a hard-coded wrong 3580), cutoff/float rescaling, hold-99/hold-1 and msoc catch-up as in downstream qg-soc.c, PON from S7 OCV or the stored SDAM SoC. The vendor SoC estimator is a closed userspace piece, so the coulomb-counting/OCV estimator is ours.
DT: `bat_therm` (0x4a) and `bat_id` (0x4b) channels on pm6150_adc, flashed as `boot-mainline-batt.img` (backup `device-backup/boot-before-batt-20261104.img`). `patches/qg/0001-iio-adc5-add-bat_therm_100k_pu.patch` adds the missing bat_therm table entry to qcom-spmi-adc5 (module, installed; original kept as `.zst.orig`). bat_id reads 767906 uV = 69 kOhm -> ATL profile (68k), selected automatically. Old module kept as `violet-vbat.ko.zst.bak`.

## 2026-11-04 — charger policy + `usb` supply in violet-qg

Live register dump (read-only, debugfs regmap `0-00`): SBL already programs hardware JEITA (0x1090=0x1b, thresholds 0x94-0x9b close to the vendor LC_M6300 soft/hard values), float voltage 0x1070=0x50 (4.4 V), safety timer 0x10a2=384 min, termination/recharge thresholds. So JEITA/termination/recharge are enforced in hardware and left untouched (see asidko "registers not to touch").
Added to `patches/qg/violet-qg.c`: input-path sequence re-run on every plug-in with the limit chosen from APSD (SDP 500 mA, CDP 1.5 A, DCP/float/OCP `icl_max_ma`=1800), `usb` power supply (online, usb_type, current_max, supplies `battery`), battery `status` from the charger state machine (TERM -> Full, PAUSE/DISABLE/INHIBIT -> Not charging), `health` from CHGR_STATUS7 (cold/cool/warm/overheat), poll 2 s. Not done: unplug/replug and SDP behaviour (phone was on the laptop port the whole time, APSD = float), Type-C Rp current, PD/QC, thermal mitigation tables.
Replug test (2026-11-04 22:34): unplug seen as plug=0 with the pack discharging (-47 mA), replug re-ran the input-path sequence (`apsd=0x10 -> icl 1800 mA, read back 1800, mode_chg=1`), battery went Full -> Charging (CHGR_STATUS1 = fast charge), `usb` online=1. The laptop port still detects as FLOAT, so the SDP (500 mA) branch has not been exercised.

## 2026-11-04 — discharge test of violet-qg (first on-battery run)

First run exposed a real bug: at a 2 s poll the coulomb increment is < 1 unit of batt_x100, so the integer division truncated it to zero and the counted SoC never moved (99.00 flat for 12 min at ~100 mA). Fixed with a sub-unit remainder carry (`cc_rem`); the rest/rescue corrections now scale with dt (~100 s time constant) instead of a fixed /20 per poll.
Second run (~10 min at 0.5-1 A, then ~5 min rest, unplugged, logs read over WiFi <phone-lan-ip> — reachable once the phone's WiFi leaves power-save, first ping takes 1-2 s): counted SoC fell 0.31 %/min at 0.75 A (physics: 0.75 A / 4015 mAh = 0.31 %/min), reported capacity stepped 100 -> 99 -> 98 -> 97 one point at a time ~40 s apart, pack 29 -> 34.9 C. At rest the OCV estimate (95.4-96.1) and the counted value (95.66-95.8) agree within ~0.4 point. Under load the V - I*Rbatt estimate reads 2-3 points low, as designed (not used for correction under load).

## 2026-11-05 — Type-C PD (sink-only) works; PMIC needs the 9 V window

`boot-mainline-typec.img` (backup `device-backup/boot-before-typec-20261105.img`): `&pm6150_typec` enabled sink-only (`power-role = "sink"`, `data-role = "device"`, `sink-pdos` 5 V/3 A + 9 V/3 A, `vdd-pdphy-supply = L17`), no vbus-supply, not linked to the dwc3 role switch (USB gadget unchanged). `qcom,pmic-typec` binds, `/sys/class/typec/port0` + `port0-partner` appear, PD 3.0.
Moto TurboPower 68 W offers: 5 V/3 A, 9 V/3 A, 15 V/3 A, 20 V/3.4 A, PPS (3.3 V.., 5 A / 3.4 A). The sink requested 9 V/3 A -> `tcpm-source-psy-c440000.spmi:pmic@0:typec@1500` voltage_now 9000000.
Problem found: at 9 V the SMB5 flagged USBIN over-voltage (`0x1310` bit 3), charge state PAUSE (`0x1006` = 6), battery "Not charging" while on the charger. Cause: USBIN_ADAPTER_ALLOW_OVERRIDE (`0x1344`) was 0, so the PMIC only accepts the 5 V window. Fix in `violet-qg.c`: follow the tcpm supply (notifier + poll); contract 9 V -> `0x1344` = FORCE_9V (0x02), 5 V -> FORCE_5V, anything else -> 0 (hardware default, PMIC protects itself); cleared on unload. After the write: OV bit clear, state taper, battery Charging +469 mA at 4.40 V. Not done: switcher frequency per voltage (vendor 1050 kHz at 9 V, default left), ICL above 1.8 A, requesting 15/20 V or PPS, fast-charge current measurement from a low SoC.
Cold reboot with the PD charger plugged in (2026-11-05 00:17): module autoloaded, batt-id 68 kOhm -> ATL, PD contract 9 V/3 A, `0x1344` = 0x02 written at probe, `0x1310` = 0x10 (no OV), state taper, battery Charging. Observed side effect: between boot and module load the charger is paused on over-voltage and the phone runs from the pack (~1 A for a few seconds; SoC 96 -> 95 %). Docs updated the same day: README.md/STATUS.md (charging row, "do not trust yet"), CHECKLIST C1, patches/README.md, HANDOFF-PROMPT.md, dt/README.md (snapshot `violet-sm6150.dts.20261105-typec`). Next (planned 2026-11-05): drain the pack, plug the PD charger, log charge current/temperature over WiFi; then decide ICL / 15-20 V / PPS.

## 2026-11-05 — rear torch works (DT only)

`boot-mainline-torch.img` (backup `device-backup/boot-before-torch-20261105.img`): `&pm6150l_flash` enabled with one `led-0` node, `led-sources = <1>, <2>` (vendor flash/torch ids 0 and 1, the dual rear LED), `led-max-microamp = 500000` (torch cap, vendor allows 2 x 900 mA), `flash-max-microamp = 1800000`, `flash-max-timeout-us = 1280000`. The built-in `leds-qcom-flash` driver binds; `/sys/class/leds/white:flash` appears (brightness 0-255 = torch, flash_brightness/flash_strobe/flash_timeout for strobe). User confirmed by eye: writes of 25 and 100 lit the LED at two levels, 0 turned it off. `brightness` is `root:feedbackd 0664` and the user is in `feedbackd`, so no udev rule is needed. Not done: camera strobe (needs `CONFIG_V4L2_FLASH_LED_CLASS`, not set), front flash (channel 3 + enable GPIO), raising the torch cap, checking Phosh's flashlight toggle.
Phosh torch tile (2026-11-05): Phosh 0.57's torch manager scans LEDs named `*:torch*`/`*:flash*` and reads `GM_TORCH_MIN_BRIGHTNESS` from udev; gmobile's torch hwdb has no violet entry, and its udev rule (`61-gmobile.rules`) builds the key from `$attr{[devicetree/base]compatible}`, a path that does not exist on this kernel (`/sys/class/devicetree` is absent), so the key ends in `dt:`. Added `/etc/udev/hwdb.d/61-violet-torch.hwdb` on the phone (`gmobile:name:white:flash:dt:*` -> `GM_TORCH_MIN_BRIGHTNESS=10`), `udevadm hwdb --update`, `udevadm trigger --subsystem-match=leds`, restarted greetd. The torch tile now appears in quick settings (user-confirmed). Not yet confirmed: that the tile switches the LED and its brightness slider. Undo: delete the file + `udevadm hwdb --update`. The file lives only on the phone (not in the image); keep a copy in `phone/` if the rootfs is rebuilt.
Torch end to end (2026-11-05): user confirmed the Phosh tile switches the LED and its brightness control works. The torch is done apart from the camera strobe (needs `CONFIG_V4L2_FLASH_LED_CLASS`) and the front flash.
Correction (2026-11-05, same day): the wildcard hwdb entry above (`gmobile:name:white:flash:dt:*`) was a workaround for a lookup that does not resolve here, and was replaced. `/etc/udev/hwdb.d/61-violet-torch.hwdb` was removed; `/etc/udev/rules.d/61-violet-torch.rules` (copy: `phone/61-violet-torch.rules`) sets `GM_TORCH_MIN_BRIGHTNESS=10` only on the LED whose `OF_FULLNAME` is `/soc@0/spmi@c440000/pmic@5/led-controller@d300/led-0`. Root cause of the empty key is not proven: gmobile's rule uses `$attr{[devicetree/base]compatible}`, the phone's udev is 251; the likely cause is that this udev cannot resolve that path. Proper long-term fix: confirm that and submit a violet entry upstream to gmobile (or fix the lookup), then drop the local rule.

## 2026-11-05 — 3.5 mm headphone playback: CLAIMED working here, but this entry is WRONG

> **CORRECTION (2026-11-06).** The "works" conclusion below was false. The two pieces of evidence it rested on
> did not hold: (1) the mic RMS 8218 "proof" was ambient noise - at that ADC gain the floor is 5-7k, and the
> later A/B showed baseline higher than "playback"; (2) the "companders gated the DAC" story was never isolated.
> The real blocker was the front end: **MultiMedia3 into the codec-DMA port is silent on this firmware**; only
> MultiMedia4 reaches the WCD9375. The by-ear L/R confirmation from that day is therefore suspect as well - the
> configuration in use now (MM4 + two sinks + default-sink switching) is the one verified by ear on 2026-11-06.
> Kept below only as a record of what was believed at the time.

The headphone route added earlier (MultiMedia3 -> `RX_CODEC_DMA_RX_0` -> rx_macro -> `swr1` -> WCD9375 HPHL/HPHR)
was correct; the silence was the **codec compander**. With `HPHL_COMP`/`HPHR_COMP` enabled the compander wants its
control stream on SoundWire data port 3, which a 2-channel stream never carries, so the R-DAC output is gated and the
jack only clicks. Turning both codec COMP switches off (and the macro `RX_COMP1/2`) produced sound immediately; no
DT, port-table or pad change was involved (the earlier RX-port-table and RX-pad experiments were chasing the wrong
layer, and are harmless: they now match the working qcm6490/qcm6490 tables).

Evidence:
- Codec register access finally obtained read-only: the RX slave's `wcd937x_csr` regmap is not registered, but the
  **TX** slave's is (`/sys/kernel/debug/regmap/sdw:3:0:0217:010a:00:3-wcd937x_csr/registers`); the analog space is
  visible there. Idle -> during playback: `0x3008` 00 -> c1 (RX supplies), `0x3009` 0c -> f4 (HPHL/HPHR PA),
  `0x30c9/0x30ca`, `0x3465/66` follow; with COMP off `0x3414` = 00 instead of 03.
- Subjective: the user heard the trimmed "Demons" clip through the earbuds, full scale, **left in left ear and right
  in right ear**.
- Objective: the phone's own mic, with the earbud on the phone, recorded the same clip at AC RMS 8218 (peak 16384)
  while the TAS speaker amp logged no activity at all, so the sound was the jack and not the speaker.
  (Note: at max ADC gain the mic also picks up room noise ~5-6k RMS, so only a large delta over the idle floor is
  meaningful.)
- Desktop path: PulseAudio's sink `violet_speaker` is `module-alsa-sink device=hw:0,2` — the same PCM — so any app
  follows the route live. Verified at app level: `paplay` played the clip, and Firefox streaming
  (`pactl list sink-inputs` -> `application.name = "Firefox"`, `media.name = "AudioStream"`, sink `RUNNING`).

Tooling (installed on the phone and copied to `phone/`): `violet-hph [jack [N]|speaker|status]` sets the route and
full-scale levels (HPH 20/20, RX digital 124/124 = 0 dB); `violet-hph speaker` reverts. Helper scripts:
`phone/codec-live.sh` (codec register diff during playback), `phone/hph-where.sh` (jack vs speaker, mic-measured),
`phone/swr-master-regs.sh` (SWR master dumps), `phone/hph-regs.sh`.

Still missing — jack auto-switch: `Headphone Jack` reads **off** with the headset plugged in, so MBHC never reports
the plug. `MBHC Switch` starts off and has to be set by hand. Next step (needs one boot flash): add the MBHC DT
properties the reference boards carry (`qcom,hphl-jack-type-normally-closed`,
`qcom,ground-jack-type-normally-closed`, mbhc button/threshold set), make the codec start MBHC at probe, and wire a
route switch (PulseAudio profile or a small listener on the jack kcontrol).

Screenshot tooling for this phone (grim is a 0-byte binary): `gdbus call --session --dest org.gnome.Shell.Screenshot
--object-path /org/gnome/Shell/Screenshot --method org.gnome.Shell.Screenshot.Screenshot false false /tmp/shot.png`
with `DBUS_SESSION_BUS_ADDRESS=unix:path=$(grep -o '/tmp/dbus-[^ ]*' /proc/net/unix | head -1)` and
`XDG_RUNTIME_DIR=/run/user/10000`. `wf-recorder` fails (VAAPI probe).

## 2026-11-05 — jack auto-switch: UCM profile + SoundWire wake IRQ (plug test pending)

Two proper pieces instead of the hand-run `violet-hph` / `violet-audio-setup` scripts:

1. **UCM2 profile** (`phone/ucm2/Xiaomi/violet/{violet,HiFi}.conf`, symlink `conf.d/sm8250/Xiaomi Redmi Note 7 Pro.conf`; installed on the
   phone under `/usr/share/alsa/ucm2`). Devices: `Speaker` (MM3 -> PRI_MI2S_RX -> TAS2563), `Headphones` (MM3 -> RX_CODEC_DMA_RX_0 -> rx_macro -> swr1 ->
   WCD9375, compander switches OFF, `JackControl "Headphone Jack"`, `JackHWMute "Speaker"`), `Mic`. PulseAudio's udev-detect now loads the card with UCM,
   creates `alsa_output.platform-soc_0_sound.HiFi__Speaker__sink` / `...HiFi__Mic__source`, and watches the jack: "Headphone Jack is now unplugged" in its log.
   `/etc/xdg/autostart/violet-audio.desktop` was retired (moved to `/root/violet-retired/`; script copy `phone/violet-audio-setup`).
   Gotchas: (a) the verb must enable a default route (`PRI_MI2S_RX ... MultiMedia3`), because PA opens the PCM while probing the profile and MultiMedia3 refuses to
   open with no back-end ("Failed to find a working profile"); (b) with the UCM `ctl-remap` include, `amixer -c 0 cget name=...` fails ("sysdefault:0"), use `amixer -D hw:0`.
2. **Why MBHC never reported a plug**: the headset-detect interrupts are SoundWire in-band interrupts of the WCD9375 TX slave (swr2). Vendor swr2 has a dedicated
   wake interrupt (`swr_wake_irq`, SPI 623, `qcom,swr-wakeup-required`) that brings the bus out of clock stop; mainline `swr2` in `violet-sm6150.dts` had only the core
   IRQ (the comment even said "wake 623"), so a plug while the bus idled was never delivered (`mbhc sw intr` only counted when audio happened to wake the bus).
   Added `interrupts = <137>, <623>; interrupt-names = "core", "wakeup"`. The `qcom,*-jack-type-normally-closed` props suggested earlier are WRONG: vendor
   `qcom,msm-mbhc-hphl-swh/gnd-swh = <1>` = normally open = the mainline default. Registers confirm MBHC is armed (0x3014=bd: L_DET_EN, NO, insertion detect).
   Image `boot-mainline-swrwake.img` (DTB-only change; backup `device-backup/boot-before-swrwake-20261105.img`; DT snapshot `dt/violet-sm6150.dts.20261105-swrwake`).
   After boot: `/proc/interrupts` shows `swr_wake_irq`. Plug test: pending (needs a headset in hand).

## 2026-11-05 (later) — jack auto-switch: instrumented-verified end to end, NOT yet verified by ear

Plug test at 22:26 (earbuds with mic): kcontrols `Headphone Jack`+`Mic Jack` on, HPH Type stereo (46/45 ohm), PulseAudio profile -> `HiFi (Headphones, Mic)`,
default sink -> `...HiFi__Headphones__sink`, active port Headphones; unplug 17 s later: all off, profile/sink/port back to Speaker. All from logs/controls (`logs/hph-2026-11-05/watch7.log`);
nobody has yet listened to the earbuds after an automatic switch, and the headset mic is not wired into the profile.
Findings, in order:
1. SoundWire TX wake IRQ (SPI 623) missing in `violet-sm6150.dts` -> plug events not delivered while the bus idled (`dt/...20261105-swrwake`).
2. `wcd-mbhc-v2.c`: `hph_status` accumulated HEADPHONE|LINEOUT; removal cleared one -> jack stuck on (`patches/0041-asoc-wcd-mbhc-clear-all-plug-types-on-removal.patch`).
3. Headset ceiling: vendor `qcom,msm-mbhc-hs-mic-max-threshold-mv = 2550`; mainline default 1700 mV classified the mic earbuds (idle ~1950 mV) as line-out. DT `qcom,mbhc-headset-vthreshold-microvolt = <2550000>`.
4. One playback front-end for two outputs cannot work with UCM: PA opens the new device's PCM before enabling the device, and MultiMedia3 will not open with no back-end routed.
   Added MultiMedia4 (DT `dai@3` + `mm4-dai-link`, `dt/...20261105-mm4`); Speaker = hw:0,2, Headphones = hw:0,3, both routes enabled in the verb.
5. OPEN: `module-switch-on-port-available` is not loaded in the running session after boot (loads fine in an isolated pulseaudio with the same default.pa, and by hand);
   without it the profile does not follow the jack. `phone/50-violet-jack.pa` drop-in did not fix it. The 22:26 test had the module loaded by hand.
Images: `boot-mainline-jack.img` is flashed (final: no DBG prints). Backups: `device-backup/boot-before-swrwake-20261105.img` is the pre-work boot.

## 2026-11-06 — SWR RX bus "link failed to connect" after idle (investigation, nothing changed yet)

Observed after a clean boot: ~100 s idle, then first playback to the Headphones sink: `swr1: swrm_wait_for_frame_gen_enabled: link status not disconnected / link failed to connect`,
RX slave `sdw:2:...:4` UNATTACHED, every stream -> `DPN_PortCtrl register write failed` (-5). Not yet reproduced deliberately; not yet A/B-tested against the pre-LOHIFI profile.
Prior art (web search, memory rule "research first" — this was skipped earlier in the session):
- qcom soundwire runtime-PM patch: "link failed to connect" is only logged before `sdw_bus_exit_clk_stop()`; it is a symptom, not a root cause (lkml.iu.edu/hypermail/linux/kernel/2202.2/09523.html).
- Johan Hovold, X13s (2023): slaves stuck UNATTACHED, tied to runtime PM / clock-stop changes (lkml.org/lkml/2023/6/5/303).
- wcd9378 review thread: codec does not recover from bus clock-stop; downstream workaround keeps the slave runtime-active (lkml.iu.edu/2607.3/10373.html).
- wcd937x-sdw "unbalanced pm_runtime_enable" fix (0ffc5a40): already present in this tree (`pm_runtime_set_suspended` at end of probe).
Candidate fixes, NOT applied: RX slave `clk_stop_mode1` (as wsa881x) vs keeping the RX slave runtime-active while the card is bound. Needs a deliberate repro first.

## 2026-11-06 — correction + Opus analysis of the SoundWire races (nothing flashed)
Correction: a command the user rejected still applied its source edit (RX `clk_stop_mode1` in wcd937x-sdw.c + patches/0042). It was never built or flashed (running kernel = boot-mainline-jack.img);
reverted the source and deleted patches/0042 on 2026-11-06 00:5x. Do not reintroduce it as a fix: it is a workaround and the vendor runs mode0 on both masters.
Opus read-only analysis (hypotheses, only the first two checked against the tree by me):
- (B) TX slave "Slave 1 initialization failed: -5" at ~17 s => INTMASK1 never programmed => MBHC irq dead for that boot. Likely reset race: DT `wcd937x_reset_active` has `output-high`
  (violet-sm6150.dts ~1353) releasing the codec before the driver's reset pulse; driver requests the GPIO GPIOD_OUT_LOW (wcd937x.c:2916). Upstream boards use output-low / bias-disable only.
- (A) RX slave UNATTACHED after idle clock stop: RX SWR pad config (drive 2, slew-rate 1) came from atoll; vendor sm6150-lpi.dtsi uses drive-strength 8 + bias-bus-hold on clock and data, no slew.
  Local patch 0029 (pinctrl-sm6150-lpass-lpi) may mis-place the slew bits. TX pads, configured like the vendor, survive clock stop.
- Driver gap: wcd937x_sdw_runtime_resume does not wait for slave re-init (first stream after idle fails -EIO).
Cheap non-flash tests proposed: read pinconf-groups for gpio3-5; count "initialization failed" per boot; toggle swr1 power/control on-off 10x.

### 2026-11-06 — non-flash checks (measured, no change to the phone)
- Deterministic repro of (A) without audio: `echo auto/on > /sys/devices/platform/soc@0/<master>/power/control`, 6 cycles each (idle 6 s, resume):
  RX master 62ef0000: 6/6 resumes log "SWR bus clsh detected" and the RX slave ends UNATTACHED. TX master 62ed0000 (control): 6/6 resumes clean, slave Attached.
  Same driver, same codec, same method; only the bus (pads/ports/clock path) differs.
- /sys/kernel/debug/gpio (LPI chip): gpio0-2 (TX) 8 mA keeper; gpio3 (RX clk) 2 mA no pull; gpio4/5 (RX data) 2 mA keeper; gpio6 (codec reset) out, 2 mA (DT asks 16 mA: unsupported value, clamped?).
- Vendor sm6150-lpi.dtsi rx_swr_clk_active / rx_swr_data_active: drive-strength 8 + bias-bus-hold (sleep state: drive 2). Ours: 2 mA, slew 1, clock bias-disable (copied from atoll).

### 2026-11-06 — vendor RX pads flashed (boot-mainline-rxvendor.img): hypothesis REFUTED
RX pads now drive 8 + bus-hold (vendor rx_swr_*_active), slew dropped. Result, same 6-cycle test: RX master still 6/6 "SWR bus clsh detected" and slave UNATTACHED; no change.
Pad drive is not the cause of (A). Kept in DT because it matches the vendor (comment says so), NOT as a fix. Backup of the pre-change boot: device-backup/boot-before-rxvendor-20261106.img (= boot-mainline-jack.img).
Same boot: BOTH slaves logged "Slave 1 initialization failed: -5" at 17.04 s, i.e. same instant on both buses -> supports the codec-reset-race idea for (B) (DT `wcd937x_reset_active` output-high vs driver reset pulse). Not tested yet.
Open for (A): RX vs TX difference elsewhere (port/timing config, rx-macro clock path, swr1 master registers after resume). Next non-flash step: compare master registers/clock enable counts RX vs TX across a resume.

### 2026-11-06 — RX vs TX comparison across suspend/resume (no flash): no root cause yet
- Not deterministic per bus: on one boot the RX master suspend/resume was clean (slave Attached, no clash, clock counts normal); minutes later on the same boot a suspend produced "bus clsh detected" and the slave went UNATTACHED.
- Failing signature (dyndbg trace, RX master, slave already UNATTACHED): every resume -> "SWR CMD error, fifo status 0x3e00010f, flushing fifo" (slave not answering); every suspend -> "SWR bus clsh detected". Master power cycling alone never recovers the slave; a stream start did (earlier test).
- Clock enable counts (clk_summary) before/suspended/after: RX core MCLK/NPL 2->1->2, rx-mclk 1->0->1; TX core MCLK 4->3->4, tx-mclk 1->0->1. Nothing visibly missing on RX. q6afe "Unknown cmd 0x100f6" is logged at each cycle on BOTH buses (TX stays healthy), so not the discriminator.
- No dev_dbg output from soundwire qcom/bus/slave during resume (only the error prints). wcd937x-sdw runtime resume does only a regcache sync (RX has no regmap).
- Still open: what makes the RX slave stop answering after a clock-stop; and the boot-time both-slave init failure (B). Candidate non-workaround steps left: reset-pin DT test for (B); a clock-stop trace from the master registers; a vendor-driver comparison of the swrm clock-stop sequence.

## 2026-11-06 — vendor (downstream) vs mainline sequence diff
Source: github.com/LineageOS/android_kernel_xiaomi_sm6150 branch lineage-21 (tip ae1507a8, Xiaomi-derived), techpack/audio: soc/swr-mstr-ctrl.c, asoc/codecs/wcd937x/wcd937x.c, wcd937x_slave.c, msm-cdc-pinctrl.c. Saved only in the session scratchpad; the violet-pmos tree has no techpack/.
VERIFIED by reading both sides (me, after the Sonnet agent's report):
- (B) vendor wcd937x_probe: `wcd937x_reset(dev); usleep_range(5000, 5010);` with the comment "5msec delay to provide sufficient time for soundwire auto enumeration of slave devices as per HW requirement" before `component_bind_all` (wcd937x.c:2852-2866). Mainline wcd937x_probe goes straight from wcd937x_reset() to component_master_add_with_match() (wcd937x.c:2953-2955), no delay.
- (A) vendor swrm_runtime_resume, clock-stop-mode0 branch: `MCP_BUS_CTRL = 0x2; usleep_range(100,105); state = UP` and nothing else. Mainline swrm_runtime_resume (qcom.c ~1760-1792): BUS_CTRL, then clears + re-enables CLASH_DET, 100 us, frame-gen wait, sdw_bus_exit_clk_stop (slave traffic right away). Mainline's clash handler also permanently masks CLASH_DET until the next resume (qcom.c:774-781).
NOT verified (agent inference): whether the missing 5 ms is the cause of (B); whether the clash/CMD_ERROR in (A) comes from the re-arm + immediate exit_clk_stop window; vendor never applies sleep pinctrl on suspend (not read); stock MIUI code may differ from the LineageOS mirror.

### 2026-11-06 06:5x — 5 ms post-reset delay: built, NOT yet flashed
The vendor-matching `usleep_range(5000, 5010)` after `wcd937x_reset()` is in wcd937x.c (patches/0042-asoc-wcd937x-wait-for-soundwire-enumeration-after-reset.patch, applied 01:09 by an earlier turn; wcd937x.o built 01:10).
Kernel Image relinked 06:53 and packed as boot-mainline-delay5.img (sha256 a4444fe1650b...; includes the vendor RX pad DTB). The phone was last flashed with boot-mainline-rxvendor.img (no delay). Phone not connected at 06:5x; flash + 5-reboot count pending.
Test plan: backup boot, flash, verify hash, 5 reboots: count "initialization failed" (baseline seen on 3 of the last ~5 boots), check "mbhc sw intr" works with a plug.

### 2026-11-06 07:3x — 5 ms post-reset delay: result (boot-mainline-delay5.img, flashed, hash a4444fe1650b verified)
5 reboots, measured ~65 s after each boot: "Slave 1 initialization failed" count = 0, 0, 0, 0, 0. Before the delay, init failures were seen on most boots recently observed in this session
(TX only on one, both slaves on another, none on one; counts were not logged systematically, so the baseline is anecdotal). Supports the vendor-matching delay as the fix for (B); small sample, plug detection per boot not yet checked by a physical plug.
(A) unchanged: RX slave status after ~65 s idle = UNATTACHED, Attached, Attached, UNATTACHED, UNATTACHED (3 of 5 boots show the RX slave not Attached when idle); TX shows Alert (interrupt pending) on all 5.
Next: physical plug test on the current boot; then (A).

### 2026-11-06 07:4x — WORKAROUND: PulseAudio jack policy module loaded from session autostart
Plug cycle on the 5 ms-delay kernel: kernel jack control followed (off at unplug, on at replug, Mic Jack ~7 s later), but PulseAudio stayed on Headphones: the session daemon (autospawned: `pulseaudio --start --log-target=syslog`) has no module-switch-on-port-available, though default.pa:33 loads it and no error is logged.
Loaded by hand it persists. Daemons I start from an ssh session die with the session (KillUserProcesses) and are replaced by a module-less autospawned one, which confused earlier tests.
WORKAROUND installed: /usr/local/bin/violet-pulse-policy + /etc/xdg/autostart/violet-pulse-policy.desktop (copies in phone/). Root cause still OPEN; remove both when found.

### 2026-11-06 08:0x — headphone playback hangs when the RX slave is UNATTACHED; vendor pads NOT the cause
Symptom (user): with the headset plugged, songs do not start at all (speaker plays fine). Cause chain, measured:
- profile/sink switching is fine (watch-final.log: Headphones<->Speaker followed the jack through 2 plug cycles with violet-pulse-policy loaded).
- Stream start to the Headphones sink fails when the RX SoundWire slave (sdw:2...:4) is UNATTACHED: dmesg "WCD937x Playback: ASoC error (-5): snd_soc_link_prepare", "DPN_PortCtrl register write failed for port 1" (330 times in 8 s: PulseAudio retries), paplay times out (rc=124), codec amp regs 0x3008/0x3009 stay 00.
- Image A = delay5 + vendor RX pads: hung on the first test. Image B = delay5 + OLD (atoll) pads (boot-mainline-delay5-oldpads.img, now flashed, hash a4f18a093da1): works right after boot (rc=0, amps on: 3008=c1 3009=fc, no errors) while the slave is Attached, but after ~60-90 s idle the slave is UNATTACHED again and the first play hangs with the same errors. So the RX pads do not explain it; the earlier success was timing (slave still Attached). The vendor-pad DT is kept as dt/violet-sm6150.dts.20261106-delay5-rxvendor, the tree has the old pads again (as flashed).
- Acoustic method (phone mic, 1 kHz Goertzel): control tone through the speaker -> amp 10613 ratio 0.94; earbud tone at 0 dB digital gain not detected at the mic (earbud far quieter than speaker; inconclusive by itself). The codec amp registers are the better indicator.
Open: (A) RX slave drops to UNATTACHED ~60 s after boot when idle and does not come back on stream start (or on master runtime-PM cycling). Candidate (vendor-evidence, untested): mirror vendor mode0 resume (do not re-arm CLASH_DET / no immediate exit_clk_stop traffic), or recover the slave (bus reset) on prepare failure.

### 2026-11-06 08:3x — RX bus failure is the STREAM START, not idling (measured) — and the phone went unreachable
- Pinning the RX master awake (power/control=on) right after boot does NOT keep the slave Attached (Attached at 33 s, UNATTACHED within 10 s, both of 2 boots): clock-stop idling is not the trigger.
- With the UCM profile hidden (PulseAudio cannot load the card), the RX slave stayed Attached for 211 s with zero "clsh"/"clk already disabled" lines. Normal boots show "wcd937x: clk already disabled" at ~34.7 s then "SWR bus clsh detected" at ~38.4 s and the slave UNATTACHED: it is something PulseAudio does when it loads the card (profile probe opens/closes the headphone PCM).
- Hand replay on that clean boot: mixer routes (verb) = harmless; opening the headphone PCM hw:0,3 for 1 s = "write error: I/O error" on the FIRST try with the slave Attached, 1 clash line; a second try -> slave UNATTACHED, 3 lines. So starting an RX SoundWire stream fails/breaks the bus. Candidates now: RX port/stream parameters in the swr1 DT (qcom,ports-* tables), the stream prepare ordering vs codec/RX-macro power-up, the 'DPN_PortCtrl' write path. NOT idle/clock-stop, NOT pads, NOT the 5 ms delay.
- A traced repeat (dyndbg on stream.c/bus.c/qcom.c/slave.c) was started with the UCM profile hidden; the phone did not come back after its reboot (no ssh over USB-link-local or WiFi, NCM gadget enumerates). STATE LEFT ON THE PHONE: /usr/share/alsa/ucm2/conf.d/sm8250/"Xiaomi Redmi Note 7 Pro.conf" is MOVED to /root/violet-ucm-hidden.conf (restore with: sudo mv /root/violet-ucm-hidden.conf "/usr/share/alsa/ucm2/conf.d/sm8250/Xiaomi Redmi Note 7 Pro.conf"). Without it PulseAudio has no card (no speaker/headphone audio).

## 2026-11-06 (21:5x) — jack switching FIXED: it was never PulseAudio's policy, it was the bus

Checked the previous session's work and reproduced both failures live. Two independent bugs, both now
fixed on the running phone (no reboot, no flash):

**1. PulseAudio does not follow the jack.** With `Headphone Jack` = on and the Headphones port available,
forcing the card to "HiFi (Mic, Speaker)" left it there indefinitely: `module-switch-on-port-available` is
loaded, but this card's UCM port availability never drives a switch. Also `amixer cget name='Headphone Jack'`
fails (CARD-iface control) - it has to be resolved to a numid through `amixer controls` first; that is why
earlier scripts silently read an empty jack value.

**2. The RX codec slave detaches when idle, and a stream started in that state dies.** Reproduced:
`sdw:2:0:0217:010a:00:4` = UNATTACHED -> play -> `SWR CMD error, fifo status 0x3e00012e`, `DPN_PortCtrl
register write failed for port 1`, `Program params failed: -5`, `WCD937x Playback: ASoC error (-5) at
snd_soc_link_prepare()`. The player then stalls ("songs do not start"). Root cause of the detach is not
chased further; the useful finding is that a **runtime-PM resume of the slave re-attaches it**: writing `on`
to the master/slave `power/control` took it from UNATTACHED to Attached in ~1 s, with only the known benign
`SWR bus clsh detected` line. Holding it `on` while the jack is in use keeps it Attached (60 s+ observed,
slave PM "suspended" is fine as long as it stays Attached).

**What is installed now** (all in `phone/`, live on the device):
- `violet-jack-watch` (`/usr/local/bin`): polls the kernel jack control 1 Hz; on change sets the UCM profile
  (Headphones/Speaker), enables MBHC, and while the jack is in use calls the bus guard every loop.
- `violet-bus-guard` (`/usr/local/sbin`, root): `ensure|hold|release|status` over the RX master/slave
  `power/control` (sudo -n from the watcher; sysfs is root-only).
- `violet-jack-watch-run` + `/etc/init.d/violet-jack-watch` (OpenRC, `command_background`, added to the
  default runlevel): runs the watcher as user `user` so it is in the same session as PulseAudio and survives
  ssh sessions (elogind kills ssh-started daemons).

Verified live: jack on -> profile "HiFi (Headphones, Mic)" within 1 s; three consecutive `paplay` runs
rc=0 with the slave staying Attached and **zero** ASoC/SWR errors; sink = `...HiFi__Headphones__sink`.
Not verified: behaviour across a reboot (the service is enabled; this needs one boot to confirm) and the
unplug direction (same code path, but I could not unplug it myself).

Caveat: holding the bus awake while headphones are in use costs a little idle power; released again when
the jack goes out.

## 2026-11-06 (22:1x) — switching architecture changed: one sink, route under it

User test exposed the flaw in the UCM-profile approach: music played in the headphones, unplug -> speaker
fine, plug again -> **the app's stream stalled**. Reproduced: after the re-plug the player's sink-input stayed
alive but the sink stopped consuming (`paplay` hung, rc=124), while the codec was powered (0x3008=c1,
0x3009=fc) and the mixer was right. Cause: switching the PulseAudio **card profile** re-creates the sinks and
wedges a stream that is playing across the switch.

New arrangement (live on the phone):
- The card profile is pinned to `HiFi (Mic, Speaker)`: **one** sink, `module-alsa-sink hw:0,2` (MultiMedia3).
- `violet-jack-watch` now switches the **codec route** with `violet-hph jack|speaker` on jack changes instead
  of switching profiles, and keeps re-asserting the pinned profile once a second.
- `module-switch-on-port-available` is unloaded and Claude's `/etc/xdg/autostart/violet-pulse-policy.desktop`
  is renamed to `.disabled` (it existed only to load that module).
- `violet-jack-watch-run` now wraps the watcher in a restart loop.

Verified live: with 30 s of music playing, `violet-hph speaker` then `violet-hph jack` flipped
`PRI_MI2S_RX ... MultiMedia3` on->off and `RX_CODEC_DMA_RX_0 ... MultiMedia3` off->on while the sink stayed
**RUNNING** and dmesg stayed clean - i.e. the route moves under a playing stream instead of tearing it down.
State after: jack=on, slave Attached, route to jack, one sink (Speaker port of hw:0,2).
Not verified by me: a physical unplug/replug during playback (that is the user's test).

## 2026-11-06 (22:4x) — ROOT CAUSE of the headphone failures: clock-stop decision in soundwire/qcom

Reproduced the user's report end to end: play in headphones -> unplug (speaker fine) -> plug -> **nothing plays**.
State at failure: `sdw:2:0:0217:010a:00:4` = UNATTACHED for minutes, `DPN_PortCtrl ... port 1` failed,
`Program params failed: -5`, `WCD937x Playback: ASoC error (-5) at snd_soc_link_prepare()`, and a runtime-PM
resume no longer re-attached it (the earlier guard's forced resumes logged
"slave was UNATTACHED -> forced resume -> UNATTACHED" every 2 s).

**Root cause (upstream bug, still present in upstream master).** `drivers/soundwire/qcom.c` decides whether the
controller may use clock stop from `slave->prop.clk_stop_mode1`, but
- it does so in `qcom_swrm_enumerate()`, which races with the slave driver probe that sets the property (and only
  the last enumerated slave counts) - the exact problem fixed upstream by Marek Szyprowski on 2026-10-28
  ("soundwire: qcom: decide about clock stop support on runtime suspend"), not yet merged;
- the condition is inverted relative to its own commit message (74e79da9fd46: "needs a full reset if clock stop
  support is not available in slave devices"): it sets the flag when the slave *does* support it.

Our WCD9375 has **no DisCo properties** (`dev-properties` on both slaves is empty, `clk_stop_mode1` = false), so
`clock_stop_not_supported` stayed false: the controller entered clock stop on runtime suspend, lost its state, and
the graceful `sdw_bus_exit_clk_stop()` on resume never re-initialised it -> link dead until reboot.

**Fix (patches/0043-soundwire-qcom-reset-on-clock-stop.patch, built into `boot-mainline-cs-fix.img`):**
take the decision at runtime suspend and invert it (a slave without clock-stop mode 1 forces the reset path).
Verified on the phone after flash: RX slave **Attached through 120 s idle** with the userspace guard stopped, two
consecutive `paplay` runs rc=0, dmesg clean. The userspace bus guard is no longer needed to hold the bus; it stays
only as a recovery net.

Rollback: `device-backup/boot-before-csfix-20261106.img` (md5 d67422ea..., identical to
`boot-mainline-delay5-oldpads.img`). Flashed image `boot-mainline-cs-fix.img` (md5 ddebef70...).

Also in this pass: headphone gain lowered to a comfortable level (PA gain 12/20, digital 110/124 = -14 dB; the
previous full-scale 20/20 + 0 dB was painfully loud on real earbuds), and the UCM Speaker device renamed to
"Speaker (3.5 mm jack follows the plug)" so the PulseAudio output label stops pretending it is always the speaker
(takes effect after the next PulseAudio restart).

## 2026-11-06 (23:1x) — the real blocker: MM3 -> codec-DMA is silent, MM4 works

After the kernel fix the link stayed up (streams started clean, codec powered: 3008=c1, 3009=fc, companders off)
but the jack was **still silent**, while the speaker route worked. Bisected with the phone's owner by ear:

- 3 tones with pwr=ULP/LOHIFI x mode=CLS_H_NORMAL / CLS_H_HIFI / CLS_AB_HIFI: **none audible** on MM3.
  (`CLS_AB_HIFI` is even rejected with EINVAL while PWR Mode = LOHIFI.)
- 5 tones on **hw:0,3 (MultiMedia4)** with `RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia4` on: **heard**.
- On hw:0,3: speaker route (`PRI_MI2S_RX Audio Mixer MultiMedia4`) -> heard + TAS logs "amp 0 active";
  jack route -> heard.

So the legacy AFE/DSP path for **MultiMedia3 into the codec-DMA port produces no audio at all** on this firmware,
with everything else looking correct; **MultiMedia4 works**. MM3 is fine for the speaker BE (that is how the
speaker has always been tested), which is what made this so confusing.

Final arrangement (live, verified by ear and by the speaker amp's own log):
- UCM `Speaker` device `PlaybackPCM` is **hw:${CardId},3** (MultiMedia4) - one permanent sink on the PCM that works.
- `violet-hph` switches the **MM4** routes (`RX_CODEC_DMA_RX_0 ... MultiMedia4` for the jack,
  `PRI_MI2S_RX ... MultiMedia4` for the speaker); the card profile never changes.
- `violet-jack-watch` polls the jack 1 Hz and calls `violet-hph` on change (OpenRC service, runs as user).
- All amixer calls use **`-D hw:$CARD`**: `amixer -c 0` goes through PulseAudio's ALSA plugin, whose numid table is
  shifted (Headphone Jack = 90 there, 89 on hw:0) - that made earlier reads silently read the wrong control.
- Volume: PA sink 65 %, codec PA gain 12/20, digital 110/124 (~ -14 dB); 20/20 + 0 dB was painfully loud.

## 2026-11-07 00:2x — stable headphone config (and the mistake that broke it earlier tonight)

Working configuration, verified by ear (music in the headset, kernel log clean, `pcm3p` = hw:0,3 open,
`pcm2p` closed):

1. **The RX SoundWire master is held awake permanently** (`power/control=on`, helper
   `/usr/local/sbin/violet-bus-guard hold`, called by the watcher every loop).  This is the load-bearing
   piece: the codec-DMA playback path and the apps-side SoundWire driver share the RX master, and a
   suspend/resume there wedges it - `SWR CMD error, fifo status 0x3e001005`, then every stream fails with
   `write error: I/O error` / ASoC -5.  With the bus held, the kernel's reset-on-resume path (patches/0043)
   never runs, so it is inert rather than harmful.
2. **Two sinks, one per PCM** (this firmware binds front end to back end):
   card `Speaker` on hw:0,2 -> PRI_MI2S_RX -> TAS amp; `violet_hph` (module-alsa-sink) on hw:0,3 ->
   codec DMA -> WCD9375 -> jack.  `violet-jack-watch` switches the **default sink** on jack change.
3. Per-sink volume; headphone ceiling from `/etc/violet-audio.conf` (`jack_hph_gain=12`,
   `jack_digital_volume=94`) so the slider sits at 100 % for the loudest level wanted.
4. Never move a live stream (the GStreamer player dies) and never run both PCMs at once (SWR CMD error +
   PulseAudio died twice).

Known trade-off: on plug/unplug the player pauses or stops (GStreamer follows the default device change);
press play and it starts on the correct sink.  An MPRIS nudge is not reliable here (only Decibels exposed
MPRIS during testing), so this is the Windows-like contract for now.

Recovery recipe if the jack stops being detected or a stream errors with EIO: cycle the bus
(`violet-bus-guard release; sleep 2; violet-bus-guard ensure`) - that brought both detection and playback
back without a reboot during this session.

## 2026-11-07 00:5x — REAL root cause of the two-day "one output at a time" bug: q6routing stale BE path

Two independent reviews (Claude Opus via `claude -p --model opus`, plus a second subagent) both pointed at the
same kernel bug rather than at the DSP.  Confirmed in source and on the device.

**The bug** (`sound/soc/qcom/qdsp6/q6routing.c`, mainline): a front-end session keeps one `port_id`, but each
`<BE> Audio Mixer MultiMediaN` switch owns its own DAPM path.  Enabling a second BE moved `port_id` and
connected the new path while **leaving the old path connected**; `get` reported the old switch as 0 (it compares
against `port_id`) and turning the old switch off returned early, so userspace could never remove it - only a
reboot.  The ASM session then mapped its copp to a port DPCM had not started: playback blocks forever with **no
kernel error**, while the stale back end (speaker amp) still powers up.  That is exactly "whichever output was
used last works, the other dies until reboot".

**Measured before the fix:** with only MM3 -> RX_CODEC_DMA_RX_0 routed (old route switched off first), the codec
HP amp powered (`0x3008`=01, `0x3009`=fc) - so MM3 *can* reach the codec, the earlier "FE is bound to a BE"
theory was wrong - but the stream hung and the TAS speaker amp *still* logged `amp 0 active` with its switch
reading off.  Reviewers were right.

**Fix:** `patches/0044-asoc-q6routing-disconnect-old-be-on-reroute.patch` - remember the selected mixer control
per session and disconnect it before connecting the new one.  Shipped as `boot-mainline-routefix.img`
(md5 4e92e6a8..., backup of the previous boot in `device-backup/boot-before-routefix.img`).

**Verified after flash:** cross-routing MM3 now reports the old BE as off and the speaker amp stays quiet
(no stale path); speaker and jack both play in sequence, `rc=0`, TAS `ACTIVE` for the speaker only, codec
`0x3009=fc` for the jack, kernel log clean.

Still open, separate: the SoundWire clock-stop wedge (patches/0043) - mitigated by holding the RX master awake;
AudioReach is not reachable on this ADSP firmware (APR/ADM only), and an ADSP restart is not a safe recovery.

## 2026-11-07 01:5x — headset "feeble + chopped speech": codec was in boot-default ULP / CLS_H_NORMAL

Symptom (user): headset very quiet, "tuk tuk" noise, speech barely intelligible at every gain tried.
Prior art searched: lkml wcd937x/wcd938x HPH volume patches (analog range, UCM digital-vs-analog volume), Android
HAL commits (class-H LOHIFI/ULP modes, compander noise fix), wcd937x-sdw binding (rx-port-mapping = HPH,CLSH,COMP,LO,DSD).
None describes this exact symptom - recorded as "nothing direct found".

Measured (fresh boot): `RX_HPH PWR Mode`=ULP(0), `RX HPH Mode`=CLS_H_NORMAL(0). `violet-hph` (manual tool) sets
LOHIFI + CLS_H_LOHIFI, but `violet-jack-watch ensure_mixers` never did, so the automatic path ran the codec in the
low-power mode. A/B by ear (aplay direct to plughw:0,3, PulseAudio bypassed): all gains 16/116, 20/84, 20/100
were equally chopped (so not a gain problem; buffer size 1024/4096 made no difference); after setting
LOHIFI + CLS_H_LOHIFI (and a CLS_AB try, partly "Resource busy") the user reported **all clear and very loud**.
Fix: `phone/violet-jack-watch` ensure_mixers now sets both modes; `/etc/violet-audio.conf` gain 16/116 -> 12/94
(the documented comfortable level; user said "very loud"). Deployed, service restarted, mixer reads PWR=1 MODE=5.
Also found: the 2026-11-07 01:2x readings 20/84 earlier were a stale watcher (conf edited after it started).

Open: (1) "tuk tuk" not re-checked after the fix; (2) volume OSD shows an icon without label for `violet_hph`
(hand-loaded module-alsa-sink: no ports, form_factor=internal, icon audio-card; speaker sink has port "Speaker").
Label cause is a hypothesis, not yet checked in Phosh source.

## 2026-11-07 01:4x — OPEN for next session: phone resets / USB+WiFi link disappears

Observed while verifying the headset fix (laptop `journalctl -k`, port 3-4): the phone's USB gadget repeatedly
disconnects/re-enumerates (device numbers 49 -> 92 between 01:11 and 01:40; 18d1:d001 and 1d6b:0103 alternate),
and it dropped off both USB and WiFi several times (once for good until a manual reboot at ~01:23, again after
~01:30, again ~01:40, ~2 min after boot).  Cause UNKNOWN - not yet isolated.  Facts only:
- the flapping started (01:11) before the watcher/codec-mode change (deployed ~01:29), so that change is not
  proven to be the cause, but it is not ruled out either (the dropouts also happened after it);
- the codec modes/gains survived a reboot (PWR=LOHIFI, MODE=CLS_H_LOHIFI, 12/94) - fix is in place;
- laptop and phone also landed on different WiFi subnets (<lan2>.x vs <lan>.x, SSID <other-ssid> vs
  <home-ssid>), which hid the phone from the laptop at times - separate from the USB flapping.
Next: after a drop, read /sys/fs/pstore (ramoops is configured), `last` kmsg, and the laptop-side USB log;
A/B by stopping violet-jack-watch for a while to see whether the drops stop.

## 2026-11-07 08:0x — crash/link-loss: first facts (cause still unknown)

Prior art searched: dwc3/NCM gadget disconnect threads (sdm845 f_ncm lifecycle regression 56a512a9b410 - about
DHCP/ifname, not our symptom; dwc3-qcom role-switch VBUS override threads), pmOS spontaneous-reboot reports
(asus-grouper watchdog, PinePhone) - nothing matching "sm6150 resets minutes after boot".  Recorded as: nothing direct.

Measured:
- Laptop log: after each phone boot the gadget enumerates, then `usb 3-4: device descriptor read/64, error -110`
  and repeated disconnect/reconnect pairs, then the link vanishes.  Phone uptime read 0 min at 08:00:52 with nobody
  touching it -> **the phone resets itself**; the "link disappearing" is a reset, not (only) a USB fault.
- `/sys/fs/pstore` is EMPTY after the reset (ramoops@a1600000 registered, console-size 4 MB): no panic record, so a
  hard reset (PMIC/watchdog/power) rather than a kernel oops.  No bootreason in the cmdline.
- State while up: charging 1.1-1.2 A from a PD source (`PD contract 5000 mV -> USBIN window override`), usb online,
  typec port0 device/sink, thermal max ~42 C, udc configured.  `qcom,pmic-typec ... supply vdd-vbus not found,
  using dummy regulator` at boot.
Instrumentation added (debug only, remove after): `phone/violet-crashwatch` -> `/usr/local/sbin/violet-crashwatch`,
started as root, logs 1 Hz battery/charger/typec/thermal/udc + all kernel lines to
`/var/log/violet-crashwatch.log`, `sync -f` each second.  Next: read the tail of that log after the next reset.

## 2026-11-07 08:1x — volume OSD label for the headset sink

Symptom: with the headset plugged the volume OSD shows the volume icon but no label; on the speaker it shows
"Speaker".  Source read (gnome-settings-daemon 51.0 = the version on the phone, `show_volume_osd()` in
plugins/media-keys/gsd-media-keys-manager.c): the label (device description) is sent only when the sink's
`device.form_factor` != "internal" OR its active port is not one of "analog-output-speaker"/"analog-output".
Speaker sink: port `[Out] Speaker` (UCM name, not in the list) -> label.  `violet_hph` (hand-loaded module-alsa-sink):
form_factor=internal and no port -> no label.  Matches both observations.
Measured on the session bus (`dbus-monitor member=ShowOSD`, VOLUMEDOWN via key.py): speaker sink -> label "Speaker";
`violet_hph` reloaded with `device.form_factor=headphone device.description=Headphones` -> label "Headphones".
(First attempt failed: `sink_properties=` with spaces must be quoted `'...'` for module-alsa-sink.)
Fix: `phone/violet-jack-watch` ensure_jack_sink loads the sink with those properties; deployed, service restarted.
Confirmed on screen by the user 2026-11-07 (volume popup shows "Headphones" with the headset in).  Side effect of the tests: speaker sink was briefly lowered to 88/94 %, restored to 100 %.

## 2026-11-07 08:1x — user clue for the link loss: it follows headset plug/unplug cycling

At ~08:10:35 USB dropped right after the headset was plugged and unplugged repeatedly (user report, not yet
reproduced by me).  The phone kept running (music playing) while USB (`error -71`, `device not accepting address`)
and the laptop's route to it were gone, so this is not a full SoC reset in this instance - earlier uptime=0
readings were resets, this one was not.  Hypothesis only: the jack events (MBHC/SoundWire/codec, or the
watcher's reaction: ensure_mixers, bus-guard sudo, sink switching) disturb the USB gadget/link.  To test: with the
crashwatch log (1 Hz, synced) read the lines around the drop; then cycle the jack while watching.

## 2026-11-07 08:2x — crashwatch redone as an OpenRC service (first attempt died with the ssh session)

The ssh-started logger (setsid nohup) was killed when my ssh session ended (KillUserProcesses), so it captured
only 3 state lines and nothing about the 08:10 drop.  Redone as `/etc/init.d/violet-crashwatch`
(`phone/violet-crashwatch.initd`), started with `rc-service violet-crashwatch start`; NOT added to a runlevel
(user's call: no boot persistence), so it must be restarted after every reboot.  Log: `/var/log/violet-crashwatch.log`.

## 2026-11-07 08:4x — crashwatch enabled at boot (user asked), size-capped

User asked for it to start every boot so a future wedge is caught.  `rc-update add violet-crashwatch default`
(init script has `need localmount`), log capped at ~16 MB with one rotated copy (`.log.1`).  The plug/unplug
test at ~08:34 did NOT reproduce the wedge (USB stayed up, phone up 15 min).  Remove the service
(`rc-update del violet-crashwatch; rm /etc/init.d/violet-crashwatch /usr/local/sbin/violet-crashwatch`) once the cause is found.

## 2026-11-08 — first fast-charge measurement (pack at 41-42 %, Moto 68 W PD charger, 9 V/3 A contract)

Phone reached over WiFi at <lan-ip> (laptop moved to <lan>.x; old <lan2>.x address was a different network). Six samples over 30 s: battery current steady **+1.994 .. +1.997 A**, vbat 4.157-4.160 V, pack 39.8 C, status Charging, `0x1006` = 3 (fast charge), `0x1061` = 0x28 (FCC 2000 mA, written by violet-qg), `0x1370` = 0x24 (ICL 1800 mA), `0x1344` = 0x02, `usb` current_max 1.8 A, tcpm psy 9.000 V / 3.000 A. The charge current is pinned to the FCC register we write (2 A), not to the input limit (9 V x 1.8 A = 16 W vs ~8.3 W into the pack), and the vendor profile allows 3 A at 15-45 C. Pack was already 39.8 C at 2 A. Not yet done: any step above 2 A (needs temperature-limited FCC like the vendor jeita-fcc-ranges: 3.0 A at 15-45 C, 1.95 A at 45-60 C, 1.17 A at 5-15 C, 0.39 A at 0-5 C).

## 2026-11-08 — temperature-limited fast-charge current, 2.5 A trial

`violet-qg` no longer writes a fixed FCC: `violet_fcc_target()` = min(`fcc_max_ma` module param (default 2000, runtime-writable in `/sys/module/violet_qg/parameters/`, clamped 500-3000), vendor `qcom,jeita-fcc-ranges` from the LC_M6300 profile: 0-5 C 390 mA, 5-15 C 1170 mA, 15-45 C 3000 mA, 45-60 C 1950 mA). One limit is our own and NOT vendor: pack >= 43 C caps at 2000 mA, released below 41 C (hysteresis added after the first trial flapped 2500 <-> 2000 at 42.7/43.0 C). Reason: the pack thermistor is the only thermal input wired; skin/connector sensors and the vendor thermal mitigation are not ported. Hardware JEITA from SBL still applies.
Trial (pack 52-54 %, Moto 68 W, 9 V/3 A, `0x1061` = 0x32): battery current steady **+2.50 A** (vbat 4.22 -> 4.30 V), but pack 40.3 -> 43.0 C in ~90 s (about +1.7 C/min), at which point the 43 C cap dropped it back to 2.0 A; temperature then eased to 40.9 C at 2 A. So 2.5 A is deliverable but is not thermally sustainable from a ~40 C start with this thermistor and no airflow/skin limit; a cool pack would last longer (not measured). Default left at 2000 mA. Installed for boot (`violet-qg.ko.zst`, previous kept as `.prev-fixedfcc`). Not done: sustained run from a cool pack, 3 A, vendor thermal mitigation tables, ICL above 1.8 A.
