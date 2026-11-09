#!/usr/bin/env python3
"""Violet Camera: viewfinder + shutter for the rear camera (GTK4 / libadwaita).

Talks to the violet-camera service (vcamd + in-process developer): live preview file, `shot`, `af`, `status`.
Tap the preview to focus, press the round button to shoot. Closing the app stops the service so other camera apps work.
"""
import os, socket, subprocess, sys, threading, time

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Gdk", "4.0")
from gi.repository import Adw, Gdk, GLib, Gtk  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
RUN = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
SOCK = RUN + "/violet-camera.sock"
PREVIEW = RUN + "/vcamd.fifo.preview"
CAM = [sys.executable, os.path.join(HERE, "violet-camera.py")]

CSS = b"""
window { background: #000; }
.shutter { min-width: 76px; min-height: 76px; border-radius: 38px; background: #fff; border: 5px solid #888; padding: 0; }
.shutter:active { background: #ccc; }
.status { color: #fff; background: alpha(#000, 0.45); border-radius: 12px; padding: 4px 10px; font-size: 12px; }
"""


def call(cmd, on_line=None):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(120)
    s.connect(SOCK)
    f = s.makefile("rw")
    f.write(cmd + "\n")
    f.flush()
    last = ""
    for line in f:
        last = line.strip()
        if on_line:
            on_line(last)
    return last


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id="org.violet.Camera")
        self.mtime = 0
        self.busy = False

    def do_activate(self):
        css = Gtk.CssProvider()
        css.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.win = Adw.ApplicationWindow(application=self, default_width=360, default_height=720)
        self.toasts = Adw.ToastOverlay()
        overlay = Gtk.Overlay()
        self.pic = Gtk.Picture(content_fit=Gtk.ContentFit.CONTAIN, hexpand=True, vexpand=True)
        overlay.set_child(self.pic)
        tap = Gtk.GestureClick()
        tap.connect("released", lambda *a: self.focus())
        self.pic.add_controller(tap)
        self.status = Gtk.Label(label="starting camera…", css_classes=["status"], halign=Gtk.Align.CENTER, valign=Gtk.Align.START,
                                margin_top=14)
        overlay.add_overlay(self.status)
        self.cam = "rear"
        self.flip = Gtk.Button(label="Main")
        self.flip.add_css_class("pill")
        self.flip.add_css_class("osd")
        self.flip.set_halign(Gtk.Align.END)
        self.flip.set_valign(Gtk.Align.END)
        self.flip.set_margin_end(18)
        self.flip.set_margin_bottom(52)
        self.flip.set_tooltip_text("Switch camera: Main 48 MP / Aux 5 MP / Selfie")
        self.flip.connect("clicked", lambda *a: self.switch())
        self.flip.set_sensitive(False)
        overlay.add_overlay(self.flip)
        self.btn = Gtk.Button(css_classes=["shutter"], halign=Gtk.Align.CENTER, valign=Gtk.Align.END, margin_bottom=28)
        self.btn.connect("clicked", lambda *a: self.shoot())
        self.btn.set_sensitive(False)
        overlay.add_overlay(self.btn)
        self.toasts.set_child(overlay)
        self.win.set_content(self.toasts)
        self.win.connect("close-request", self.on_close)
        self.win.present()
        threading.Thread(target=self.boot, daemon=True).start()
        GLib.timeout_add(70, self.update_preview)
        GLib.timeout_add(1500, self.update_status)

    # ---- service plumbing
    def boot(self):
        try:
            call("status")                                   # a leftover socket file proves nothing: really connect
        except OSError:
            GLib.idle_add(self.status.set_label, "starting camera service…")
            # the app runs in the graphical session, so a child of it is not killed with an ssh login (unlike ssh-started ones)
            subprocess.Popen(CAM + ["daemon"], stdout=open("/var/tmp/vcamd.log", "a"), stderr=subprocess.STDOUT,
                             start_new_session=True)
            for _ in range(80):
                time.sleep(0.25)
                try:
                    call("status")
                    break
                except OSError:
                    pass
        try:
            st = call("status")
            GLib.idle_add(self.btn.set_sensitive, True)
            GLib.idle_add(self.flip.set_sensitive, True)
            GLib.idle_add(self.status.set_label, "ready · " + st.replace("STATUS ", ""))
        except OSError:
            GLib.idle_add(self.status.set_label, "camera service failed to start (see /var/tmp/vcamd.log)")

    def on_close(self, *a):
        threading.Thread(target=lambda: subprocess.run(CAM + ["stop"], capture_output=True), daemon=True).start()
        return False

    # ---- preview
    def update_preview(self):
        try:
            st = os.stat(PREVIEW)
            if st.st_mtime_ns != self.mtime:
                self.mtime = st.st_mtime_ns
                with open(PREVIEW, "rb") as f:
                    w, h = map(int, f.readline().split())
                    data = f.read(w * h * 3)
                if len(data) == w * h * 3:
                    tex = Gdk.MemoryTexture.new(w, h, Gdk.MemoryFormat.R8G8B8, GLib.Bytes.new(data), w * 3)
                    self.pic.set_paintable(tex)
        except (OSError, ValueError):
            pass
        return True

    def update_status(self):
        if self.busy or not os.path.exists(SOCK):
            return True

        def work():
            try:
                st = call("status")
                GLib.idle_add(self.status.set_label, st.replace("STATUS ", ""))
            except OSError:
                pass
        threading.Thread(target=work, daemon=True).start()
        return True

    # ---- actions
    def switch(self):
        if self.busy:
            return
        self.busy = True
        order = ["rear", "aux", "front"]
        want = order[(order.index(self.cam) + 1) % len(order)]
        self.btn.set_sensitive(False)
        self.flip.set_sensitive(False)
        self.status.set_label(f"switching to {want} camera…")

        def work():
            try:
                r = call(f"camera {want}")
                if r.startswith("CAMERA"):
                    self.cam = want
                    GLib.idle_add(self.flip.set_label, {"rear": "Main", "aux": "Aux", "front": "Selfie"}[want])
                    GLib.idle_add(self.status.set_label, f"{want} camera")
                else:
                    GLib.idle_add(self.toast, r)
            except OSError as e:
                GLib.idle_add(self.toast, f"error: {e}")
            finally:
                self.busy = False
                GLib.idle_add(self.btn.set_sensitive, True)
                GLib.idle_add(self.flip.set_sensitive, True)
        threading.Thread(target=work, daemon=True).start()

    def toast(self, msg):
        self.toasts.add_toast(Adw.Toast(title=msg, timeout=3))

    def focus(self):
        if self.busy:
            return
        self.busy = True
        self.status.set_label("focusing…")

        def work():
            try:
                r = call("af")
                GLib.idle_add(self.status.set_label, r)
            finally:
                self.busy = False
        threading.Thread(target=work, daemon=True).start()

    def shoot(self):
        if self.busy:
            return
        self.busy = True
        self.btn.set_sensitive(False)
        self.status.set_label("capturing…")

        def on_line(line):
            if line.startswith("CAPTURED"):
                self.busy = False                                  # the ring buffer is free again: allow the next shot
                GLib.idle_add(self.btn.set_sensitive, True)
                GLib.idle_add(self.status.set_label, "captured · developing in background…")
            elif line.startswith("DONE"):
                GLib.idle_add(self.toast, "Saved " + os.path.basename(line.split()[1]))

        def work():
            try:
                call("shot", on_line)
            except OSError as e:
                GLib.idle_add(self.toast, f"error: {e}")
            finally:
                self.busy = False
                GLib.idle_add(self.btn.set_sensitive, True)
        threading.Thread(target=work, daemon=True).start()


if __name__ == "__main__":
    sys.exit(App().run(sys.argv))
