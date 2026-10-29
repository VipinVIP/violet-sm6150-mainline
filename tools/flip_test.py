import ctypes, fcntl, mmap, os, select, struct, sys, time
# Minimal compositor-like test: two dumb buffers on /dev/dri/card0, legacy PAGE_FLIP with events.
# Usage: flip_test.py [seconds]   (run as root, no other DRM master)

def IOWR(nr, size): return (3 << 30) | (size << 16) | (ord('d') << 8) | nr
GETRESOURCES, GETCRTC, CREATE_DUMB, MAP_DUMB = IOWR(0xA0, 64), IOWR(0xA1, 104), IOWR(0xB2, 32), IOWR(0xB3, 16)
ADDFB, PAGE_FLIP, SETCRTC = IOWR(0xAE, 28), IOWR(0xB0, 24), IOWR(0xA2, 104)

fd = os.open("/dev/dri/card0", os.O_RDWR)
res = bytearray(64); fcntl.ioctl(fd, GETRESOURCES, res)
n_crtc = struct.unpack_from("<I", res, 36)[0]
crtcs = (ctypes.c_uint32 * n_crtc)()
struct.pack_into("<QQQQ", res, 0, 0, ctypes.addressof(crtcs), 0, 0)
struct.pack_into("<IIII", res, 32, 0, n_crtc, 0, 0)
fcntl.ioctl(fd, GETRESOURCES, res)
crtc_id = None
for c in crtcs:
    cr = bytearray(104); struct.pack_into("<I", cr, 12, c); fcntl.ioctl(fd, GETCRTC, cr)
    if struct.unpack_from("<I", cr, 32)[0]:          # mode_valid
        crtc_id = c; break
w, h = 1080, 2340
print("crtc", crtc_id, flush=True)

fbs = []
for k in range(2):
    d = bytearray(struct.pack("<IIIIIIQ", h, w, 32, 0, 0, 0, 0)); fcntl.ioctl(fd, CREATE_DUMB, d)
    handle, pitch, size = struct.unpack_from("<I", d, 16)[0], struct.unpack_from("<I", d, 20)[0], struct.unpack_from("<Q", d, 24)[0]
    m = bytearray(struct.pack("<IIQ", handle, 0, 0)); fcntl.ioctl(fd, MAP_DUMB, m)
    buf = mmap.mmap(fd, size, mmap.MAP_SHARED, mmap.PROT_WRITE, offset=struct.unpack_from("<Q", m, 8)[0])
    buf[:] = (bytes([0x40, 0x80, 0x20, 0xff]) if k else bytes([0x20, 0x20, 0x80, 0xff])) * (size // 4)
    a = bytearray(struct.pack("<IIIIIII", 0, w, h, pitch, 32, 24, handle)); fcntl.ioctl(fd, ADDFB, a)
    fbs.append(struct.unpack_from("<I", a, 0)[0])
print("fbs", fbs, flush=True)

# flip back and forth between our two buffers (same size/format as fbcon's)
t0 = time.time(); n = 0; dur = float(sys.argv[1]) if len(sys.argv) > 1 else 30
while time.time() - t0 < dur:
    f = bytearray(struct.pack("<IIIIQ", crtc_id, fbs[n % 2], 1, 0, n)); fcntl.ioctl(fd, PAGE_FLIP, f)
    r, _, _ = select.select([fd], [], [], 1.0)
    if not r: print("flip %d: no event within 1 s" % n, flush=True); break
    os.read(fd, 4096); n += 1
    if n % 60 == 0: print("flips %d  t=%.1fs" % (n, time.time() - t0), flush=True)
print("done, %d flips" % n, flush=True)
