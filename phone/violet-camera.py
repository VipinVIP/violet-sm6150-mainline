#!/usr/bin/env python3
"""violet-camera: persistent camera service (vcamd capture daemon + in-process developer) and its CLI.

    violet-camera.py start                 # start the service through the session D-Bus (survives ssh logout)
    violet-camera.py shot [N] [out]        # N frames (default: chosen from scene brightness) -> JPEG
    violet-camera.py camera front|rear     # switch sensor
    violet-camera.py af | status | stop

Service = this script in `daemon` mode: links the media pipeline for the chosen sensor, runs `vcamd` as a child (zero-shutter-lag
ring buffer, continuous AE, contrast AF on the rear camera) and keeps numpy/OpenCV loaded so a shot costs no Python start-up.
The CLI and the GTK app talk to it over a unix socket.
"""
import os, re, socket, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
RUN = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
FIFO = RUN + "/vcamd.fifo"
OUT = FIFO + ".out"
SOCK = RUN + "/violet-camera.sock"
SVC = os.path.expanduser("~/.local/share/dbus-1/services/org.violet.Camd.service")
MC = ["media-ctl", "-d", "/dev/media0"]

# Everything that differs between the two cameras. `rot` = clockwise degrees that make the sensor image upright for each way the
# phone is held (poses from the SSC accelerometer: +Y = top up, +X = right edge up). The rear value was confirmed with a real
# upside-down photo on 2026-11-04. The front value (and its mirrored viewfinder) is the usual Android arrangement and is not yet
# verified on the device.
SENSORS = {
    "rear": dict(entity="imx586 3-001a", vcm="dw9800 3-000c", csiphy="msm_csiphy0", mbus="SRGGB10_1X10", pixfmt="pRAA",
                 W=4000, H=3000, bayer="RGGB", black=64, gain="smia", max_exp=2600, max_gain=16, vpipe="imx586",
                 rot={"up": 90, "rightup": 180, "down": 270, "leftup": 0}, preview_rot=90, mirror=0),
    # 5 MP second rear sensor (Samsung S5K5E8, CCI0, CSIPHY1, GRBG, fixed focus, slow 17 fps frame). Works as a plain camera here.
    "aux": dict(entity="s5k5e8 2-0018", vcm=None, csiphy="msm_csiphy1", mbus="SGRBG10_1X10", pixfmt="pgAA",
                W=1296, H=972, bayer="GRBG", black=64, gain="s5k", max_exp=1000, max_gain=16, vpipe="s5k5e8",
                rot={"up": 90, "rightup": 180, "down": 270, "leftup": 0}, preview_rot=90, mirror=0),
    "front": dict(entity="ov13855 3-0036", vcm=None, csiphy="msm_csiphy2", mbus="SBGGR10_1X10", pixfmt="pBAA",
                  W=2112, H=1568, bayer="BGGR", black=64, gain="ov", max_exp=3100, max_gain=7.5, vpipe="ov13855",
                  rot={"up": 270, "rightup": 0, "down": 90, "leftup": 180}, preview_rot=270, mirror=1),
}


def sh(*a, **k):
    return subprocess.run(list(a), capture_output=True, text=True, **k)


def orientation():
    try:
        r = sh("ssccli", "--sensor", "accelerometer", "--duration", "1")
        a = {k: float(v) for k, v in re.findall(r"([XYZ])=(-?\d+\.\d+)", r.stdout)[-3:]}
        x, y = a["X"], a["Y"]
        if abs(x) < 2.5 and abs(y) < 2.5:          # flat on a table: no usable direction, assume upright portrait
            return "up"
        if abs(y) >= abs(x):
            return "up" if y > 0 else "down"
        return "rightup" if x > 0 else "leftup"
    except Exception:
        return "up"


# ---------------------------------------------------------------- service side
def link_pipeline(name):
    """Route the chosen sensor's CSIPHY into CSID0 -> VFE0 RDI0, set formats; return (video, vcm_subdev|'-', sensor_subdev)."""
    c = SENSORS[name]
    for p in (0, 1, 2):
        sh(*MC, "-l", f'"msm_csiphy{p}":1->"msm_csid0":0[0]')
    sh(*MC, "-l", f'"{c["csiphy"]}":1->"msm_csid0":0[1]')
    sh(*MC, "-l", '"msm_csid0":1->"msm_vfe0_rdi0":0[1]')
    f = f'{c["mbus"]}/{c["W"]}x{c["H"]}'
    sh(*MC, "-V", ",".join(f'"{e}":{p}[fmt:{f}]' for e, p in
                           [(c["entity"], 0), (c["csiphy"], 0), (c["csiphy"], 1), ("msm_csid0", 0), ("msm_csid0", 1),
                            ("msm_vfe0_rdi0", 0)]))
    sh("v4l2-ctl", "-d", "/dev/video0", f'--set-fmt-video=width={c["W"]},height={c["H"]},pixelformat={c["pixfmt"]}')
    node = lambda ent: sh(*MC, "-e", ent).stdout.strip()
    sens = node(c["entity"])
    vcm = node(c["vcm"]) if c["vcm"] else "-"
    if not sens:
        raise RuntimeError(f"no subdev for {c['entity']}")
    return "/dev/video0", vcm, sens


def spawn_vcamd(name):
    c = SENSORS[name]
    for p in subprocess.run("pgrep -f 'wireplum[b]er'", shell=True, capture_output=True, text=True).stdout.split():
        try:
            os.kill(int(p), 15)
        except OSError:
            pass
    video, vcm, sens = link_pipeline(name)
    if os.path.exists(OUT):
        os.remove(OUT)
    args = [os.path.join(HERE, "vcamd"), video, vcm, sens, FIFO, str(c["W"]), str(c["H"]), c["bayer"], str(c["black"]), c["gain"],
            str(c["max_exp"]), str(c["max_gain"]), str(c["preview_rot"]), str(c["mirror"]), c["vpipe"]]
    child = subprocess.Popen(args)
    t = time.time()
    while time.time() - t < 25 and not (os.path.exists(OUT) and "READY" in open(OUT).read()):
        time.sleep(0.1)
    return child


def vcamd_send(cmd, wait=20, prefix=None):
    n0 = os.path.getsize(OUT) if os.path.exists(OUT) else 0
    fd = os.open(FIFO, os.O_WRONLY | os.O_NONBLOCK)
    os.write(fd, (cmd + "\n").encode())
    os.close(fd)
    t = time.time()
    while time.time() - t < wait:
        time.sleep(0.01)
        if os.path.exists(OUT) and os.path.getsize(OUT) > n0:
            with open(OUT) as f:
                f.seek(n0)
                lines = [l for l in f.read().splitlines() if not l.startswith("AFSCORE")]
            lines = [l for l in lines if prefix is None or l.startswith(prefix)]
            if lines:
                return lines[-1]
    raise RuntimeError("vcamd did not answer: " + cmd)


def daemon():
    if os.path.exists(SOCK):
        os.remove(SOCK)
    sys.path.insert(0, HERE)
    import cv2
    import vpipe
    state = {"name": "rear", "child": spawn_vcamd("rear")}
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCK)
    srv.listen(4)
    lock = threading.Lock()          # vcamd access (capture / AF / status / switching)
    dev_lock = threading.Lock()      # one JPEG developed at a time, in the background

    def handle(conn):
        f = conn.makefile("rw")
        line = f.readline().split()
        say = lambda s: (f.write(s + "\n"), f.flush())
        try:
            if not line:
                return
            c = line[0]
            if c == "shot":
                n = int(line[1]) if len(line) > 1 else 0
                out = line[2] if len(line) > 2 else time.strftime("/home/user/Pictures/violet-%Y%m%d-%H%M%S.jpg")
                t0 = time.time()
                with lock:
                    name = state["name"]
                    rot = SENSORS[name]["rot"][orientation()]
                    reply = vcamd_send(f"shotu {n} /var/tmp/zsl.u16", prefix="OK")
                    _, _, got, exp, gain, lens = reply.split()
                    raw = f"/var/tmp/zsl-{int(t0 * 1000)}.u16"
                    os.replace("/var/tmp/zsl.u16", raw)
                t1 = time.time()
                say(f"CAPTURED camera={name} frames={got} exp={exp} gain={gain} lens={lens} t={t1 - t0:.2f}s")
                with dev_lock:
                    vpipe.configure(SENSORS[name]["vpipe"])
                    frames = vpipe.load(raw, int(got), True)
                    x = frames[0] if len(frames) == 1 else vpipe.merge(frames, log=lambda *a: None)[0]
                    img = vpipe.develop(x, log=lambda *a: None)
                    img = {0: img, 90: cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE), 180: cv2.rotate(img, cv2.ROTATE_180),
                           270: cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE)}[rot]
                    cv2.imwrite(out, img, [cv2.IMWRITE_JPEG_QUALITY, 93])
                    os.remove(raw)
                say(f"DONE {out} develop={time.time() - t1:.2f}s total={time.time() - t0:.2f}s")
            elif c == "camera":
                want = line[1] if len(line) > 1 else ""
                with lock:
                    if want not in SENSORS:
                        say(f"ERR unknown camera {want}")
                    elif want == state["name"]:
                        say(f"CAMERA {want}")
                    else:
                        try:
                            vcamd_send("quit", 0.3)
                        except Exception:
                            pass
                        try:
                            state["child"].wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            state["child"].kill()
                        state["child"] = spawn_vcamd(want)
                        state["name"] = want
                        say(f"CAMERA {want}")
            elif c == "af":
                with lock:
                    say(vcamd_send("af", prefix="AF", wait=30))
            elif c == "lens" and len(line) > 1:                  # debug
                with lock:
                    say(vcamd_send(f"lens {line[1]}", prefix="LENS"))
            elif c == "wideaf":
                with lock:
                    say(vcamd_send("wideaf", prefix="AF", wait=30))
            elif c == "status":
                with lock:
                    say(f"{vcamd_send('status', prefix='STATUS')} camera={state['name']}")
            elif c == "stop":
                say("BYE")
                with lock:
                    try:
                        vcamd_send("quit", 2)
                    except Exception:
                        pass
                os._exit(0)
        except Exception as e:                           # noqa: BLE001
            say(f"ERR {e}")
        finally:
            conn.close()

    while True:
        srv.settimeout(1.0)
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            if state["child"].poll() is not None and not lock.locked():
                break
            continue
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


# ---------------------------------------------------------------- client side
def call(cmd, show=True, timeout=120):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(SOCK)
    except OSError:
        raise SystemExit("camera service not running - run: violet-camera.py start")
    f = s.makefile("rw")
    f.write(cmd + "\n")
    f.flush()
    last = ""
    for line in f:
        last = line.strip()
        if show:
            print(last)
    return last


def start():
    os.makedirs(os.path.dirname(SVC), exist_ok=True)
    open(SVC, "w").write("[D-BUS Service]\nName=org.violet.Camd\n"
                         f"Exec=/bin/sh -c 'exec {sys.executable} {os.path.join(HERE, 'violet-camera.py')} daemon >>/var/tmp/vcamd.log 2>&1'\n")
    env = open(f"/proc/{sh('pgrep', '-x', 'pipewire').stdout.split()[0]}/environ", "rb").read().split(b"\0")
    addr = next(e.split(b"=", 1)[1].decode() for e in env if e.startswith(b"DBUS_SESSION_BUS_ADDRESS="))
    ping = lambda: subprocess.run(["dbus-send", f"--bus={addr}", "--print-reply", "--reply-timeout=2000", "--dest=org.violet.Camd", "/",
                                   "org.freedesktop.DBus.Peer.Ping"], capture_output=True)
    ping()
    t = time.time()
    retried = False
    while time.time() - t < 40:
        if not retried and time.time() - t > 12 and not os.path.exists(SOCK):
            retried = True
            ping()
        if os.path.exists(SOCK):
            try:
                print(call("status", show=False))
                return
            except SystemExit:
                pass
        time.sleep(0.3)
    print("service NOT ready (see /var/tmp/vcamd.log)")


if __name__ == "__main__":
    c = sys.argv[1] if len(sys.argv) > 1 else "shot"
    if c == "daemon":
        daemon()
    elif c == "start":
        start()
    elif c == "shot":
        call("shot " + " ".join(sys.argv[2:]))
    elif c in ("af", "status", "stop", "camera", "lens", "wideaf"):
        call(" ".join([c] + sys.argv[2:]))
