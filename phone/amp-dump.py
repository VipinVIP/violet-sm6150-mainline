import fcntl, os, sys, time
fd = os.open('/dev/i2c-1', os.O_RDWR)
fcntl.ioctl(fd, 0x0706, 0x4c)   # I2C_SLAVE_FORCE
def rd(reg):
    os.write(fd, bytes([reg])); return os.read(fd, 1)[0]
def wr(reg, v): os.write(fd, bytes([reg, v]))
wr(0x00, 0); wr(0x7f, 0)
print(' '.join('%02x:%02x' % (r, rd(r)) for r in range(0x01, 0x40)))
