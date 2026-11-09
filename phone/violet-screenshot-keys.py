#!/usr/bin/env python3
"""Android-style screenshot chord: press Power and Volume Down together.

Runs as root (OpenRC service violet-screenshot-keys). It grabs the Power and Volume Down evdev
devices (EVIOCGRAB) and re-emits their events to Phosh through a uinput device, but holds each key
press back for CHORD_WINDOW seconds. If the other key is pressed inside that window it is a chord:
both keys are swallowed (the phone does not blank, the volume does not change) and Phosh is asked
for a screenshot (org.gnome.Shell.Screenshot, saved to ~/Pictures/Screenshots/). Otherwise the held
press is forwarded, so normal use is only CHORD_WINDOW late. The grabs vanish if this process dies.

  violet-screenshot-keys [--dry-run] [--power DEV] [--voldown DEV] [--no-forward]
"""
import fcntl
import glob
import os
import select
import struct
import subprocess
import sys
import threading
import time

EV_SYN, EV_KEY = 0, 1
KEY_POWER, KEY_VOLUMEDOWN = 116, 114
OTHER = {KEY_POWER: KEY_VOLUMEDOWN, KEY_VOLUMEDOWN: KEY_POWER}
EVIOCGRAB = 0x40044590
UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_SETUP, UI_DEV_CREATE = 0x40045564, 0x40045565, 0x405C5503, 0x5501
EVENT_FMT = "llHHi"  # struct input_event on 64-bit: timeval (2 longs), type, code, value
EVENT_SIZE = struct.calcsize(EVENT_FMT)

CHORD_WINDOW = 0.15  # both keys within this many seconds = chord (Android uses 150 ms too)
COOLDOWN = 2.0  # ignore repeated chords for this long
USER = "user"
SHOT_DIR = "/home/user/Pictures/Screenshots"
SOUND = "/usr/share/sounds/freedesktop/stereo/camera-shutter.oga"


class Filter:
    """Chord logic without any I/O. key()/tick() return actions:
    ("fwd", code, value) to pass a key event on, or ("shot",) to take a screenshot."""

    def __init__(self):
        self.pending = None  # (code, press time): a press held back, waiting for a possible chord
        self.state = {KEY_POWER: None, KEY_VOLUMEDOWN: None}  # None | "forwarded" | "swallowed"
        self.last_shot = -1e9

    def _flush(self):
        code, _ = self.pending
        self.pending = None
        self.state[code] = "forwarded"
        return [("fwd", code, 1)]

    def key(self, code, value, now):
        other = OTHER[code]
        if value == 1:
            if self.pending and self.pending[0] == other and now - self.pending[1] <= CHORD_WINDOW:
                self.pending = None
                self.state[code] = self.state[other] = "swallowed"
                if now - self.last_shot < COOLDOWN:
                    return []
                self.last_shot = now
                return [("shot",)]
            actions = self._flush() if self.pending else []
            if self.state[other] == "forwarded":  # the other key was held past the window: not a chord
                self.state[code] = "forwarded"
                return actions + [("fwd", code, 1)]
            self.pending = (code, now)
            return actions
        if value == 0:
            if self.pending and self.pending[0] == code:  # a tap shorter than the window
                self.pending = None
                self.state[code] = None
                return [("fwd", code, 1), ("fwd", code, 0)]
            was, self.state[code] = self.state[code], None
            return [] if was == "swallowed" else [("fwd", code, 0)]
        return [("fwd", code, 2)] if self.state[code] == "forwarded" else []  # auto-repeat

    def tick(self, now):
        if self.pending and now - self.pending[1] >= CHORD_WINDOW:
            return self._flush()
        return []

    def next_timeout(self, now):
        return None if not self.pending else max(0.0, self.pending[1] + CHORD_WINDOW - now)


class Forwarder:
    """A uinput device that re-emits the grabbed keys."""

    def __init__(self):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        for code in OTHER:
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, code)
        fcntl.ioctl(self.fd, UI_DEV_SETUP, struct.pack("HHHH80sI", 0x06, 0x1209, 0x5342, 1, b"violet-chord-forward", 0))
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        time.sleep(0.4)  # let the compositor pick the new device up

    def emit(self, code, value):
        os.write(self.fd, struct.pack(EVENT_FMT, 0, 0, EV_KEY, code, value))
        os.write(self.fd, struct.pack(EVENT_FMT, 0, 0, EV_SYN, 0, 0))


def find_event_device(name):
    for path in sorted(glob.glob("/sys/class/input/event*")):
        try:
            with open(os.path.join(path, "device", "name")) as f:
                if f.read().strip() == name:
                    return "/dev/input/" + os.path.basename(path)
        except OSError:
            continue
    return None


def session_bus():
    """D-Bus address of the running Phosh session, so a root service can reach the user's bus."""
    pids = subprocess.run(["pgrep", "-x", "phoc"], capture_output=True, text=True).stdout.split()
    if pids:
        with open("/proc/%s/environ" % pids[0], "rb") as f:
            for item in f.read().split(b"\0"):
                if item.startswith(b"DBUS_SESSION_BUS_ADDRESS="):
                    return item.split(b"=", 1)[1].decode()
    return None


def take_screenshot(dry_run):
    path = "%s/screenshot-%s.png" % (SHOT_DIR, time.strftime("%Y%m%d-%H%M%S"))
    if dry_run:
        print("SCREENSHOT", path, flush=True)
        return
    bus = session_bus()
    if not bus:
        print("no Phosh session, no screenshot", file=sys.stderr, flush=True)
        return
    env = ["sudo", "-n", "-u", USER, "env", "XDG_RUNTIME_DIR=/run/user/10000", "DBUS_SESSION_BUS_ADDRESS=" + bus]
    subprocess.run(env + ["mkdir", "-p", SHOT_DIR])
    for attempt in (1, 2):
        out = subprocess.run(env + ["gdbus", "call", "--session", "--dest", "org.gnome.Shell.Screenshot",
                                    "--object-path", "/org/gnome/Shell/Screenshot",
                                    "--method", "org.gnome.Shell.Screenshot.Screenshot", "false", "true", path],
                             capture_output=True, text=True, timeout=20)
        print("phosh screenshot attempt %d: %s" % (attempt, out.stdout.strip() or out.stderr.strip()), flush=True)
        if out.stdout.startswith("(true"):
            subprocess.Popen(env + ["paplay", SOUND], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        time.sleep(0.5)


def main(argv):
    dry_run = "--dry-run" in argv
    power_path = argv[argv.index("--power") + 1] if "--power" in argv else find_event_device("pm8941_pwrkey")
    vol_path = argv[argv.index("--voldown") + 1] if "--voldown" in argv else find_event_device("pm8941_resin")
    if not power_path or not vol_path:
        print("power/volume-down input devices not found", file=sys.stderr)
        return 1
    devices = [open(power_path, "rb", buffering=0), open(vol_path, "rb", buffering=0)]

    forwarder = None
    if "--no-forward" not in argv:
        try:
            forwarder = Forwarder()
            for dev in devices:
                fcntl.ioctl(dev, EVIOCGRAB, 1)
        except OSError as err:  # without the grab the keys still reach Phosh: chord detection only
            print("cannot grab keys / create uinput device (%s): chord detection only" % err, flush=True)
            forwarder = None
    print("watching %s %s, forwarding=%s%s" % (power_path, vol_path, bool(forwarder), " (dry run)" if dry_run else ""),
          flush=True)

    flt = Filter()

    def run(actions):
        for action in actions:
            if action[0] == "fwd" and forwarder:
                forwarder.emit(action[1], action[2])
            elif action[0] == "shot":
                threading.Thread(target=take_screenshot, args=(dry_run,), daemon=True).start()

    while True:
        ready, _, _ = select.select(devices, [], [], flt.next_timeout(time.monotonic()))
        run(flt.tick(time.monotonic()))
        for dev in ready:
            data = dev.read(EVENT_SIZE * 8)
            for off in range(0, len(data) - EVENT_SIZE + 1, EVENT_SIZE):
                _, _, etype, code, value = struct.unpack(EVENT_FMT, data[off:off + EVENT_SIZE])
                if etype == EV_KEY and code in OTHER and value in (0, 1, 2):
                    now = time.monotonic()
                    actions = flt.key(code, value, now)
                    if value != 2:
                        print("%.3f %s %s -> %s" % (now, "POWER" if code == KEY_POWER else "VOLDOWN",
                                                    "down" if value else "up", actions or "-"), flush=True)
                    run(actions)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
