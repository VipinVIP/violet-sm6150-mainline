#!/usr/bin/env python3
# Create the ADSP "audiopd" static process with an AP-provided remote heap (what Android's adsprpcd audiopd does).
import fcntl, os, struct, sys, ctypes, time
memlen = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0x800000
dev = sys.argv[2] if len(sys.argv) > 2 else '/dev/fastrpc-adsp-secure'
fd = os.open(dev, os.O_RDWR)
name = ctypes.create_string_buffer(b'audiopd')
arg = struct.pack('<IIQ', 8, memlen, ctypes.addressof(name))
buf = ctypes.create_string_buffer(arg, len(arg))
IOCTL = (3 << 30) | (16 << 16) | (ord('R') << 8) | 9
try:
    fcntl.ioctl(fd, IOCTL, buf)
    print('audiopd created, heap %#x' % memlen, flush=True)
except OSError as e:
    print('INIT_CREATE_STATIC failed:', e, flush=True)
    sys.exit(1)
while True:
    time.sleep(3600)
