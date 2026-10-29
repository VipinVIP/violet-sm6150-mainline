import mmap,os,struct,time,sys
# Live DSI/INTF experiments from the ginkgo notes. Physical offsets (DSI 6G = reg + 4).
fd=os.open("/dev/mem",os.O_RDWR|os.O_SYNC)
d=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ|mmap.PROT_WRITE,offset=0xae94000)
i=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ|mmap.PROT_WRITE,offset=0xae6b000)
R=lambda m,o: struct.unpack("<I",m[o:o+4])[0]
def W(m,o,v): m[o:o+4]=struct.pack("<I",v)
CTRL,LANE_CTRL,RESET,CLK_CTRL,FIFO,LANE_ST,CLK_ST=0x004,0x0ac,0x118,0x11c,0x00c,0x0a8,0x120
TE,ICFG=0x800,0x804
def st(t):
    print("%-14s fifo=%08x lane=%08x clk=%08x ctrl=%08x lanectrl=%08x intf_cfg=%08x"%(t,R(d,FIFO),R(d,LANE_ST),R(d,CLK_ST),R(d,CTRL),R(d,LANE_CTRL),R(i,ICFG)),flush=True)
def watch():
    W(d,FIFO,0xffffffff)
    for k in range(5): time.sleep(0.4); st("  +%.1fs"%(0.4*(k+1)))
mode=sys.argv[1]
st("before")
if mode=="prefetch_off":
    W(i,TE,0)                                   # INTF timing engine off
    W(i,ICFG,R(i,ICFG)&~(1<<31))                # prog fetch off
    c=R(d,CTRL); W(d,CTRL,c&~1); time.sleep(0.02)
    W(d,RESET,1); time.sleep(0.02); W(d,RESET,0)
    W(d,CTRL,c); time.sleep(0.02)
    W(i,TE,1)                                   # INTF on
elif mode=="hs_cycle":
    W(i,TE,0)
    c=R(d,CTRL); W(d,CTRL,c&~1)
    ck=R(d,CLK_CTRL); W(d,CLK_CTRL,ck|(1<<9))   # FORCE_ON_DYN_AHBM_HCLK (dynamic force-on)
    W(d,LANE_CTRL,R(d,LANE_CTRL)|(1<<24))
    W(d,RESET,1); time.sleep(0.02); W(d,RESET,0)
    W(d,CLK_CTRL,0x23f)
    W(d,CTRL,c); time.sleep(0.02)
    W(i,TE,1)
watch()
