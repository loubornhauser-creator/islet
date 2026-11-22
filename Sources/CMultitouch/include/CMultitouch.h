#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <stdbool.h>

/// Called on a private multitouch thread (~100 Hz while fingers touch the trackpad).
/// x/y are normalized (0...1) positions of the first finger, y = 0 is the bottom edge.
typedef void (*cmt_callback)(int fingers, float x, float y);

/// Loads MultitouchSupport at runtime (no link-time dependency on a private framework).
bool cmt_start(cmt_callback callback);
void cmt_stop(void);

#endif
