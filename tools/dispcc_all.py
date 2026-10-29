import mmap,os,struct
# dumps DISP_CC 0xaf02000-0xaf02200 (branches + RCGs) and 0xaf00000-0xaf00040 (PLL0)
fd=os.open("/dev/mem",os.O_RDONLY|os.O_SYNC)
m=mmap.mmap(fd,0x3000,mmap.MAP_SHARED,mmap.PROT_READ,offset=0xaf00000)
for o in list(range(0x0,0x40,4))+list(range(0x2000,0x2200,4)):
    print("%04x %08x"%(o,struct.unpack("<I",m[o:o+4])[0]))
