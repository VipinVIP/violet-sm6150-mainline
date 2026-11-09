#!/usr/bin/env python3
# Press a key on a virtual keyboard (root). Usage: key.py ESC | LEFTALT+LEFT | ...
import sys
import time

from evdev import UInput, ecodes as e

keys = [getattr(e, "KEY_" + k.upper()) for k in sys.argv[1].split("+")]
with UInput({e.EV_KEY: keys}, name="violet-virtual-kbd") as ui:
    time.sleep(1.0)
    for k in keys:
        ui.write(e.EV_KEY, k, 1)
    ui.syn()
    time.sleep(0.1)
    for k in reversed(keys):
        ui.write(e.EV_KEY, k, 0)
    ui.syn()
    time.sleep(0.3)
