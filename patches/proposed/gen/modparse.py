import struct,sys,json
def parse(path):
    d=open(path,'rb').read()
    n=len(d)//8
    q=struct.unpack('<%dQ'%n,d[:n*8])
    def rec(i):
        return (i+10<=n and q[i+1]==0 and q[i+2]==q[i]+1 and q[i+4]==1 and q[i+5]==q[i]+2 and q[i+7]==1 and q[i+9]==1 and q[i+3]<0x10000)
    i=0;runs=[]
    while i<n-10:
        if rec(i):
            s=i
            while i<n-10 and rec(i): i+=10
            runs.append((s,(i-s)//10))
        else: i+=1
    out=[]
    for s,c in runs:
        # include a preceding record if ids are consecutive (id_prev+3 == id_first)
        st=s
        if s>=10 and q[s-10+4]==1 and q[s-10+5]==q[s-10+2]+1 and q[s-10+3]<0x10000 and q[s-10+7]==1:
            st=s-10
        regs=[q[st+10*k+3] for k in range(c+(s-st)//10)]
        e=st+10*len(regs)
        vals=[q[e+1+2*k] for k in range(len(regs))]
        out.append(dict(off=st*8,hdr=[q[st-8+j] for j in range(8)] if st>=8 else [],regs=regs,vals=vals,type=q[st+6]))
    return out
if __name__=='__main__':
    for r in parse(sys.argv[1]):
        print(hex(r['off']),len(r['regs']),'type',r['type'],'hdr',[hex(x) for x in r['hdr']])
        print('   ',[(hex(a),hex(b)) for a,b in list(zip(r['regs'],r['vals']))[:10]])
