import sys
sys.path.insert(0,'/var/tmp')
import i2cr
for addr in (0x50,0x51):
    out=bytearray()
    bad=0
    for off in range(0,0x4000,8):
        try: out+=i2cr.read(3,addr,off,8,1)
        except Exception: out+=b'\xee'*8; bad+=1
        if bad>8 and len(out)<64: break
    open('/var/tmp/eep%x.bin'%addr,'wb').write(out)
    print(hex(addr),len(out),'bad',bad)
