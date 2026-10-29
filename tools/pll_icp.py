import mmap,os,struct,sys
# sets DSI0 PLL ICP_SET (0xae948fc) and FRAC_START1/2 to r10's values
fd=os.open("/dev/mem",os.O_RDWR|os.O_SYNC)
m=mmap.mmap(fd,0x1000,mmap.MAP_SHARED,mmap.PROT_READ|mmap.PROT_WRITE,offset=0xae94000)
rd=lambda o: struct.unpack("<I",m[o:o+4])[0]
def wr(o,v): m[o:o+4]=struct.pack("<I",v)
print("before icp=%02x frac1=%02x frac2=%02x"%(rd(0x8fc),rd(0x8b4),rd(0x8b8)))
wr(0x8fc,0x3f)
if "frac" in sys.argv: wr(0x8b4,0xa3); wr(0x8b8,0x92)
print("after  icp=%02x frac1=%02x frac2=%02x"%(rd(0x8fc),rd(0x8b4),rd(0x8b8)))
