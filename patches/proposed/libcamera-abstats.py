import sys, glob
W,H=2112,1568
for f in sorted(glob.glob(sys.argv[1])):
    d=open(f,'rb').read()
    if len(d)<W*H*4: print(f,"short"); continue
    n=W*H
    r=d[0::4]; g=d[1::4]; b=d[2::4]
    mr=sum(r)/n; mg=sum(g)/n; mb=sum(b)/n
    clip=sum(1 for i in range(0,n,7) if d[4*i]>=255 and d[4*i+1]>=255 and d[4*i+2]>=255)
    tot=len(range(0,n,7))
    print("%s  mean %.0f  clip %.1f%%  R %.0f G %.0f B %.0f  G/R %.2f G/B %.2f"
          % (f.split('-')[-1], (mr+mg+mb)/3, 100*clip/tot, mr, mg, mb, mg/mr, mg/mb))
