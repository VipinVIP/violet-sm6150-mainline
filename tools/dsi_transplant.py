import mmap,os,struct,time,sys
# writes r10's values for the remaining DSI PHY lane-timing / PLL differences, clears FIFO status, re-reads
fd=os.open("/dev/mem",os.O_RDWR|os.O_SYNC)
m=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ|mmap.PROT_WRITE,offset=0xae94000)
rd=lambda o: struct.unpack("<I",m[o:o+4])[0]
def wr(o,v): m[o:o+4]=struct.pack("<I",v)
def st(t): print(t,"fifo=%08x lane=%08x clk=%08x ctrl=%08x"%(rd(0xc),rd(0xa8),rd(0x120),rd(0x4)))
st("before")
if "lanes" in sys.argv:
    for i in range(4):
        b=0x500+i*0x80; wr(b+0x1c,0x21); wr(b+0x20,0x09); wr(b+0x2c,0x02)
    wr(0x72c,0x02)
if "pll" in sys.argv:
    wr(0x8b4,0xa3); wr(0x8b8,0x92)
wr(0xc,0xffffffff); time.sleep(0.2); st("after clear")
time.sleep(1); st("1s later")
