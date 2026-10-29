# Touch anonymous memory page by page; print the PHYSICAL address of every 8th page (flushed) so the last line
# before a hang names the bad region.  Needs root (pagemap PFNs).
import mmap, os, struct, sys, time
total_mb = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
step = 8
pm = os.open('/proc/self/pagemap', os.O_RDONLY)
chunk = 64 << 20
n = 0
keep = []
t0 = time.time()
for c in range(total_mb // 64):
    m = mmap.mmap(-1, chunk, flags=mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS)
    keep.append(m)
    base = int.from_bytes(__import__('ctypes').string_at(0, 0), 'little') if False else None
    import ctypes
    addr = ctypes.addressof(ctypes.c_char.from_buffer(m))
    for off in range(0, chunk, 4096):
        m[off] = 1                                   # touch -> kernel picks a physical page
        if (off >> 12) % step == 0:
            e = struct.unpack('<Q', os.pread(pm, 8, ((addr + off) >> 12) * 8))[0]
            pfn = e & ((1 << 55) - 1)
            sys.stdout.write('%.1f %dMB phys=0x%x\n' % (time.time() - t0, n * 64 + (off >> 20), pfn << 12))
            sys.stdout.flush()
    n += 1
print('DONE', total_mb, 'MB')
