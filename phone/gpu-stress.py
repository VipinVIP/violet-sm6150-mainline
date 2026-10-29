import ctypes as C, os, sys, time
os.environ.setdefault("EGL_PLATFORM","surfaceless")
secs=float(sys.argv[1]) if len(sys.argv)>1 else 20
iters=int(sys.argv[2]) if len(sys.argv)>2 else 64   # shader loop count = load
W,H=1080,1920
egl=C.CDLL("libEGL.so.1"); gl=C.CDLL("libGLESv2.so.2")
egl.eglGetDisplay.restype=C.c_void_p; egl.eglGetDisplay.argtypes=[C.c_void_p]
egl.eglInitialize.argtypes=[C.c_void_p,C.POINTER(C.c_int),C.POINTER(C.c_int)]
egl.eglChooseConfig.argtypes=[C.c_void_p,C.POINTER(C.c_int),C.POINTER(C.c_void_p),C.c_int,C.POINTER(C.c_int)]
egl.eglCreateContext.restype=C.c_void_p; egl.eglCreateContext.argtypes=[C.c_void_p,C.c_void_p,C.c_void_p,C.POINTER(C.c_int)]
egl.eglMakeCurrent.argtypes=[C.c_void_p,C.c_void_p,C.c_void_p,C.c_void_p]
gl.glCreateShader.restype=C.c_uint; gl.glCreateProgram.restype=C.c_uint
gl.glGetString.restype=C.c_char_p
d=egl.eglGetDisplay(None); a=C.c_int(); b=C.c_int(); egl.eglInitialize(d,C.byref(a),C.byref(b)); egl.eglBindAPI(0x30A0)
cfg=C.c_void_p(); n=C.c_int()
egl.eglChooseConfig(d,(C.c_int*5)(0x3040,4,0x3033,0,0x3038),C.byref(cfg),1,C.byref(n))
ctx=egl.eglCreateContext(d,cfg,None,(C.c_int*3)(0x3098,2,0x3038)); egl.eglMakeCurrent(d,None,None,ctx)
print(gl.glGetString(0x1F01),gl.glGetString(0x1F02),flush=True)
def sh(t,src):
    s=gl.glCreateShader(t); p=C.c_char_p(src.encode()); gl.glShaderSource(s,1,C.byref(p),None); gl.glCompileShader(s); return s
vs=sh(0x8B31,"attribute vec2 p; void main(){gl_Position=vec4(p,0.,1.);}")
fs=sh(0x8B30,"precision highp float; uniform float t; void main(){vec2 u=gl_FragCoord.xy/1000.; float a=0.;"
  "for(int i=0;i<%d;i++){a+=sin(u.x*float(i)+t)*cos(u.y*float(i)-t); u=u.yx*1.01+a*0.001;} gl_FragColor=vec4(fract(a),fract(u.x),fract(u.y),1.);}"%iters)
pr=gl.glCreateProgram(); gl.glAttachShader(pr,vs); gl.glAttachShader(pr,fs); gl.glBindAttribLocation(pr,0,b"p"); gl.glLinkProgram(pr); gl.glUseProgram(pr)
tex=C.c_uint(); fbo=C.c_uint()
gl.glGenTextures(1,C.byref(tex)); gl.glBindTexture(0x0DE1,tex); gl.glTexImage2D(0x0DE1,0,0x1908,W,H,0,0x1908,0x1401,None)
gl.glGenFramebuffers(1,C.byref(fbo)); gl.glBindFramebuffer(0x8D40,fbo); gl.glFramebufferTexture2D(0x8D40,0x8CE0,0x0DE1,tex,0)
gl.glViewport(0,0,W,H)
quad=(C.c_float*8)(-1,-1,1,-1,-1,1,1,1)
gl.glEnableVertexAttribArray(0); gl.glVertexAttribPointer(0,2,0x1406,0,0,quad)
loc=gl.glGetUniformLocation(pr,b"t"); gl.glUniform1f.argtypes=[C.c_int,C.c_float]
t0=time.time(); f=0
while time.time()-t0<secs:
    gl.glUniform1f(loc,f*0.01); gl.glDrawArrays(0x0005,0,4); gl.glFinish(); f+=1
    if f%30==0: print("t=%.1f frames=%d err=%x"%(time.time()-t0,f,gl.glGetError()),flush=True)
print("done frames",f,"fps %.1f"%(f/(time.time()-t0)),flush=True)
