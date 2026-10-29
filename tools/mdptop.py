import mmap,os,struct,sys,time
# dumps DPU MDP_TOP (0xae01000, 0x460) non-zero words, and INTF_1 frame/line count twice
fd=os.open("/dev/mem",os.O_RDONLY|os.O_SYNC)
m=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ,offset=0xae01000)
for o in range(0,0x460,4):
    v=struct.unpack("<I",m[o:o+4])[0]
    if v: print("%08x %08x"%(0xae01000+o,v))
i=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ,offset=0xae6b000)
for k in range(2):
    print("intf1 frame=%d line=%d en=%d"%(struct.unpack("<I",i[0x8ac:0x8b0])[0],struct.unpack("<I",i[0x8b0:0x8b4])[0],struct.unpack("<I",i[0x800:0x804])[0]))
    time.sleep(0.5)
