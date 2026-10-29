import mmap,os,struct,time,sys
# sets INTF_1 PROG_FETCH_START (0xae6b800 + 0x170) and shows the DSI status
fd=os.open("/dev/mem",os.O_RDWR|os.O_SYNC)
i=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ|mmap.PROT_WRITE,offset=0xae6b000)
d=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ|mmap.PROT_WRITE,offset=0xae94000)
rd=lambda m,o: struct.unpack("<I",m[o:o+4])[0]
def st(t): print(t,"pf_en=%08x pf_start=%08x fifo=%08x lane=%08x clk=%08x"%(rd(i,0x96c),rd(i,0x970),rd(d,0xc),rd(d,0xa8),rd(d,0x120)))
st("before")
i[0x970:0x974]=struct.pack("<I",int(sys.argv[1],0))
d[0xc:0x10]=struct.pack("<I",0xffffffff); time.sleep(0.5); st("after")
