#!/bin/sh
# memstress.sh <nproc> <secs>: nproc python processes copying 48 MB buffers (memory bandwidth, no display)
N=$1; SEC=$2
for i in $(seq 1 $N); do
  (python3 -c "
import time
t=time.time(); a=bytearray(48<<20); b=bytearray(48<<20); n=0
while time.time()-t<$SEC:
    b[:]=a; n+=1
print('proc done copies',n,'=> %.1f GB/s' % (n*48/1024/$SEC))
" &) 
done
sleep $((SEC+3)); echo MEMSTRESS-FINISHED
