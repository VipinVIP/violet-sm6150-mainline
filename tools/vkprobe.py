import ctypes as C,sys
vk=C.CDLL("libvulkan.so.1")
class AppInfo(C.Structure):
    _fields_=[("sType",C.c_int),("pNext",C.c_void_p),("pApplicationName",C.c_char_p),("applicationVersion",C.c_uint),
              ("pEngineName",C.c_char_p),("engineVersion",C.c_uint),("apiVersion",C.c_uint)]
class InstInfo(C.Structure):
    _fields_=[("sType",C.c_int),("pNext",C.c_void_p),("flags",C.c_uint),("pApplicationInfo",C.POINTER(AppInfo)),
              ("enabledLayerCount",C.c_uint),("ppEnabledLayerNames",C.c_void_p),("enabledExtensionCount",C.c_uint),("ppEnabledExtensionNames",C.c_void_p)]
app=AppInfo(0,None,b"probe",1,b"probe",1,(1<<22)|(1<<12))
ci=InstInfo(1,None,0,C.pointer(app),0,None,0,None)
inst=C.c_void_p()
r=vk.vkCreateInstance(C.byref(ci),None,C.byref(inst)); print("vkCreateInstance",r)
n=C.c_uint(0); r=vk.vkEnumeratePhysicalDevices(inst,C.byref(n),None); print("enumerate rc",r,"count",n.value)
devs=(C.c_void_p*max(n.value,1))()
vk.vkEnumeratePhysicalDevices(inst,C.byref(n),devs)
for i in range(n.value):
    buf=C.create_string_buffer(2048)
    vk.vkGetPhysicalDeviceProperties(C.c_void_p(devs[i]),buf)
    raw=buf.raw
    api,drv,ven,dev,typ=[int.from_bytes(raw[k:k+4],"little") for k in range(0,20,4)]
    name=raw[20:276].split(b"\0")[0].decode()
    print("device",i,name,"vendor %04x device %04x type %d api %d.%d.%d"%(ven,dev,typ,api>>22,(api>>12)&0x3ff,api&0xfff))
