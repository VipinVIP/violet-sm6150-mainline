import mmap, os, struct, sys
idx = int(sys.argv[1]); val = int(sys.argv[2], 0)
fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x10000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x15000000)
def r(o): return struct.unpack_from('<I', m, o)[0]
print('before S2CR[%d]=%08x SMR=%08x' % (idx, r(0xc00 + 4*idx), r(0x800 + 4*idx)))
struct.pack_into('<I', m, 0xc00 + 4*idx, val)
print('after  S2CR[%d]=%08x' % (idx, r(0xc00 + 4*idx)))
