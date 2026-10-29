import mmap, os, struct
fd = os.open('/dev/mem', os.O_RDONLY | os.O_SYNC)
base = 0x15000000
m = mmap.mmap(fd, 0x10000, mmap.MAP_SHARED, mmap.PROT_READ, offset=base)
def r(o): return struct.unpack_from('<I', m, o)[0]
print('ID0 %08x ID1 %08x ID2 %08x sCR0 %08x' % (r(0x20), r(0x24), r(0x28), r(0x0)))
n = 68
for i in range(n):
    smr = r(0x800 + 4*i); s2 = r(0xc00 + 4*i)
    if smr & 0x80000000:
        sid = smr & 0x7fff; mask = (smr >> 16) & 0x7fff
        print('SMR%02d id=%04x mask=%04x  S2CR=%08x type=%d cbndx=%d' % (i, sid, mask, s2, (s2>>16)&3, s2&0xff))
