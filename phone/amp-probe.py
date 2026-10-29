import fcntl, os, sys, time
fd = os.open('/dev/i2c-1', os.O_RDWR)
fcntl.ioctl(fd, 0x0706, 0x4c)
def rd(reg):
    os.write(fd, bytes([reg])); return os.read(fd, 1)[0]
def wr(reg, v): os.write(fd, bytes([reg, v]))
def dump(tag):
    wr(0x00, 0); wr(0x7f, 0)
    print(tag, 'PWR02=%02x' % rd(0x02), 'TDMdet0a=%02x' % rd(0x0a), 'INT_LIVE', ' '.join('%02x:%02x' % (r, rd(r)) for r in range(0x24, 0x2c)), 'INT_LAT', ' '.join('%02x:%02x' % (r, rd(r)) for r in range(0x2c, 0x34)), flush=True)
mode = sys.argv[1] if len(sys.argv) > 1 else 'mute'
dump('before')
if mode == 'mute':
    wr(0x00, 0); wr(0x7f, 0)
    wr(0x02, (rd(0x02) & ~3) | 1)   # MODE=1: active, muted
    time.sleep(0.3); dump('active-mute')
    wr(0x02, (rd(0x02) & ~3) | 2)   # back to shutdown
    time.sleep(0.2); dump('restored')
