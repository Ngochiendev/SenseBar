#import "include/SenseBarAudioBridge.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

typedef OSStatus (*SBCreateTapFunction)(id, AudioObjectID *);
typedef OSStatus (*SBDestroyTapFunction)(AudioObjectID);

bool SBAudioCreateStereoProcessTap(
    const AudioObjectID *processes,
    size_t processCount,
    AudioObjectID *tapID,
    CFStringRef *tapUUID
) {
    if (!processes || processCount == 0 || !tapID || !tapUUID) return false;

    Class tapClass = NSClassFromString(@"CATapDescription");
    SBCreateTapFunction createTap = (SBCreateTapFunction)dlsym(
        RTLD_DEFAULT,
        "AudioHardwareCreateProcessTap"
    );
    if (!tapClass || !createTap) return false;

    NSMutableArray<NSNumber *> *objectIDs = [NSMutableArray arrayWithCapacity:processCount];
    for (size_t index = 0; index < processCount; index++) {
        [objectIDs addObject:@(processes[index])];
    }

    id description = ((id (*)(id, SEL))objc_msgSend)(tapClass, sel_registerName("alloc"));
    description = ((id (*)(id, SEL, id))objc_msgSend)(
        description,
        sel_registerName("initStereoMixdownOfProcesses:"),
        objectIDs
    );
    if (!description) return false;

    ((void (*)(id, SEL, BOOL))objc_msgSend)(
        description,
        sel_registerName("setPrivate:"),
        YES
    );
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(
        description,
        sel_registerName("setMuteBehavior:"),
        2
    );

    NSUUID *uuid = ((id (*)(id, SEL))objc_msgSend)(
        description,
        sel_registerName("UUID")
    );
    AudioObjectID createdTap = kAudioObjectUnknown;
    if (!uuid || createTap(description, &createdTap) != noErr || createdTap == kAudioObjectUnknown) {
        return false;
    }

    *tapID = createdTap;
    *tapUUID = CFBridgingRetain(uuid.UUIDString);
    return true;
}

OSStatus SBAudioDestroyProcessTap(AudioObjectID tapID) {
    SBDestroyTapFunction destroyTap = (SBDestroyTapFunction)dlsym(
        RTLD_DEFAULT,
        "AudioHardwareDestroyProcessTap"
    );
    return destroyTap ? destroyTap(tapID) : kAudioHardwareUnsupportedOperationError;
}
