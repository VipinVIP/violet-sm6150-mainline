import mmap,os,struct,sys
# usage: regdump.py out.txt ; dumps selected GPU-related ranges via /dev/mem (needs CONFIG_DEVMEM)
import sys
ALL={"rgmu_ctl":(0x507e000,0x800),"gmu_ao":(0x508ec00,0x400),"gpucc":(0x5090000,0x9000),"gcc_gpu":(0x171000,0x200),"smmu":(0x50a0000,0x100)}
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
