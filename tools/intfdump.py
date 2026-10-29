import mmap,os,struct
# dumps DPU INTF_1 (0xae6b800, 0x2c0) non-zero words; only safe while the display is on
fd=os.open("/dev/mem",os.O_RDONLY|os.O_SYNC)
m=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ,offset=0xae6b000)
for o in range(0,0x2c0,4):
    v=struct.unpack("<I",m[0x800+o:0x804+o])[0]
    if v: print("%08x %08x"%(0xae6b800+o,v))
