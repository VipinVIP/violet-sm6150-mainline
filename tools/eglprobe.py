import ctypes as C,os
os.environ.setdefault("EGL_PLATFORM","surfaceless")
egl=C.CDLL("libEGL.so.1"); gl=C.CDLL("libGLESv2.so.2")
egl.eglGetDisplay.restype=C.c_void_p; egl.eglGetDisplay.argtypes=[C.c_void_p]
egl.eglInitialize.argtypes=[C.c_void_p,C.POINTER(C.c_int),C.POINTER(C.c_int)]
egl.eglBindAPI.argtypes=[C.c_uint]
egl.eglChooseConfig.argtypes=[C.c_void_p,C.POINTER(C.c_int),C.POINTER(C.c_void_p),C.c_int,C.POINTER(C.c_int)]
egl.eglCreateContext.restype=C.c_void_p; egl.eglCreateContext.argtypes=[C.c_void_p,C.c_void_p,C.c_void_p,C.POINTER(C.c_int)]
egl.eglMakeCurrent.argtypes=[C.c_void_p,C.c_void_p,C.c_void_p,C.c_void_p]
gl.glGetString.restype=C.c_char_p
d=egl.eglGetDisplay(None); mj=C.c_int(); mn=C.c_int()
print("init",egl.eglInitialize(d,C.byref(mj),C.byref(mn)),mj.value,mn.value,flush=True)
egl.eglBindAPI(0x30A0)
attr=(C.c_int*5)(0x3040,4,0x3033,0,0x3038)  # RENDERABLE_TYPE=ES2, SURFACE_TYPE=0 (surfaceless), NONE
cfg=C.c_void_p(); n=C.c_int()
print("choose",egl.eglChooseConfig(d,attr,C.byref(cfg),1,C.byref(n)),n.value,flush=True)
ca=(C.c_int*3)(0x3098,2,0x3038)
ctx=egl.eglCreateContext(d,cfg,None,ca); print("ctx",bool(ctx),flush=True)
print("makecurrent",egl.eglMakeCurrent(d,None,None,ctx),flush=True)
for e in (0x1F00,0x1F01,0x1F02): print(gl.glGetString(e),flush=True)
fbo=C.c_uint(); tex=C.c_uint()
gl.glGenTextures(1,C.byref(tex)); gl.glBindTexture(0x0DE1,tex)
gl.glTexImage2D(0x0DE1,0,0x1908,64,64,0,0x1908,0x1401,None)
gl.glGenFramebuffers(1,C.byref(fbo)); gl.glBindFramebuffer(0x8D40,fbo)
gl.glFramebufferTexture2D(0x8D40,0x8CE0,0x0DE1,tex,0)
print("fbo status %x"%gl.glCheckFramebufferStatus(0x8D40),flush=True)
gl.glClearColor(C.c_float(0.25),C.c_float(0.5),C.c_float(0.75),C.c_float(1.0)) if False else None
gl.glClearColor.argtypes=[C.c_float]*4
gl.glClearColor(0.25,0.5,0.75,1.0); gl.glClear(0x4000)
buf=C.create_string_buffer(4)
gl.glReadPixels(0,0,1,1,0x1908,0x1401,buf)
print("pixel",list(buf.raw),"err %x"%gl.glGetError(),flush=True)
