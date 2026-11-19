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

typedef struct SBAudioEqualizer SBAudioEqualizer;
SBAudioEqualizer * _Nullable SBAudioEqualizerCreate(double rate, float gain, const float * _Nullable bands, bool enabled);
void SBAudioEqualizerDestroy(SBAudioEqualizer * _Nonnull equalizer);
/// Publish from one serialized control thread, never from the render callback.
void SBAudioEqualizerPublish(SBAudioEqualizer * _Nonnull equalizer, float gain, const float * _Nullable bands, bool enabled);
void SBAudioEqualizerPrepare(SBAudioEqualizer * _Nonnull equalizer, float gain, const float * _Nullable bands, bool enabled);
void SBAudioEqualizerRender(SBAudioEqualizer * _Nonnull equalizer, const AudioBufferList * _Nonnull input, AudioBufferList * _Nonnull output, unsigned channels);
/// Control-thread curve preview at the supplied sample rate; returns headroom dB.
float SBAudioEqualizerCurve(double rate, const float * _Nonnull bands, float * _Nonnull response, unsigned count);

#endif
