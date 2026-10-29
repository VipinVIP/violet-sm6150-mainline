import mmap,os,struct,sys
# usage: regdump.py out.txt ; dumps selected GPU-related ranges via /dev/mem (needs CONFIG_DEVMEM)
import sys
ALL={"dsi_ctrl":(0xae94000,0x400),"dsi_phy":(0xae94400,0x100),"dsi_lane":(0xae94500,0x300),"dsi_pll":(0xae94800,0x124)}
R=[(n,)+ALL[n] for n in sys.argv[2:]]
fd=os.open("/dev/mem",os.O_RDONLY|os.O_SYNC)
out=open(sys.argv[1],"w")
for name,base,size in R:
    page=base & ~0xfff; off=base-page
    try:
        m=mmap.mmap(fd,((off+size+0xfff)//0x1000)*0x1000,mmap.MAP_SHARED,mmap.PROT_READ,offset=page)
    except Exception as e:
        out.write("# %s map failed %s\n"%(name,e)); continue
    for o in range(0,size,4):
        out.write("%08x %08x %s\n"%(base+o,struct.unpack("<I",m[off+o:off+o+4])[0],name))
    out.flush()
