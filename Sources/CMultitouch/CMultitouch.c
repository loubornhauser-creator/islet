#include "CMultitouch.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint pos, vel; } MTReadout;
typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int unknown1;
    int unknown2;
    MTReadout normalized;
    float size;
    int unknown3;
    float angle;
    float majorAxis;
    float minorAxis;
    MTReadout unknown4;
    int unknown5[2];
    float unknown6;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallback)(MTDeviceRef, MTTouch *, int, double, int);
typedef CFArrayRef (*MTDeviceCreateListFn)(void);
typedef void (*MTRegisterFn)(MTDeviceRef, MTContactCallback);
typedef int (*MTStartFn)(MTDeviceRef, int);
typedef void (*MTStopFn)(MTDeviceRef);

static cmt_callback g_cb = NULL;
static CFArrayRef g_devices = NULL;
static void *g_lib = NULL;
static MTRegisterFn g_unregister = NULL;
static MTStopFn g_stop = NULL;

static int contact(MTDeviceRef dev, MTTouch *t, int n, double ts, int frame) {
    (void)dev; (void)ts; (void)frame;
    if (g_cb) {
        if (n > 0 && t) g_cb(n, t[0].normalized.pos.x, t[0].normalized.pos.y);
        else g_cb(0, 0, 0);
    }
    return 0;
}

bool cmt_start(cmt_callback callback) {
    if (g_devices) return true;
    g_lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY);
    if (!g_lib) return false;
    MTDeviceCreateListFn create = (MTDeviceCreateListFn)dlsym(g_lib, "MTDeviceCreateList");
    MTRegisterFn reg = (MTRegisterFn)dlsym(g_lib, "MTRegisterContactFrameCallback");
    MTStartFn start = (MTStartFn)dlsym(g_lib, "MTDeviceStart");
    g_unregister = (MTRegisterFn)dlsym(g_lib, "MTUnregisterContactFrameCallback");
    g_stop = (MTStopFn)dlsym(g_lib, "MTDeviceStop");
    if (!create || !reg || !start) return false;
    g_cb = callback;
    g_devices = create();
    if (!g_devices) return false;
    CFIndex count = CFArrayGetCount(g_devices);
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef d = (MTDeviceRef)CFArrayGetValueAtIndex(g_devices, i);
        reg(d, contact);
        start(d, 0);
    }
    return count > 0;
}

void cmt_stop(void) {
    if (!g_devices) return;
    CFIndex count = CFArrayGetCount(g_devices);
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef d = (MTDeviceRef)CFArrayGetValueAtIndex(g_devices, i);
        if (g_unregister) g_unregister(d, contact);
        if (g_stop) g_stop(d);
    }
    CFRelease(g_devices);
    g_devices = NULL;
    g_cb = NULL;
}
