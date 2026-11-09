#!/usr/bin/env python3
# Tap a series of points on one virtual touchscreen (typing on the on-screen keyboard).
# Usage (root): taps.py X,Y X,Y ...   - panel pixels, 1080x2340 portrait.
import sys
import time

from evdev import AbsInfo, UInput, ecodes as e

W, H = 1080, 2340
cap = {
    e.EV_KEY: [e.BTN_TOUCH],
    e.EV_ABS: [
        (e.ABS_X, AbsInfo(0, 0, W - 1, 0, 0, 0)),
        (e.ABS_Y, AbsInfo(0, 0, H - 1, 0, 0, 0)),
        (e.ABS_MT_SLOT, AbsInfo(0, 0, 9, 0, 0, 0)),
        (e.ABS_MT_TRACKING_ID, AbsInfo(0, 0, 65535, 0, 0, 0)),
        (e.ABS_MT_POSITION_X, AbsInfo(0, 0, W - 1, 0, 0, 0)),
        (e.ABS_MT_POSITION_Y, AbsInfo(0, 0, H - 1, 0, 0, 0)),
    ],
}

pts = [tuple(int(v) for v in a.split(",")) for a in sys.argv[1:]]
with UInput(cap, name="violet-virtual-touch", input_props=[e.INPUT_PROP_DIRECT]) as ui:
    time.sleep(1.0)
    for n, (x, y) in enumerate(pts, 1):
        ui.write(e.EV_ABS, e.ABS_MT_SLOT, 0)
        ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, n)
        ui.write(e.EV_KEY, e.BTN_TOUCH, 1)
        for ax, v in ((e.ABS_MT_POSITION_X, x), (e.ABS_MT_POSITION_Y, y), (e.ABS_X, x), (e.ABS_Y, y)):
            ui.write(e.EV_ABS, ax, v)
        ui.syn()
        time.sleep(0.08)
        ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1)
        ui.write(e.EV_KEY, e.BTN_TOUCH, 0)
        ui.syn()
        time.sleep(0.25)
    time.sleep(0.3)
