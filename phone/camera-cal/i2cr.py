import fcntl, struct, ctypes, sys, os
I2C_RDWR=0x0707
class Msg(ctypes.Structure):
    _fields_=[('addr',ctypes.c_uint16),('flags',ctypes.c_uint16),('len',ctypes.c_uint16),('buf',ctypes.c_void_p)]
class Data(ctypes.Structure):
    _fields_=[('msgs',ctypes.POINTER(Msg)),('nmsgs',ctypes.c_uint32)]
def read(bus,addr,reg,n,w16):
    fd=os.open('/dev/i2c-%d'%bus,os.O_RDWR)
    rb=(ctypes.c_uint8*(2 if w16 else 1))(*( [reg>>8,reg&255] if w16 else [reg&255]))
    out=(ctypes.c_uint8*n)()
    m=(Msg*2)(Msg(addr,0,len(rb),ctypes.addressof(rb)),Msg(addr,1,n,ctypes.addressof(out)))
    d=Data(m,2)
    fcntl.ioctl(fd,I2C_RDWR,d)
    os.close(fd)
    return bytes(out)
if __name__=='__main__':
    bus=int(sys.argv[1]);addr=int(sys.argv[2],0);reg=int(sys.argv[3],0);n=int(sys.argv[4]);w16=int(sys.argv[5])
    try:
        b=read(bus,addr,reg,n,w16)
        print(b.hex(' '))
    except Exception as e:
        print('ERR',e)
