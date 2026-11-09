# HANDOFF 2026-11-04 — front camera brightness + libcamera tuning

Everything below was done in one session on 2026-11-04 between 06:50 and 09:00 IST. Read this top to bottom
before touching the camera again; the state is unusual (a second libcamera build exists in `/usr/local`).

## TL;DR — state of play

| Item | State | Where |
|---|---|---|
| Front camera "too dark" root cause | **FIXED** — driver bug (frame length overrode vendor timing) | `ov13855.c`, module installed on phone |
| Frame rate / exposure ceiling | **FIXED** — 3214-line frame (30 fps), max exposure 3206 (was 1642 @ ~49 fps) | same |
| Light at the AGC ceiling | **2.05×** more than before (raw signal 16 % → 33 % of full scale) | measured |
| libcamera soft-ISP tuning (AWB/AGC/shoulder) | **IN PROGRESS** — patched build exists in `/usr/local`, NOT yet used by the desktop | `~/lc` on phone + `patches/proposed/` |
| AWB startup green flash | **FIXED in the patched build** (G/R flash 4.00 → 1.30) | patched build only |
| Residual AWB cast | **NOT FIXED** — grey-world bias, needs CCM/tuning work | open |
| Highlight shoulder vs a real clipped object | **NOT TESTED** — needs a shot with the white cloth | open |
| Autofocus | not started — no VCM driver exists in the tree | open |

**Nothing on the phone's system was replaced.** The desktop (Snapshot) still uses the distro libcamera.
The patched build is only ever used when `LD_LIBRARY_PATH`/`LIBCAMERA_IPA_MODULE_PATH` are set.

## 1. The driver bug (this is the part that is done and permanent)

Symptom: front preview unusably dark while libcamera's AGC sat pinned at *both* limits
(`exposure 1642/1642`, `analogue_gain 1984/1984`).

Cause: `ov13855_init_controls()` created `V4L2_CID_VBLANK` with default **82**; `ov13855_start()` calls
`__v4l2_ctrl_handler_setup()` *after* the vendor mode table, so `0x380e` was rewritten to
`82 + 1568 = 1650` lines at every stream start. The vendor mode table's own frame length is `0x0c8e` = **3214**
lines (30 fps). Max exposure is `VTS - 8`, so the sensor integrated 1642 lines at ~49 fps instead of 3206 at
~28 fps — exactly half the light, i.e. one full stop.

Fix (in `kernel/linux-7.2.10/drivers/media/i2c/ov13855.c`):

```c
#define OV13855_VBLANK_DEFAULT	(0x0c8e - OV13855_HEIGHT)	/* 1646 */
#define OV13855_GAIN_DEFAULT	256
#define OV13855_GAIN_MAX	1984
```
used as the VBLANK control default, for `s->vblank` in probe, and for the exposure range (so max is 3206).

Evidence: registers read back from the chip — `0x380e` was `0x0672` (1650) before, `0x0c8e` (3214) after;
60 frames in 1.22 s (≈49 fps) vs 2.18 s (≈28 fps); raw signal at max exposure+gain 92/959 → 180/959 (1.96×).

Also measured and **deliberately not changed**: `0x3508/0x3509` written as `0x0f80` (15.5×) produces *no*
increase in the captured signal — the OV13855's real analogue ceiling is `0x07c0` (7.75×), so the V4L2 range
stays 128…1984.

Build gotcha (cost an hour): `make M=drivers/media/i2c ov13855.ko` alone compiles the object **without**
`-DMODULE` because `CONFIG_VIDEO_OV13855` is not in `.config`; the resulting `.ko` has `U init_module` and fails
to load with "Unknown symbol init_module (err -2)". Always build with:

```sh
cd kernel/linux-7.2.10
make ARCH=arm64 LLVM=1 M=drivers/media/i2c CONFIG_VIDEO_OV13855=m ov13855.ko
nm drivers/media/i2c/ov13855.ko | grep " T init_module"   # must print a symbol
```

Reload gotcha: the module refcount is held by v4l2-async, so `rmmod ov13855` fails with "in use" even with no
open fds. Either
`echo 3-0036 > /sys/bus/i2c/drivers/ov13855/unbind; rmmod ov13855; modprobe ov13855`
or just reboot (the `.ko` is on disk in `/lib/modules/7.2.10-sm6150/extra/`).

Current state: installed, loaded, verified after a clean reboot.

## 2. libcamera soft-ISP work (in progress)

### Why
The three real quality gaps, established by reading libcamera 0.7.2 source and by measurement:

| Algorithm | File | What it actually does | Consequence |
|---|---|---|---|
| `Awb` | `src/ipa/simple/algorithms/awb.cpp` | plain grey-world on frame sums, **no tuning hooks**, no smoothing, clamped 4.0 | frame-to-frame jumps; green cast when the scene is not neutral |
| `Agc` | `src/ipa/simple/algorithms/agc.cpp` | 5-bin mean-sample-value target, mid-range; exposure first, then gain | clips bright objects (10.4 % of one photo was flat 255,255,255) |
| `Adjust` | `adjust.cpp` / `.h` | gamma 2.2 by default + contrast, **no highlight shoulder** | clipped highlights stay flat white |

`Gamma`, `Contrast`, `Saturation` are runtime libcamera controls (0.1–10 / 0–2 / 0–2), default gamma 2.2.

### What was built
Pristine libcamera **v0.7.2** built natively on the phone into **`/usr/local`** (system libcamera untouched),
then patched and rebuilt. Build dir `~/lc`, source `~/lc/libcamera-v0.7.2`, build `~/lc/output`.

Meson options used:
```sh
meson setup ../output -Dpipelines=simple,virtual -Dv4l2=disabled -Dgstreamer=disabled \
      -Dqcam=disabled -Ddocumentation=disabled -Dpycamera=disabled -Dwerror=false -Dprefix=/usr/local
```
Build takes ~6 min on the phone (8 cores). Deps installed: meson ninja gcc g++ cmake python3-dev py3-jinja2
py3-yaml py3-ply libdrm-dev gnutls-dev libevent-dev libunwind-dev eudev-dev yaml-dev.

### The patches (all three, in `patches/proposed/violet-libcamera-tuning.patch`)
1. **AWB temporal smoothing** (`awb.cpp`): adaptive alpha — 0.60 when the target is >30 % away, 0.15 otherwise,
   with a 1 % deadband. Kills the startup flash without freezing the loop.
2. **AGC highlight weighting** (`agc.cpp`): if the top 10 % of the luma histogram holds >2 % of the pixels,
   bias the MSV target darker proportionally (weight 8.0, capped at 5 bins of error).
3. **Tone shoulder** (`bayer_1x_packed.frag`, `bayer_unpacked.frag`, `debayer_cpu.cpp`): above a knee of
   **0.85**, compress towards 1.0 with `knee + range*over/(over+range)` instead of clipping.

Tuning history (important — the first attempt was worse and was fixed):
- α=0.12 / knee=0.72 → image was *greener and 15 % dimmer* than stock. Wrong direction.
- α=0.35 / knee=0.85 → still green at frame 8.
- **α adaptive (0.60/0.15) / knee 0.85 → current.** Verified below.

### Verified (patched build only)
| | before (system) | after (patched) |
|---|---|---|
| frame-2 AWB (G/R) | **4.00** — green flash | **1.30** — no flash |
| settled AWB (G/R) | 1.03 | 1.09 |
| mean luminance | 165 | 160 (−3 %) |
| clipped | 0.0 % | 0.0 % |

### How to run the patched build (does not affect the desktop)
```sh
export LD_LIBRARY_PATH=/usr/local/lib
export LIBCAMERA_IPA_MODULE_PATH=/usr/local/lib/libcamera/ipa
cam -c 2 --capture=8 --file=/var/tmp/x#.bin
```
The IPA is signed with the key generated by this build — do **not** mix `/usr/local/lib` with the system IPA
directory, the signature check fails.

### How to test (script on the phone: `/var/tmp/ab.sh`, copy in `patches/proposed/libcamera-ab.sh`)
Releases the CSIPHY→CSID links, captures 8 frames with the system lib, 8 with the patched lib, prints
per-frame mean / clipped% / per-channel means (`abstats.py`).

Camera index note: `cam -l` numbering is **not stable across reboots** (2 vs 3 for the front). Always look it up:
`cam -l | grep -i "front camera"`.

## 3. Open items / next steps for the next session

1. **Prove the highlight shoulder** on a real clipped object (hold the white cloth in front of the camera,
   capture with both builds, compare clipped-pixel counts). Not done yet.
2. **Residual AWB cast** (1.09 vs 1.03): grey-world has no illuminant model. Options: use the vendor CCMs
   (`phone/ov13855.yaml`) more aggressively, add a grey-edge assumption, or implement a proper AWB — this is
   real work, not a one-line tweak.
3. **Decide how the desktop uses the patched libcamera.** Today only opt-in via env vars, so Snapshot is
   unaffected. Options: an env file for the phosh session, or installing over `/usr/lib` (rollback:
   `apk fix libcamera libcamera-ipa`). Not done on purpose.
4. **Autofocus**: the VCM at i2c `0x0c` (CCI1) is undriven; there is no actuator driver in the tree at all.
   This is the biggest remaining feature gap.
5. **Snapshot writes 1920×1080** while the sensor delivers 2112×1568 — the still stream never reaches the
   file. Worth fixing app-side.
6. **Photos are saved with `EXIF Orientation = 8`** instead of being physically rotated — anything that
   ignores EXIF shows them sideways. The DT rotation values (90° front / 270° rear) are still guesses from the
   bring-up.

## 4. Backups taken (do not delete)

| What | Path | Size |
|---|---|---|
| Phone userspace (quick) | `device-backup/phone-userspace/quick-20261104-0803.tar.gz` | 678 MB |
| Driver + docs + cap.sh snapshot | `device-backup/camera-fix-20261104-0803.tar.gz` | 226 KB |
| libcamera patch set | `patches/proposed/violet-libcamera-tuning.patch` | 5 KB |
| Patch generator (idempotent) | `patches/proposed/libcamera-patch.py` | — |
| Build script / log | `patches/proposed/libcamera-build.sh`, `libcamera-build.log` | — |
| A/B harness | `patches/proposed/libcamera-ab.sh`, `libcamera-abstats.py` | — |

Evidence images from this session (full-resolution comparisons) are in `docs/camera-2026-11-04/`:
`progress.png` (front camera before/after the driver fix, same scene), `ab.png` (system vs patched libcamera),
`photos.png` (the two user photos), `clip.png` + `mask.png` (the clipped white cloth), `orient.png`
(stored pixels vs EXIF-rotated).

Patch format note: `patches/proposed/violet-libcamera-tuning.patch` uses `a/`…`b/` labels — apply with
`patch -p1` from the root of a libcamera-v0.7.2 source tree (verified against a fresh extract).

Restore the phone userspace with `host/phone-restore.sh` (see `docs/RESTORE.md`). Re-run the patch with
`python3 patches/proposed/libcamera-patch.py` inside `~/lc/libcamera-v0.7.2` (it is idempotent and asserts the
anchors), then `ninja -C ../output && sudo ninja -C ../output install`.

## 5. Other things learned this session (not camera driver)

- The **hotspot isolates clients** ("<hotspot>"): the phone gets a DHCP lease and can ping the gateway, but
  client↔client traffic is dropped, so ssh over WiFi is impossible even though both are on the same subnet.
- `cam` (libcamera-tools) is the only usable CLI; `cam -C 1` needs `--capture=1` (the count is an optional
  argument, a space-separated value makes it print usage).
- Killing `wireplumber` is still required before `rmmod` of camera modules; `pkill -f wireplumber` **kills your
  own ssh session** because the pattern matches the remote shell — use `pgrep -f 'wireplum[b]er'`.
- The rear capture harness now uses the correct mbus code: imx586 is **`SRGGB10`** (video `pRAA`), not
  `SBGGBGR10`; the wrong code fails `media_pipeline_start` with `-EPIPE`. See `phone/cap.sh`.

## 6. Addendum (afternoon session) — rear autofocus hardware proven, quality gap analysis

**Rear VCM = Dongwoon DW9800-class at i2c-3 `0x0c`** (`actuatorName = dw9800` in the Ofilm sensormodule.bin;
reg 0x00 reads `0xf2`). Register layout matches `dw9807-vcm.c`: 0x02 control (bit0 power-down), 0x03 position MSB,
0x04 position LSB (10-bit). Supply is `pm6150_l19` (2.8 V) – it was already live, no DT change needed to probe.

**Proof it moves the lens** (`phone/af-sweep.sh`, userspace i2cset only, exposure 3000 / gain 1600, scene = coin at
~25 cm): Laplacian variance of a 2×2-binned green crop by lens code:
0:380 100:374 200:373 300:363 400:358 500:354 600:370 700:451 **800:723** 900:482 1023:467 → clear focus peak ≈ 800.

**Why the rear photos are soft today:** the lens just sits at the reset position (≈512) because nothing drives
the VCM. No ISP tuning can fix that. Also noted: at exposure 1500/gain 256 an indoor scene is ~2 counts above the
64 black level – the soft ISP's gain staging hides that; real quality needs multi-frame merging for noise.

Gap list to Xiaomi/Google class, in the order that matters:
1. **Autofocus** — kernel `dw9800` subdev (focus-absolute) + a contrast-AF loop (the libcamera *simple* IPA has no AF).
2. **Multi-frame raw merge (HDR+-style)** — align + merge N short raw frames: ~√N noise cut, no clipped highlights.
3. **Real ISP for stills** — proper demosaic, denoise, local tone mapping, sharpening, lens shading, OIS-free
   stabilisation by short exposures. Libcamera soft ISP is a preview-grade pipeline.
4. Orientation/EXIF, full-res still output (items 5/6 in §3).

Note: wireplumber was killed for the capture harness; re-start per memory note (D-Bus activation) or reboot.

### 6.1 DW9800 driver (written, NOT yet booted)
`kernel/.../drivers/media/i2c/dw9800.c` (+ Makefile line, build with `CONFIG_VIDEO_DW9800=m`), module installed in
`/lib/modules/7.2.10-sm6150/extra/`. DT: `rear_vcm: actuator@c` on `cci_i2c1` + `lens-focus = <&rear_vcm>` on the
imx586 node (`violet-sm6150-camera.dtsi`). Bound by hand via `new_device` it probes fine ("DW9800 VCM registered")
but gets **no /dev/v4l-subdev** — async subdevs only get a node once a notifier matches them, hence the DT link.
Boot image with the DT change: `boot-mainline-cam-af.img` (built, not flashed). After boot expect a subdev with
`focus_absolute` and libcamera listing the lens in the media graph. Next: contrast-AF loop.

### 6.2 AF verified on the phone (booted `boot-mainline-cam-af.img`, 13:47)
- After boot: `dw9800 3-000c: DW9800 VCM registered`, `/dev/v4l-subdev18` has `focus_absolute` (0–1023, default 512).
- `phone/violet-af.c` (build on phone: `gcc -O2 -o violet-af violet-af.c`) streams the RDI node (MPLANE, pRAA 4000×3000),
  steps the lens, scores a central ROI and does coarse (64) + fine (32→4) search. Score = 4×4-binned Laplacian energy
  divided by mean² (raw gradient energy is noise/flicker dominated at gain 1600 — an unnormalised score gave BEST 0
  on repeat runs). Run: `violet-af /dev/video0 <vcm-subdev> <imx586-subdev> <exposure> <gain> [--sweep]`.
  Pipeline must be linked first (run `cap.sh` once). Repeat runs on the coin scene: 780, 780, 788, 780 (~1 s per AF).
- Visual proof: `docs/camera-2026-11-04/raw/af_compare.png` — lens at old rest position 512 (left, blurry) vs AF 780
  (right: embossed lettering and scratches resolved).
- Not yet done: AF is a standalone tool, not wired into libcamera/Snapshot (the simple IPA has no AF algorithm);
  only the close-range peak is proven — test a far scene (infinity should be near code ~0–200); the per-module
  EEPROM (0x50) likely holds infinity/macro calibration codes — read it to bound the search.

### 6.3 AF range calibration (far scene) and EEPROM
- Far scene (≥3 m, two runs): focus peak at lens code **~400** (396, 404); close coin (~25 cm): **~780**. Useful travel is
  therefore ~300–1000; `violet-af` now searches 256–1023 (coarse step 48, then fine 32→4).
- Rear EEPROM (CCI1 0x50/0x51) NOT decoded: the CCI adapter rejects 2-byte-address `i2ctransfer` ("Not supported"),
  and 1-byte `i2cdump` shows a 0x20-period repeating pattern (header `01 28 fb b5 e0 fb c0` at 0x50, `01 05 cf 87…` at 0x51),
  i.e. the chip wants 16-bit addressing. Only worth doing if the factory infinity/macro codes are needed; contrast AF
  self-calibrates so it was skipped.

## 7. Multi-frame merge (offline prototype, 2026-11-04 14:05) — WORKS
`tools/camera/vpipe.py` (uv venv in `tools/camera/.venv`: numpy scipy opencv-python-headless pillow):
burst of 8 raw frames → sharpest reference → DIS dense flow on binned luma → sub-pixel warp of each Bayer plane →
robust Wiener-style weighted merge in raw → edge-aware demosaic → grey-world WB → shoulder + sRGB → chroma bilateral
→ NLM luma → unsharp. 5 s on the laptop. Capture: `violet-af …` then `v4l2-ctl --stream-count=8 --stream-to=burst.raw`
(15 MB/frame, stride 5008).
Evidence: `docs/camera-2026-11-04/burst1/cmp_crop.jpg` (single frame left vs 8-frame merge right, same data — colour
noise gone, text clean), `full_small.jpg`. Scene was dim (exposure scale 23×), fixed exposure 3000/gain 800.
Known gaps: no auto-exposure (fixed values), chroma slightly grey/flat in shadows (needs real CCM + local tone map),
no lens-shading correction, no rotation/EXIF (use `--rotate`), runs only on the laptop, noise-model weight constants are
rough. Next: `violet-shot` on the phone = meter → AF → burst → merge → JPEG.

## 8. `violet-shot` — first end-to-end phone-made photo (14:12)
`phone/violet-shot.py` (+ `violet-af`, `vpipe.py` in `/var/tmp/` on the phone; `sudo apk add py3-numpy py3-opencv py3-scipy`):
links the rear pipeline → auto-exposure (≤2600 lines, ≤16× SMIA gain, target mean 150, highlight guard) → contrast AF →
6–10 frame raw burst → `vpipe.py --rotate 270` → JPEG. Run: `sudo python3 /var/tmp/violet-shot.py out.jpg`
(use `IF=<iface> ./rssh` — the USB interface name changes with the cable: enp0s20f0u1 now).
First run: scene so dark AE pinned (exp 2600, 16×, mean 24); AF 748; 10-frame burst 0.6 s; whole shot 47 s (merge ≈ 36 s on the phone).
Result `docs/camera-2026-11-04/shot1/` — upright, text and embossing sharp in dim light. SMIA gain note: code 256 ≠ 1×;
gain_x = 1024/(1024-code) (code 0 = 1×, 800 ≈ 4.6×).
Remaining: cool colour cast + haze (needs real CCM / tone curve / local contrast), shot speed, lens-shading, EXIF,
not hooked into a UI/app, front camera has no burst path, no HDR (multi-exposure) yet.

## 9. Direction change + develop rewrite (14:40)
Research (web, 2026-11-04): Pixel's default photo IS an HDR+ burst (2–10 raw frames from a zero-shutter-lag buffer,
tile alignment + merge); Xiaomi's stock pipeline lists MFNR for this SoC (default-on not verified); GSMArena calls the
stock Note 7 Pro "way too soft" in low light, so stock is not the quality ceiling. Megapixels (+postprocessd) exists as a
Linux capture app (5-frame DNG burst + external postprocess script); not adopted yet.
`vpipe.py develop()` rewritten: robust WB (grey-world + white-patch blend, clamped), vendor 5000 K CCM (rows normalised),
luma shoulder + cheap local tone lift, half-res chroma denoise, unsharp. 8-frame merge+develop 4.1 s on the laptop
(`docs/camera-2026-11-04/burst1/merged2.jpg`, neutral whites, natural blues). Rotation must come from the accelerometer
(the `--rotate 270` default is wrong when the phone is held differently — burst1 comes out upside down).
Phone dropped off USB (new cable, no enp0s20f0u* interface, not in fastboot, not on WiFi) at 14:30; plan once back:
install nothing new, copy updated vpipe.py, then build the ZSL daemon (keep sensor streaming, continuous AF, shutter =
take last N frames, merge in the background, C/NEON hot path).

## 10. Fast path written offline (phone unreachable 14:30→; NOT yet tested on the phone)
- `vpipe.py develop()` re-done with OpenCV SIMD ops + one 3×3 transform (WB×vendor CCM×exposure) + 65536-entry tone LUT:
  develop 1.15 s → 0.35 s on the laptop (≈ 3 s on the phone est.); 1-frame shot ≈ 0.5 s, 3-frame ≈ 1.2 s on the laptop.
  `tools/camera/prof.py` prints per-stage timings.
- `phone/vcamd.c` — zero-shutter-lag capture daemon: keeps the RDI node streaming, continuous AE (deadband so exposure
  is stable), runs AF once after warm-up and on `af`, keeps the last 6 raw frames in RAM; FIFO commands `shot N path`,
  `af`, `status`, `quit`. Compiles clean on the laptop (`gcc -O2 -Wall -Wextra vcamd.c -lm`). Build on the phone, put next to
  `violet-camera.py` as `vcamd`.
- `phone/violet-camera.py` — `start | shot [N] [out] | af | status | stop`; rotation from `ssccli --sensor accelerometer`
  (ROT_TABLE is a guess: up=270 matches shot1; calibrate left/right/down by taking shots in each orientation).
- First thing to do when the phone is back: `apk add gcc musl-dev linux-headers`, `gcc -O2 -o vcamd vcamd.c -lm`,
  `sudo python3 violet-camera.py start`, `shot 3`, check timings and the picture, then calibrate rotation.

## 11. Merge speed-up + app evaluation (15:00)
- `vpipe.merge()`: DIS FAST preset on a quarter-size luma, flow upsampled, one 4-channel `cv2.remap` per frame,
  weights simplified → 8 frames 2.2 s → 1.6 s, 3 frames 0.64 s (laptop). Output equivalent.
- Megapixels evaluation (web): captures a 5-frame DNG burst; its bundled postprocess script does NOT stack (copies frame 1);
  stacking lives in separate `postprocessd`; libmegapixels needs a per-device config; no documented AF handling in what
  I found. Verdict: own daemon (`vcamd`) is less work than adopting it and already has AE + AF; Megapixels is only a UI
  option later. IMX586 driver exposes just the 4000×3000 vendor mode = the 2×2-binned 12 MP readout, i.e. the same
  default stock phones use (so no mode change needed).
- Phone status: USB NCM disconnected 14:09:31 (laptop log) and never returned; not on WiFi (.10 no route; .4 is
  another host). Needs a physical reset. Watcher armed (`watch2.out`).

## 12. ON-DEVICE RESULTS (phone back 15:01) — vcamd + violet-camera.py work
Deploy: copy `phone/vcamd.c`, `phone/violet-camera.py`, `phone/violet-shot.py`, `tools/camera/vpipe.py` to `/var/tmp/` on the phone,
`gcc -O2 -o vcamd vcamd.c -lm`; `python3 violet-camera.py start` (D-Bus activation → cgroup /c1; elogind kills
anything started from ssh; the camera devices are user-accessible so no sudo; wait ≥25 s before re-starting after a
pkill, or dbus refuses a second activation of the unclaimed name; start() now uses `--print-reply --reply-timeout`).
Then `violet-camera.py status | af | shot [N] [out.jpg] | stop`.
- ZSL: shutter→raw in RAM **0.17–0.3 s** (ring of 6 frames, AE deadband keeps exposure stable).
- JPEG (3 frames, dark scene, AE pinned at 2600 lines/16×): 47 s (first violet-shot) → **7.5 s**; 1 frame **3.4 s**; 4 frames 7.4 s.
  Frame count chosen in the daemon from exposure×gain (1/2/3/4 frames). C unpack of 10-bit packed → uint16 saves ~1.2 s vs numpy.
- AF bug found on device: fixed centre-window AF is flat on scenes with a plain centre (scores 0.7M flat, lens stuck
  ~250 → blurry z1.jpg). Replaced by a 5×4 window grid: per-window normalised Laplacian energy, only windows whose
  contrast range clearly exceeds noise are combined; lens peak 748–832 on the coin scene (sharp), 1.9 s. In very dark
  scenes only 1–2 windows are usable so the peak is noisy (±50 codes) — needs a longer-exposure/averaged AF frame.
- Evidence: `docs/camera-2026-11-04/zsl1/z2_small.jpg` (sharp "TIGER BALM", correct whites) vs `z1.jpg`
  (wrong AF → blurry).
Still open: orientation table calibration, front camera, UI/shutter, instant preview, GPU/C hot path, AF in very dark scenes,
lens shading (measure with a white sheet), EXIF.

## 13. Violet Camera app, driven like a user (15:32) — WORKS ON THE PHONE
Install on the phone: copy `phone/{vcamd.c,violet-camera.py,violet-shot.py,violet-cam-app.py,install-camera.sh}` and
`tools/camera/vpipe.py` to `/var/tmp/`, run `sh install-camera.sh` (installs to `~/violet-camera`, builds `vcamd`, writes
`~/.local/share/applications/violet-camera.desktop`). Phosh only lists the app because of `X-Purism-FormFactor=Workstation;Mobile;`.
Launch "Violet Camera" from the app grid: the GTK4/libadwaita app starts `violet-camera.py daemon` itself (a child of the
graphical session survives; ssh-started ones die with the session) → vcamd (ZSL ring, AE, AF) + resident developer.
- Viewfinder: vcamd writes a 300×400 portrait RGB preview (9 Bayer cells averaged per pixel, grey-world WB, vendor CCM, gamma)
  every 4th frame to `$XDG_RUNTIME_DIR/vcamd.fifo.preview`; the app shows it as a Gdk texture. Status line = exp/gain/lens.
- Tap the preview = autofocus; round button = shutter. Shutter re-arms as soon as the raw is in RAM (0.2–0.3 s); the JPEG
  (`~/Pictures/violet-*.jpg`) is developed in the service in the background (1 frame ≈ 2.4 s, 4 dark frames ≈ 7 s) and a toast says "Saved …".
- Verified by screenshots over VNC: live preview, tap-to-focus (blurry → sharp, lens 420 → 756), shutter toast, and the saved
  JPEG (`docs/camera-2026-11-04/zsl1/app_shot_small.jpg`: sharp, whites neutral, upright).
- AF fixes found on-device: (1) cell() was reading only the 8 MSBs of each 10-bit pixel — at 16× gain that quantisation
  swamped the signal; now full 10-bit (`PX10`); (2) 4×4 cells → 8×8 cells (noise averages out; prominence of real peaks
  rose from ~1.3× to >2× over baseline); (3) the "usable window" test is relative (peak ≥1.4× the window median), no
  absolute floor; (4) dark scenes (gain·exp > 8×) average two frames per lens position; (5) no confident peak → lens 420 (mid-distance).
  Debug: `VCAMD_DEBUG=1` makes vcamd log per-window `AFWIN` lines.
- Gotchas hit: a bare `pkill -f` in an ssh command kills the ssh shell (use `pgrep -f 'x[x]'` brackets); a leftover socket file
  makes naive "exists" checks lie (the app now really connects); D-Bus activation of an unclaimed name refuses a 2nd start
  inside ~25 s, so the app now spawns the daemon itself instead.
Still open: orientation (only "up" verified), shutter-lag UI polish (spinner/thumbnail), front camera, AF in genuinely dark
featureless scenes (falls back to 420), colour/LSC calibration with a white sheet, EXIF, speed of the merge for dark scenes
(GPU/NEON), cold-start time of the app (~20 s because the service warms AE+AF), stock Snapshot cannot run while the service holds the camera.

## 14. User feedback fixes (16:10): upside-down image, focus motor noise, screen freeze while focusing
- **Upside-down**: the first rotation table (up=270 CCW) was a guess calibrated on a desk shot. A real portrait-held photo
  came out upside down. Now ROT_TABLE = up 90 (CW), rightup 180, down 270, leftup 0; the viewfinder mapping flipped the same
  way (vcamd `write_preview`: sy = H-10-x*10, sx = y*10; verified numerically against `cv2.ROTATE_90_CLOCKWISE`, corr 0.98).
  Pose now comes from `ssccli` accel with +Y = top up and **+X = right edge up** (the earlier x sign was reversed).
  Evidence: `docs/camera-2026-11-04/zsl1/app_shot2_small.jpg` (tin on a glass table with its reflection below; box text upright).
  Only the upright-portrait pose is verified; flat-on-table assumes upright.
- **Motor sound**: AF jumped the VCM across its whole range (e.g. 976→256) in single writes, which rings the spring.
  `set_lens()` now ramps in 20-code steps every 1.5 ms; coarse sweep is 11 positions (step 77) + 4 fine instead of 23 frames.
  Ramped moves are quieter but a VCM sweep is still audible; not measured (no microphone test).
- **Freeze**: vcamd stopped updating the preview during AF and the scoring ran single-threaded (~100+ ms/frame). Now the
  preview is written from AF frames too, the 8×8 cell grid is computed with OpenMP (capped at 3 threads via OMP_NUM_THREADS so the
  compositor keeps cores), AF wall time ≈ 2.3–2.4 s in a dark scene (2 averaged frames/position), results 702–795 repeatably.
  Install now builds vcamd with `-fopenmp`.
- Tooling notes: the VNC ssh tunnel goes stale after re-enumeration (restart it with a fresh `ssh -N -L 5901:127.0.0.1:5900`);
  `pkill -f <pattern that appears in your own command>` kills your own shell (exit 144) — kill by PID.

## 15. "Low clarity, no camera switch, focus blurs first" (16:35) — causes and fixes
User report: app cannot switch cameras, clarity much worse than the front camera, focus blurs before it focuses.
Causes found (with evidence):
1. **Viewfinder was 300×400 stretched to the screen** → now ~750×1000 (rear, 4×4-raw blocks, 4 Bayer cells/pixel) and 1056×784 (front).
2. **Every JPEG since the first merge had red and blue swapped.** OpenCV's Bayer names are offset from the sensor layout: RGGB
   needs `COLOR_BayerBG2BGR_EA`, BGGR needs `COLOR_BayerRG2BGR_EA`. Evidence: viewfinder (own C demosaic) showed a gold tin and
   red "KP" band, JPEGs a teal tin and blue band; test render with the corrected code (`/tmp/rb_cmp.png` logic) matches the
   viewfinder. Fixed in `vpipe.SENSORS`. The old "whites neutral" checks could not catch it (grey-world hides a global swap).
3. **AF swept the whole lens range** (visible as blur) → rewritten: tap/scene change = local hill-climb from the current lens
   position (steps 32→8, direction vote across windows with a noise estimate from two frames at the same position), ≈0.8 s,
   wide 11-position search only as fallback/first start; continuous AF refocuses locally after 3 consecutive checks where the
   detail energy leaves 0.65–1.55× of the post-focus baseline (cooldown). CAF has only been tested for not misfiring, not for
   quality on a moving scene.
4. **Dark room**: AE is pinned at max (rear 2600 lines/16×, front 3100/7.5×) so rear stills are noisy; merge now uses up to 6 frames
   at ≥14× equivalent gain (1/2/3/4/6 frames). Not fixed: longer exposure for steady phones, real denoise tuning.
New: **front camera** (OV13855, BGGR, 2112×1568, CSIPHY2, no AF, selfie-mirrored viewfinder, shot ≈1 s) and a "Selfie"/"Back" pill in the app.
One daemon binary drives both: `vcamd <video> <vcm|-> <exp-sd> <fifo> <W> <H> <bayer> <black> <smia|ov> <max-exp> <max-gain> <rot> <mirror> <sensor>`;
`violet-camera.py` has a SENSORS table, links the media graph per sensor (`media-ctl -e` finds the subdev nodes), and `camera front|rear`.
Front gain code = 256·x (OV13855), rear = SMIA. Unverified: front orientation table (assumed Android-style 270 + mirrored preview);
flat-on-table = upright assumption; motor noise (not measurable here).
Evidence: `docs/camera-2026-11-04/zsl2/rear_fixed_s.jpg` (correct colours, sharp), `front_fixed_s.jpg`, `zsl1/app_shot3_crop.jpg` (100 % crop, pre-colour-fix).

## 16. Second rear camera (S5K5E8) added as "Aux" (16:45)
User corrected me: they had seen images from both rear cameras (yesterday, GNOME Camera/Snapshot). I had wrongly dismissed the
5 MP sensor as depth-only; stock Xiaomi may use it that way, but here it is an ordinary working camera (STATUS.md: all three cameras work).
Added as third entry in `SENSORS` (violet-camera.py): `s5k5e8 2-0018`, CSIPHY1, `SGRBG10_1X10` 1296×972 (`pgAA`), fixed focus
(no VCM), exposure max 1058 lines (≈17 fps, 58 ms frame), gain code = 32·x (32..512), vendor 4500 K CCM, OpenCV demosaic code
`COLOR_BayerGB2BGR_EA` (OpenCV name = sensor layout shifted by (1,1): RGGB→BG, BGGR→RG, GRBG→GB), rotation 270 like the main rear (same CW90 table).
vcamd gain models: 0 SMIA (imx586), 1 OV (256·x), 2 S5K (32·x). App button cycles Main → Aux → Selfie and shows the current camera.
Verified: CLI shot (`docs/camera-2026-11-04/zsl2/aux1_s.jpg`: gold tin, red labels, upright, very noisy in a dim room at 16×/1000 lines)
and in the real app (screenshot, `camera=aux`). Not done: aux-based portrait blur (needs sensor sync + stereo calibration), aux
denoise tuning (more frames / chroma denoise would help), field-of-view framing difference vs main is not handled.

## 17. User's same-spot comparison (garden, daylight): why the front looked better than main and aux (17:15)
Files pulled from the phone: `docs/camera-2026-11-04/compare/{violet_main.,Violet_FE_.jpg,Violet_aux.jpg}`, same-size overview `overview.jpg`, same-FOV crops `crops_samefov.jpg`.
Measured/seen: main mean luma 60 vs front 96 vs aux 82; Laplacian variance main 22.9 (30.8 at front size) vs front 79.8 vs aux 230;
sky pink in main and front; aux strong green cast; main crop at same field of view is visibly OUT OF FOCUS (user's thumb also in frame),
front and aux crisp. Front raw black level checked on device (p1 63–66, expected 64) so its haze is scene/lens, not processing.
Causes + fixes:
1. **Main out of focus** — local AF could only creep (≤ ~190 codes) so after pointing at a distant scene it stalled, and the
   wide search was rarely reached; the 1.5 confidence threshold also made dim scenes fall back to lens 420. Now: accelerating
   hill-climb (48→128 codes while improving, halving once bracketed, up to 24 evals), failure (not bracketed) triggers the wide
   search (200–1020, 11 positions), confidence threshold 1.12, travel 150–1023. Device test: from lens 220/420/650/1000 AF settles on 610–642 (dark desk scene).
2. **Dark/muddy main** — exposure was normalised to the 99.7th percentile, so a bright sky darkened everything. Now median→0.18 linear with a
   headroom-8 tone curve (shoulder), shadow lift up to 2.8×.
3. **Pink sky** — WB gains applied to clipped pixels (R×2.1, B×1.5 on a saturated pixel). Now saturated pixels fade to neutral before tone mapping
   (viewfinder: channels clamped to white before the CCM). Test with a faked clipped sky: sky = pure white.
4. **Aux green** — grey-world over foliage. New estimator: grey-world on valid (relative floor, unclipped) pixels as a start, then iterate on near-neutral
   pixels only (±30 % of G under the current gains). Stable across scene brightness. NOT verified on real outdoor raw (none captured).
5. **Noisy aux/front** — frame count now relative to each sensor's own AE limits (d = gain·exp / (max_gain·max_exp): 1/2/3/4/6 frames), aux gets luma NLM (h=11), front h=3.
Open: aux is still very noisy in a dim room (5 MP sensor at its 16× limit); 6-frame main merge takes ≈18 s to develop on the phone (shutter is
instant, JPEG is not); front vs main "equal output size" comparison not done; lens shading not corrected.
Flashing stock Android for a reference was NOT needed: the three causes are in this repo's code. It remains an option for a quality target comparison.
