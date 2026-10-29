#!/usr/bin/env python3
"""Sample the TAS2563 PWR_CTL while a speaker stream is running.

A5 question: does the amp actually leave software shutdown (PWR_CTL.MODE=10)
while audio plays, and does it drop back afterwards?  Uses I2C_SLAVE_FORCE
(0x0706) because the tas2781 driver owns the address on bus 1.

Observed states on violet (do not over-interpret the bitfield — these are the
values that actually occur, and 0x0c is the state in which the tone is audible):
  0x0e  idle / after the stream  == amp in software shutdown
  0x0c  while a stream runs      == amp powered (the 2026-10-26 "speaker audible"
                                     run read exactly 0x0c during the tone)
Bit 1 is what differs between the two; the datasheet MODE field is not bits[1:0]
in the way the earlier version of this script assumed.
"""
import fcntl
import os
import subprocess
import time

I2C_SLAVE_FORCE = 0x0706
ADDR = 0x4C
PAGE_REG, PAGE_BOOK = 0x00, 0x7F
PWR_CTL = 0x02

fd = os.open("/dev/i2c-1", os.O_RDWR)
fcntl.ioctl(fd, I2C_SLAVE_FORCE, ADDR)


def rd(reg):
    os.write(fd, bytes([reg]))
    return os.read(fd, 1)[0]


def pwr_ctl():
    os.write(fd, bytes([PAGE_REG, 0]))
    os.write(fd, bytes([PAGE_BOOK, 0]))
    return rd(PWR_CTL)


KNOWN = {0x0E: "shutdown (idle)", 0x0C: "powered (streaming)"}


def describe(v):
    return KNOWN.get(v, "unmapped value")


print(f"idle           PWR_CTL=0x{pwr_ctl():02x} ({describe(pwr_ctl())})", flush=True)

proc = subprocess.Popen(
    ["speaker-test", "-D", "hw:0,2", "-c", "2", "-t", "sine", "-f", "440", "-l", "1"],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
time.sleep(0.8)
for i in range(10):
    v = pwr_ctl()
    print(f"stream t+{i * 0.5:0.1f}s  PWR_CTL=0x{v:02x} ({describe(v)})", flush=True)
    time.sleep(0.5)

proc.wait(timeout=15)
time.sleep(0.5)
v = pwr_ctl()
print(f"after stream   PWR_CTL=0x{v:02x} ({describe(v)})", flush=True)
