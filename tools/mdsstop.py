import mmap,os,struct
# dumps MDSS top (0xae00000, 0x400) non-zero words
fd=os.open("/dev/mem",os.O_RDONLY|os.O_SYNC)
m=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ,offset=0xae00000)
for o in range(0,0x400,4):
    v=struct.unpack("<I",m[o:o+4])[0]
    if v: print("%08x %08x"%(0xae00000+o,v))
