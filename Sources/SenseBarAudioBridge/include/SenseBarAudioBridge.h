#ifndef SENSEBAR_AUDIO_BRIDGE_H
#define SENSEBAR_AUDIO_BRIDGE_H

#include <CoreAudio/AudioHardware.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stddef.h>

/// Creates a private stereo process tap when the runtime supports it.
/// The returned UUID is retained; the caller owns it.
bool SBAudioCreateStereoProcessTap(
    const AudioObjectID * _Nonnull processes,
    size_t processCount,
    AudioObjectID * _Nonnull tapID,
    CFStringRef _Nullable * _Nonnull tapUUID
);

/// Destroys a process tap without adding a launch-time dependency on the API.
OSStatus SBAudioDestroyProcessTap(AudioObjectID tapID);

#endif
