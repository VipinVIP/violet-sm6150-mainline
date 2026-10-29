import mmap,os,struct,time,sys
# usage: intfpeek.py  -> dumps INTF_1 (0xae6a800) regs 0x000-0x0b4 + 0x26c, twice 0.5 s apart
fd=os.open("/dev/mem",os.O_RDONLY|os.O_SYNC)
m=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ,offset=0xae6a000)
rd=lambda o: struct.unpack("<I",m[0x800+o:0x800+o+4])[0]
for k in range(2):
    print("pass",k," ".join("%03x=%08x"%(o,rd(o)) for o in list(range(0,0xb8,4))+[0x26c]))
    time.sleep(0.5)
