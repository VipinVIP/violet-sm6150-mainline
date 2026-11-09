#!/usr/bin/env python3
# Inject touch taps/swipes into the Phosh session through a virtual uinput
# touchscreen, so the UI can be driven over ssh (no ydotool on the device).
#
# Usage (root): tap.py X Y            - tap at panel pixel (X, Y)
#               tap.py X1 Y1 X2 Y2    - swipe from (X1,Y1) to (X2,Y2)
# Coordinates are panel pixels, 1080x2340 portrait, same as a screenshot.
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


def move(ui, x, y):
    ui.write(e.EV_ABS, e.ABS_MT_POSITION_X, x)
    ui.write(e.EV_ABS, e.ABS_MT_POSITION_Y, y)
    ui.write(e.EV_ABS, e.ABS_X, x)
    ui.write(e.EV_ABS, e.ABS_Y, y)
    ui.syn()


def main():
    pts = [int(a) for a in sys.argv[1:]]
    if len(pts) not in (2, 4):
        sys.exit(__doc__ or "usage: tap.py X Y [X2 Y2]")

    with UInput(cap, name="violet-virtual-touch", input_props=[e.INPUT_PROP_DIRECT]) as ui:
        time.sleep(1.0)  # let udev/libinput pick the device up
        ui.write(e.EV_ABS, e.ABS_MT_SLOT, 0)
        ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, 1)
        ui.write(e.EV_KEY, e.BTN_TOUCH, 1)
        move(ui, pts[0], pts[1])
        if len(pts) == 4:
            steps = 15
            for i in range(1, steps + 1):
                time.sleep(0.02)
                move(ui, pts[0] + (pts[2] - pts[0]) * i // steps,
                     pts[1] + (pts[3] - pts[1]) * i // steps)
        else:
            time.sleep(0.08)
        ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1)
        ui.write(e.EV_KEY, e.BTN_TOUCH, 0)
        ui.syn()
        time.sleep(0.3)


if __name__ == "__main__":
    main()
