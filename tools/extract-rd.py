import struct,sys
f=open('/boot/boot.img','rb'); h=f.read(1648)
assert h[:8]==b'ANDROID!',h[:8]
ksize,kaddr,rsize,raddr,ssize,saddr,tags,page,hv=struct.unpack('<9I',h[8:44])
print('kernel',ksize,'ramdisk',rsize,'page',page,'hdr',hv)
def al(x): return (x+page-1)//page*page
roff=page+al(ksize)
f.seek(roff); rd=f.read(rsize)
open('/tmp/initramfs','wb').write(rd); print('wrote',len(rd), rd[:4].hex())
