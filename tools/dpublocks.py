import mmap,os,struct
# dumps non-zero words of DPU CTL/LM/PINGPONG/SSPP blocks (phys = 0xae01000 + catalog base); display must be on
B={"ctl0":(0x1000,0x1e0),"ctl1":(0x1200,0x1e0),"ctl2":(0x1400,0x1e0),"lm0":(0x44000,0x320),"lm1":(0x45000,0x320),
   "pp0":(0x70000,0xd4),"pp1":(0x70800,0xd4),"vig0":(0x4000,0x1f0),"dma0":(0x24000,0x1f0),"dma1":(0x26000,0x1f0)}
fd=os.open("/dev/mem",os.O_RDONLY|os.O_SYNC)
import sys
for n,(b,l) in [(k,B[k]) for k in sys.argv[1:]]:
    a=0xae01000+b; pg=a&~0xfff; off=a-pg
    m=mmap.mmap(fd,((off+l+0xfff)//0x1000)*0x1000,mmap.MAP_SHARED,mmap.PROT_READ,offset=pg)
    for o in range(0,l,4):
        v=struct.unpack("<I",m[off+o:off+o+4])[0]
        if v: print("%s %03x %08x"%(n,o,v))
