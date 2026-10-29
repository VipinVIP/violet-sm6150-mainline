import fcntl, os, struct, sys
# Disables every CRTC of /dev/dri/card0 (SETCRTC with fb 0) so the kernel runs its display-off path.
# Needs root and no other DRM master (stop the compositor first).

def IOWR(nr, size):
    return (3 << 30) | (size << 16) | (ord('d') << 8) | nr

GETRESOURCES = IOWR(0xA0, 64)
SETCRTC = IOWR(0xA2, 104)

fd = os.open(sys.argv[1] if len(sys.argv) > 1 else "/dev/dri/card0", os.O_RDWR)
res = bytearray(64)
fcntl.ioctl(fd, GETRESOURCES, res)
n_crtcs = struct.unpack_from("<I", res, 36)[0]
crtcs = (struct.Struct("<%dI" % n_crtcs))
buf = bytearray(4 * n_crtcs)
addr = (struct.unpack("<Q", struct.pack("<Q", id(buf)))[0])  # placeholder, replaced below

import ctypes
cbuf = (ctypes.c_uint32 * n_crtcs)()
struct.pack_into("<Q", res, 8, ctypes.addressof(cbuf))   # crtc_id_ptr
struct.pack_into("<IIII", res, 32, 0, n_crtcs, 0, 0)     # only ask for crtcs
fcntl.ioctl(fd, GETRESOURCES, res)
for cid in list(cbuf):
    c = bytearray(104)
    struct.pack_into("<QIIIIIII", c, 0, 0, 0, cid, 0, 0, 0, 0, 0)
    try:
        fcntl.ioctl(fd, SETCRTC, c)
        print("crtc %d disabled" % cid)
    except OSError as e:
        print("crtc %d: %s" % (cid, e))
