import sys, gi
gi.require_version("Gtk","4.0")
from gi.repository import Gtk, GLib
v = sys.argv[1]
app = Gtk.Application(application_id="test.imtest."+v)
def act(app):
    w = Gtk.ApplicationWindow(application=app)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    w.set_child(box)
    btn = Gtk.Button(label="play"); box.append(btn)
    lbl = Gtk.Label(label="no text field here"); lbl.set_vexpand(True); box.append(lbl)
    if v in ("searchbar","both","nocap"):
        sb = Gtk.SearchBar(); se = Gtk.SearchEntry(); sb.set_child(se)
        (sb.set_key_capture_widget(box) if v!="nocap" else None); box.prepend(sb)
    if v in ("hiddenentry","both"):
        e = Gtk.Entry(); e.set_visible(False); box.append(e)
    w.present()
    GLib.timeout_add(1500, lambda: (btn.grab_focus(), False)[1])
app.connect("activate", act)
app.run([])
