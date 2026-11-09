#!/usr/bin/env python3
"""violet-shot: rear-camera still = auto-exposure -> contrast AF -> raw burst -> merge/develop -> JPEG.

Run as root on the phone (needs /dev/media0, /dev/video0, the DW9800 subdev):
    sudo python3 violet-shot.py [out.jpg]
Needs violet-af (built from violet-af.c) and vpipe.py next to this script.
"""
import glob, os, subprocess, sys, time
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
M = ["media-ctl", "-d", "/dev/media0"]
W, H, STRIDE = 4000, 3000, 5008
MAX_EXP = 2600            # lines; ~28 ms -> still hand-holdable
MAX_GAIN = 16.0           # linear analogue gain
TARGET = 150.0            # mean green level after black subtraction (of 959)


def sh(*a, check=False, **k):
    return subprocess.run(list(a), capture_output=True, text=True, check=check, **k)


def setup():
    for p in subprocess.run("pgrep -f 'wireplum[b]er'", shell=True, capture_output=True, text=True).stdout.split():
        os.kill(int(p), 15)
    time.sleep(1.5)
    for p in (1, 2):
        sh(*M, "-l", f'"msm_csiphy{p}":1->"msm_csid0":0[0]')
    sh(*M, "-l", '"msm_csiphy0":1->"msm_csid0":0[1]')
    sh(*M, "-l", '"msm_csid0":1->"msm_vfe0_rdi0":0[1]')
    f = "SRGGB10_1X10/4000x3000"
    sh(*M, "-V", ",".join(f'"{e}":{p}[fmt:{f}]' for e, p in
        [("imx586 3-001a", 0), ("msm_csiphy0", 0), ("msm_csiphy0", 1), ("msm_csid0", 0), ("msm_csid0", 1), ("msm_vfe0_rdi0", 0)]))
    sh("v4l2-ctl", "-d", "/dev/video0", "--set-fmt-video=width=4000,height=3000,pixelformat=pRAA")
    exp_sd = vcm_sd = None
    for sd in sorted(glob.glob("/dev/v4l-subdev*")):
        out = sh("v4l2-ctl", "-d", sd, "-L").stdout
        if "focus_absolute" in out:
            vcm_sd = sd
        if "analogue_gain" in out and "exposure" in out and "max=3048" in out:
            exp_sd = sd
    if not (exp_sd and vcm_sd):
        sys.exit(f"subdevs not found exp={exp_sd} vcm={vcm_sd}")
    return exp_sd, vcm_sd


def gain_code(x):         # SMIA analogue gain: x = 1024 / (1024 - code)
    return int(round(1024 - 1024 / x))


def set_exposure(exp_sd, exp, gain_x):
    sh("v4l2-ctl", "-d", exp_sd, "-c", f"exposure={int(exp)},analogue_gain={gain_code(gain_x)}")


def grab_raw(path, n):
    r = sh("v4l2-ctl", "-d", "/dev/video0", "--stream-mmap", f"--stream-count={n}", f"--stream-to={path}", timeout=60)
    return os.path.getsize(path) // (STRIDE * H)


def stats(path):
    buf = np.fromfile(path, np.uint8)
    f = buf[-STRIDE * H:].reshape(H, STRIDE)[::8, :5000].reshape(H // 8, 1000, 5)
    g = (f[:, :, 1].astype(np.float32) * 4 - 64)      # one green-ish MSB per 4 px
    return float(g.mean()), float(np.percentile(g, 99.5))


def meter(exp_sd):
    exp, gain = 1500.0, 1.0
    for i in range(4):
        set_exposure(exp_sd, exp, gain)
        grab_raw("/var/tmp/meter.raw", 3)
        mean, hi = stats("/var/tmp/meter.raw")
        mean = max(mean, 0.5)
        scale = TARGET / mean
        if hi * scale > 900:           # protect highlights
            scale = 900 / max(hi, 1)
        total = exp * gain * scale
        exp = min(max(total, 8), MAX_EXP)
        gain = min(max(total / exp, 1.0), MAX_GAIN)
        print(f"  AE {i}: mean={mean:.1f} p99.5={hi:.0f} -> exp={exp:.0f} gain={gain:.2f}x")
        if 0.8 < scale < 1.25:
            break
    set_exposure(exp_sd, exp, gain)
    return exp, gain


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else time.strftime("/home/user/Pictures/violet-%Y%m%d-%H%M%S.jpg")
    t0 = time.time()
    exp_sd, vcm_sd = setup()
    print(f"setup {time.time()-t0:.1f}s")
    exp, gain = meter(exp_sd)
    af = sh(os.path.join(HERE, "violet-af"), "/dev/video0", vcm_sd, exp_sd, str(int(exp)), str(gain_code(gain)))
    print("  AF:", af.stdout.strip().splitlines()[-1] if af.stdout.strip() else af.stderr)
    set_exposure(exp_sd, exp, gain)
    n = 6 if gain < 2 else 8 if gain < 6 else 10
    t1 = time.time()
    got = grab_raw("/var/tmp/burst.raw", n)
    print(f"burst {got} frames in {time.time()-t1:.1f}s")
    r = sh(sys.executable, os.path.join(HERE, "vpipe.py"), "/var/tmp/burst.raw", out, "--rotate", "270")
    print(r.stdout.strip().splitlines()[-1] if r.stdout.strip() else r.stderr[-300:])
    print(f"total {time.time()-t0:.1f}s -> {out}")


if __name__ == "__main__":
    main()
