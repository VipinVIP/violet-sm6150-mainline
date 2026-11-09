import time, sys, numpy as np, cv2
import vpipe as v
t=time.time(); fr=v.load(sys.argv[1], int(sys.argv[2])); print('load/unpack', round(time.time()-t,2))
t=time.time(); P=[v.planes(f) for f in fr]; print('planes', round(time.time()-t,2))
t=time.time(); x,_,_=v.merge(fr, log=lambda *a:None); print('merge', round(time.time()-t,2))
t=time.time(); out=v.develop(x, log=lambda *a:None); print('develop', round(time.time()-t,2))
t=time.time(); cv2.imwrite('/tmp/o.jpg', out, [cv2.IMWRITE_JPEG_QUALITY,92]); print('jpeg', round(time.time()-t,2))
