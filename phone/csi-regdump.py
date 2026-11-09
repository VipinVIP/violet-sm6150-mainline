import mmap,os,struct,sys
fd=os.open('/dev/mem',os.O_RDONLY|os.O_SYNC)
def dump(name,base,length,step=4):
    m=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ,offset=base)
    out=[]
    for o in range(0,length,step):
        v=struct.unpack_from('<I',m,o)[0]
        out.append((o,v))
    print('==',name,hex(base))
    for o,v in out:
        if v: print('  %03x=%08x'%(o,v))
for n,b,l in (('csiphy0',0xac65000,0x1000),('csid0',0xacb3000,0x400)):
    try: dump(n,b,l)
    except Exception as e: print(n,'ERR',e)
