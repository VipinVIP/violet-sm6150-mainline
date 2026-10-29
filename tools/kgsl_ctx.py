import os,fcntl,struct,time,sys
# create a draw context to force a real GPU power-up (IOCTL_KGSL_DRAWCTXT_CREATE = _IOWR(0x09,0x13,8))
fd=os.open("/dev/kgsl-3d0",os.O_RDWR)
req=(3<<30)|(8<<16)|(0x09<<8)|0x13
buf=bytearray(struct.pack("II",0,0))
try:
    fcntl.ioctl(fd,req,buf); print("ctx create ok",struct.unpack("II",bytes(buf)),flush=True)
except OSError as e:
    print("ctx create failed",e,flush=True)
time.sleep(float(sys.argv[1]) if len(sys.argv)>1 else 2)
