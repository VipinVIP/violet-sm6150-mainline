import mmap,os,struct,time
# turns on DISP_CC_MDSS_ROT_CLK (CBCR 0xaf02010) and watches the DSI status
fd=os.open("/dev/mem",os.O_RDWR|os.O_SYNC)
c=mmap.mmap(fd,0x3000,mmap.MAP_SHARED,mmap.PROT_READ|mmap.PROT_WRITE,offset=0xaf00000)
d=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ|mmap.PROT_WRITE,offset=0xae94000)
rd=lambda m,o: struct.unpack("<I",m[o:o+4])[0]
def st(t): print(t,"rot=%08x fifo=%08x lane=%08x clk=%08x"%(rd(c,0x2010),rd(d,0xc),rd(d,0xa8),rd(d,0x120)))
st("before")
c[0x2010:0x2014]=struct.pack("<I",rd(c,0x2010)|1)
time.sleep(0.1); st("rot on")
d[0xc:0x10]=struct.pack("<I",0xffffffff); time.sleep(0.5); st("cleared")
