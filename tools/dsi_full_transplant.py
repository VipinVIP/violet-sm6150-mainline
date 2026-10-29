import mmap,os,struct,sys,time
# Writes r10's DSI controller config (debug-backup/dsi_r10.txt, ctrl range only) into the running
# DSI, skipping status / irq / readout registers, then restarts the video engine.
SKIP={0x000,0x008,0x00c,0x0a8,0x0b4,0x0c0,0x110,0x120,0x134,0x138,0x13c,0x140,0x148,0x14c,0x150,0x154,0x1c8,0x334,0x338,0x33c}
vals={}
for l in open(sys.argv[1]):
    a,v,blk=l.split()
    a=int(a,16)-0xae94000
    if blk=="dsi_ctrl" and a not in SKIP and a!=0x004: vals[a]=int(v,16)
fd=os.open("/dev/mem",os.O_RDWR|os.O_SYNC)
m=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ|mmap.PROT_WRITE,offset=0xae94000)
rd=lambda o: struct.unpack("<I",m[o:o+4])[0]
def wr(o,v): m[o:o+4]=struct.pack("<I",v)
def st(t): print(t,"ctrl=%08x fifo=%08x lane=%08x clk=%08x"%(rd(4),rd(0xc),rd(0xa8),rd(0x120)))
st("before")
diff=[(o,rd(o),v) for o,v in sorted(vals.items()) if rd(o)!=v]
for o,old,v in diff: print("  %03x %08x -> %08x"%(o,old,v))
for o in range(0,0x400,4):
    if o in vals: pass
for o,old,v in diff: wr(o,v)
c=rd(4); wr(4,c&~2); time.sleep(0.05); wr(0xc,0xffffffff); wr(4,c)
time.sleep(0.5); st("after")
