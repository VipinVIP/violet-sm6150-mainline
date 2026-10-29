#!/usr/bin/env python3
"""i2c-scan.py - probe addresses on an i2c-dev bus and read registers, no i2c-tools needed.

Usage: i2c-scan.py /dev/i2c-0 [addr_hex] [reg_hex] [count]

No args beyond the bus: scans 0x03-0x77 with a zero-length (quick) write and prints who ACKs.
With addr+reg: does a write-then-read of that register and hexdumps the result.
This is how we tell "the chip is not powered / bus is dead" (nothing ACKs anywhere) apart from
"the chip answers but the driver disagrees" (0x62 ACKs, read returns data).
"""
import ctypes
import fcntl
import sys

I2C_RDWR = 0x0707


class I2cMsg(ctypes.Structure):
    _fields_ = [("addr", ctypes.c_uint16),
                ("flags", ctypes.c_uint16),
                ("len", ctypes.c_uint16),
                ("buf", ctypes.POINTER(ctypes.c_uint8))]


class I2cRdwrIoctlData(ctypes.Structure):
    _fields_ = [("msgs", ctypes.POINTER(I2cMsg)),
                ("nmsgs", ctypes.c_uint32)]


def _ioctl(fd, msgs):
    arr = (I2cMsg * len(msgs))(*msgs)
    data = I2cRdwrIoctlData(arr, len(msgs))
    fcntl.ioctl(fd, I2C_RDWR, bytes(data))


def probe(fd, addr):
    """Zero-length write = i2cdetect's 'quick' probe. Device ACK -> no exception."""
    try:
        _ioctl(fd, [I2cMsg(addr, 0, 0, None)])
        return 0
    except OSError as exc:
        return exc.errno


def read_reg(fd, addr, reg, count):
    wbuf = (ctypes.c_uint8 * 1)(reg)
    rbuf = (ctypes.c_uint8 * count)()
    _ioctl(fd, [I2cMsg(addr, 0, 1, wbuf), I2cMsg(addr, 1, count, rbuf)])
    return bytes(rbuf)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    bus = sys.argv[1]
    fd = open(bus, "r+b", buffering=0)
    fileno = fd.fileno()

    if len(sys.argv) == 2:
        found = []
        for addr in range(0x03, 0x78):
            rc = probe(fileno, addr)
            if rc == 0:
                found.append(addr)
                print("ACK  0x%02x" % addr)
            elif rc not in (121, 6, 19):   # EREMOTEIO (NACK), ENXIO, ENODEV
                print("0x%02x errno=%d (%s)" % (addr, rc, errno_name(rc)))
        print("scan done: %d device(s) ACKed%s" %
              (len(found), "" if found else " - bus dead or nothing powered"))
        return 0 if found else 1

    addr = int(sys.argv[2], 0)
    reg = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x01
    count = int(sys.argv[4], 0) if len(sys.argv) > 4 else 1
    print("probe 0x%02x: %s" % (addr, "ACK" if probe(fileno, addr) == 0 else "NO ACK"))
    try:
        data = read_reg(fileno, addr, reg, count)
        print("reg 0x%02x -> %s" % (reg, " ".join("%02x" % b for b in data)))
        return 0
    except OSError as exc:
        print("reg 0x%02x read failed: errno=%d (%s)" % (reg, exc.errno, exc.strerror))
        return 1


def errno_name(rc):
    import os
    return os.strerror(rc)


if __name__ == "__main__":
    sys.exit(main())
