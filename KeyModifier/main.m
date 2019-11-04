//
//  main.m
//  KeyModifier
//
//  Created by 林 科俊 on 2019/10/31.
//  Copyright © 2019 Mid. All rights reserved.
//


//#import "keycode.h"
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "ModifyMaya.m"

#import <Carbon/Carbon.h>

bool isZDown = false;
bool isTabDown = false;
bool isScaling = false;

bool isDeleting = false;


bool modifyEnable = true;

int zStep = 0;

CGEventSourceRef eventSrc;

CGEventRef replacedEvent;
CFMachPortRef eventTap;

long long count = 0;

const int64_t kUserPost = 20;

void postKeyEvent(CGEventSourceRef src, CGKeyCode code, bool downOrUp, CGEventFlags flags) {
    CGEventRef event = CGEventCreateKeyboardEvent((CGEventSourceRef) src, code, downOrUp);
    CGEventSetFlags(event, flags);
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, kUserPost);
    CGEventPost(kCGHIDEventTap, event); //  option              return nil;
    CFRelease(event);
}

void postMouseEvent(CGEventSourceRef src, CGEventType type, CGPoint pt, CGMouseButton mb, CGEventFlags flags) {
    CGEventRef event = CGEventCreateMouseEvent((CGEventSourceRef) src, type, pt, mb);
    CGEventSetFlags(event, flags);
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, kUserPost);
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
}

// note: 触发的时候（一般是KeyDown)，才需要判断。
bool onlyHasTheseFlags(CGEventFlags flags, CGEventFlags validFlags) {
    // #uncertain: more flags ?
    uint64_t all = kCGEventFlagMaskAlternate |
            kCGEventFlagMaskCommand |
            kCGEventFlagMaskControl |
            kCGEventFlagMaskSecondaryFn |
            kCGEventFlagMaskShift |
            kCGEventFlagMaskAlphaShift;

    uint64_t has = flags & all;
    if (has == validFlags) {
        return true;
    } else {
        return false;
    }
}

void LogKeyStroke(CGEventTimestamp *pTimeStamp,
        uint *pType,
        long long *pKeycode,
        UniChar *pUc,
        UniCharCount *pUcc,
        CGEventFlags *pFlags,
        FILE *pLogFile) {
    fprintf(pLogFile, "{ \"time\":%llu, \"type\":%u, \"keycode\":%lld, ", *pTimeStamp, *pType, *pKeycode);
    if (pUc[0] != 0) {fprintf(pLogFile, "\"unichar\":0x%04x, ", pUc[0]);}
    if ((pUc[0] < 128) && (pUc[0] >= 41)) {fprintf(pLogFile, "\"ascii\":\"%c\", ", pUc[0]);}
    fprintf(pLogFile, "\"flags\":%llu },\n", *pFlags);

//    if (*pKeycode == 6) {
//        if (*pType == 10) {
//            NSLog(@"z down");
//            isZDown = true;
//        } else if (*pType == 11) {
//            NSLog(@"z up");
//            isZDown = false;
//        }
//    }
}

CGEventRef captureKeyStroke(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *pLogFile) {
    UniChar uc[10];
    UniCharCount ucc;


    // 在调试或者其他时候，在这个callback里如果走了太多时间，系统会停用这个callback，导致之后无法在进入
    // 这里在出现这种情况时，重新enable这个tap，避免失效
    if (type == kCGEventTapDisabledByTimeout) {
        /* Reset eventTap */
        CGEventTapEnable(eventTap, true);
        NSLog(@"time out");
        return NULL;
    }

    int64_t userData = CGEventGetIntegerValueField(event, kCGEventSourceUserData);

    // note: 这里调用 frontmostApplication 会leak，但是它被包在main的 autoreleasepool 里，不允许调用 release()
    // 只能再写个 autoreleasepool (autoreleasepool 可以嵌套)
    // why: c风格的回调函数里面，无法想用外层的 autoreleasepool 吗？
    @autoreleasepool {
        NSWorkspace *ws = NSWorkspace.sharedWorkspace;
        NSRunningApplication *frontmostApp = ws.frontmostApplication;
//        return event;
        if (frontmostApp) {
            bool inSpecialApp = [frontmostApp.bundleIdentifier containsString:@"com.autodesk.Maya"];
//        NSLog(@"frontmostApp's bundleIdentifier = %@", frontmostApp.bundleIdentifier);
            if (!inSpecialApp) {
                isScaling = false;
                isDeleting = false;
                // todo: 针对每个app，指定一个UserPostflag，屏蔽其他app产生的event;
                if (userData == kUserPost) {
                    return nil;
                }
                goto RET;
            }
        } else {
            goto RET;
        }
    }

    int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    CGEventFlags flags = CGEventGetFlags(event);

    // 自己post的消息会进入这个callback。
    // 检测标识位，如果时自己post的，那么直接发送出去。
    if (userData == kUserPost) {
        goto RET;
    }

    // cmd + ~ 开启或停用改键的开关
    if ((flags & kCGEventFlagMaskCommand) && (keycode == kVK_ANSI_Grave)) {
        if (type == kCGEventKeyDown) {
            modifyEnable = !modifyEnable;
            NSLog(@"modify enable = %d", modifyEnable);
            if (!modifyEnable) {
                isZDown = false;
                isTabDown = false;
                isScaling = false;
                isDeleting = false;
            }
        }
        return nil;
    }
    if (!modifyEnable) {
        goto RET;
    }

//    if (type == kCGEventLeftMouseUp) {
//        NSLog(@"left mouse up");
//    } else if (type == kCGEventRightMouseUp) {
//        NSLog(@"right mouse up");
////        return nil;
//    } else if (type == kCGEventOtherMouseDragged) {
//        NSLog(@"other mouse dragged, code=%d, flag=%d", keycode, flags);
//        for (int i = 1; i <= 13; i++) {
//            int64_t value = CGEventGetIntegerValueField(event, i);
//            NSLog(@"intergerValueField %d = %d", i, value);
//        }
//        NSLog(@"---------------");
//    }

//    if (type != kCGEventKeyDown) {
//        if (type != kCGEventKeyUp) {
//            if (type != kCGEventFlagsChanged) {
////                NSLog(@"xxx");
//                return event;
//            }
//        }
//    }


//    if ((flags & kCGEventFlagMaskAlternate) || (flags & kCGEventFlagMaskControl)) {
//        keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
//        flags = CGEventGetFlags(event);
//        type = CGEventGetType(event);
////        NSLog(@"final ---->> code = %d, type = %d, flag = %d", keycode, type, flags);
////        for (int i = 1; i <= 13; i++) {
////            int64_t value = CGEventGetIntegerValueField(event, i);
////            NSLog(@"intergerValueField %d = %d", i, value);
////        }
//        NSLog(@"---------------");
//        goto RET;
//    }

    CGEventTapLocation tapLoc = kCGHIDEventTap;
//    CGEventTapLocation tapLoc = kCGSessionEventTap;
//    CGEventSourceRef src = CGEventCreateSourceFromEvent(event);
//    CGEventSourceRef src = CGEventCreateSourceFromEvent(event);
//    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventSourceRef src = eventSrc;
//    src = nil;
// -----------------------------------------------------------------
    // cmd + 3 => del
    if (keycode == kVK_ANSI_3) {
        if (onlyHasTheseFlags(flags, kCGEventFlagMaskCommand)) {
            if (type == kCGEventKeyDown) {
                isDeleting = true;
                postKeyEvent(src, kVK_Delete, true, 0);
                return nil;
            }
        }
        if (isDeleting && type == kCGEventKeyUp) {
            isDeleting = false;
            postKeyEvent(src, kVK_Delete, false, 0);
            return nil;
        }
    }


// -----------------------------------------------------------------
    // 3 -> alt + mouse right
    if (keycode == kVK_ANSI_3) {
//        NSLog(@"code = %d, type = %d, flag = %d", keycode, type, flags);
        if ((flags & kCGEventFlagMaskAlternate) |
                (flags & kCGEventFlagMaskCommand) |
                (flags & kCGEventFlagMaskShift) |
                (flags & kCGEventFlagMaskControl) |
                (flags & kCGEventFlagMaskSecondaryFn)) {
            return event;
        }
//        CGEventSetFlags(event, flags | kCGEventFlagMaskAlternate);
//        if (type == kCGEventKeyDown) {
//            if (!isScaling) {
//                CGEventSetType(event, kCGEventRightMouseDown);
//                isScaling = true;
//            } else {
//                CGEventSetType(event, kCGEventRightMouseDragged);
//            }
//        } else if (type == kCGEventKeyUp) {
//            isScaling = false;
//            CGEventSetType(event, kCGEventRightMouseUp);
//        } else {
//            NSLog(@" !!! no reach !!!");
//        }
//        goto RET;
        if (type == kCGEventKeyDown) {
            if (!isScaling) {
                postKeyEvent(src, kVK_Option, true, kCGEventFlagMaskAlternate);
                postMouseEvent(src, kCGEventRightMouseDown, CGEventGetLocation(event), kCGMouseButtonRight, kCGEventFlagMaskAlternate);
                return nil;
            } else {
                postMouseEvent(src, kCGEventRightMouseDragged, CGEventGetLocation(event), kCGMouseButtonRight, kCGEventFlagMaskAlternate);
                return nil;
            }
        } else if (type == kCGEventKeyUp) {
            isScaling = false;
            postMouseEvent(src, kCGEventRightMouseUp, CGEventGetLocation(event), kCGMouseButtonRight, kCGEventFlagMaskAlternate);
            postKeyEvent(src, kVK_Option, false, 0);
            return nil;
        }

        if (isScaling) {
            // drag 和 move 对maya来说都可以
            postMouseEvent(src, kCGEventRightMouseDragged, CGEventGetLocation(event), kCGMouseButtonRight, kCGEventFlagMaskAlternate);
//        postMouseEvent(src, kCGEventMouseMoved, CGEventGetLocation(event), kCGMouseButtonRight, kCGEventFlagMaskAlternate);
            return nil;
            CGEventSetType(event, kCGEventMouseMoved);
            goto RET;
        }
    }

// -----------------------------------------------------------------

// -----------------------------------------------------------------
    // tab -> alt + mouse mid

    if (keycode == kVK_Tab) {
//        NSLog(@"code = %d, type = %d, flag = %d", keycode, type, flags);
        if ((flags & kCGEventFlagMaskAlternate) |
                (flags & kCGEventFlagMaskCommand) |
                (flags & kCGEventFlagMaskShift) |
                (flags & kCGEventFlagMaskControl) |
                (flags & kCGEventFlagMaskSecondaryFn)) {
            return event;
        }
//        CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, 0);
        // btn num alway -1

//        CGEventSetFlags(event, flags | kCGEventFlagMaskAlternate);
//        CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 2);
//        CGEventSetIntegerValueField(event, kCGMouseEventSubtype, 1);

        if (type == kCGEventKeyDown) {
            if (!isTabDown) {
                // 消息累加数，每次+1。无意义
//                CGEventSetIntegerValueField(event, kCGMouseEventNumber, 1);
                isTabDown = true;
//                CGEventSetType(event, kCGEventFlagsChanged);
//                CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, 58);
//                CGEventSetIntegerValueField(event, kCGMouseEventClickState, 1);


//                CGEventSourceRef eventSource = CGEventCreateSourceFromEvent(event);
                replacedEvent = CGEventCreateKeyboardEvent((CGEventSourceRef) src, (CGKeyCode) 58, true);
                CGEventSetFlags(replacedEvent, flags | kCGEventFlagMaskAlternate);
                CGEventSetIntegerValueField(replacedEvent, kCGEventSourceUserData, kUserPost);
                CGEventPost(tapLoc, replacedEvent); //  option              return nil;
                CFRelease(replacedEvent);

                replacedEvent = CGEventCreateMouseEvent((CGEventSourceRef) src, kCGEventOtherMouseDown, CGEventGetLocation(event), kCGMouseButtonCenter);
                CGEventSetFlags(replacedEvent, flags | kCGEventFlagMaskAlternate);
                CGEventSetIntegerValueField(replacedEvent, kCGEventSourceUserData, kUserPost);
                CGEventPost(tapLoc, replacedEvent); //                return nil;
                CFRelease(replacedEvent);
                return nil;
                goto RET;
            } else {
//                CGEventSetType(event, kCGEventOtherMouseDragged);
//                CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, 0);
//                CGEventSetIntegerValueField(event, kCGMouseEventClickState, 0);
//                CGEventTapPostEvent(nil, CGEventCreateMouseEvent((CGEventSourceRef) runLoopSource, kCGEventOtherMouseDragged, CGEventGetLocation(event), kCGMouseButtonCenter));
//                goto RET;
//                CGEventSourceRef eventSource = CGEventCreateSourceFromEvent(event);
                replacedEvent = CGEventCreateMouseEvent((CGEventSourceRef) src, NX_MOUSEMOVED, CGEventGetLocation(event), kCGMouseButtonCenter);
                CGEventSetFlags(replacedEvent, flags | kCGEventFlagMaskAlternate);
                CGEventSetIntegerValueField(replacedEvent, kCGEventSourceUserData, 20);
                CGEventPost(tapLoc, replacedEvent); //
                CFRelease(replacedEvent);
//                CFRelease(eventSource);
                return nil;
            }
        } else if (type == kCGEventKeyUp) {
            isTabDown = false;
//            CGEventSetIntegerValueField(event, kCGMouseEventNumber, 1);
//            CGEventSetType(event, kCGEventOtherMouseUp);
//            CGEventSetType(event, kCGEventFlagsChanged);
//            CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, 0);
//            CGEventSetIntegerValueField(event, kCGMouseEventClickState, 1);
//            CGEventSourceRef eventSource = CGEventCreateSourceFromEvent(event);
            replacedEvent = CGEventCreateMouseEvent((CGEventSourceRef) src, kCGEventOtherMouseUp, CGEventGetLocation(event), kCGMouseButtonCenter);
            CGEventSetFlags(replacedEvent, flags | kCGEventFlagMaskAlternate);
            CGEventSetIntegerValueField(replacedEvent, kCGEventSourceUserData, 20);
            CGEventPost(tapLoc, replacedEvent); //
            replacedEvent = CGEventCreateKeyboardEvent((CGEventSourceRef) src, (CGKeyCode) 58, false);
//            CGEventSetFlags(replacedEvent, flags);
            CGEventPost(tapLoc, replacedEvent);
            CFRelease(replacedEvent);
//            CGEventPost(kCGHIDEventTap, CGEventCreateKeyboardEvent((CGEventSourceRef) runLoopSource, (CGKeyCode) 58, false)); //  option              return nil;
//            CFRelease(eventSource);

            return nil;
            goto RET;
        } else {
            NSLog(@" !!! no reach !!!");
        }

    }

    if (isTabDown) {
//        CGEventSetType(event, kCGEventOtherMouseDragged);
//        CGEventSourceRef eventSource = CGEventCreateSourceFromEvent(event);
        replacedEvent = CGEventCreateMouseEvent((CGEventSourceRef) src, NX_MOUSEMOVED, CGEventGetLocation(event), kCGMouseButtonCenter);
        CGEventSetFlags(replacedEvent, flags | kCGEventFlagMaskAlternate);
        CGEventSetIntegerValueField(replacedEvent, kCGEventSourceUserData, 20);
        CGEventPost(tapLoc, replacedEvent);
        CFRelease(replacedEvent);
//        CFRelease(eventSource);
        return nil;

//        if (zStep == 0) {
////            CGEventPost(kCGHIDEventTap, CGEventCreateKeyboardEvent((CGEventSourceRef) runLoopSource, (CGKeyCode) 58, true)); //  option              return nil;
//            CGEventPost(kCGHIDEventTap, CGEventCreateMouseEvent((CGEventSourceRef) runLoopSource, kCGEventOtherMouseDown, CGEventGetLocation(event), kCGMouseButtonCenter)); //                return nil;
//            zStep = 1;
//            return nil;
//        } else {
//            CGEventSetType(event, kCGEventMouseMoved);
//            CGEventSetFlags(event, flags | kCGEventFlagMaskAlternate);
//            CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, 0);
//            goto RET;
//        }
//        CGEventSetIntegerValueField(event, kCGMouseEventClickState, 0);
//        CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, 2);
//        CGEventSetIntegerValueField(event, kCGMouseEventSubtype, 1);
//        CGEventTapPostEvent(nil, CGEventCreateMouseEvent(nil, kCGEventMouseMoved, CGEventGetLocation(event), kCGMouseButtonCenter));
//        return nil;
//        NSLog(@"kCGEventOtherMouseDragged code = %d, type = %d, flag = %d", keycode, type, flags);

    }
// -----------------------------------------------------------------



//    NSEvent *ev = [NSEvent eventWithCGEvent:event];
//    if ((flags & kCGEventFlagMaskShift) &&
//            (flags & kCGEventFlagMaskAlternate)
//            ) {
//        NSLog(@"modify flag : shift && alt");
//    } else if (flags & kCGEventFlagMaskAlternate) {
//        NSLog(@"modify flag : alt");
//    }


//    CGEventTimestamp timeStamp = CGEventGetTimestamp(event);

    CGEventKeyboardGetUnicodeString(event, 10, &ucc, uc);

//    LogKeyStroke(&timeStamp, &type, &keycode, uc, &ucc, &flags, pLogFile);
//    NSLog(@"key code: %lld,  event: %d", keycode, type);

    // todo: 以isZDown 为首判断,应该更清晰
    if (keycode == kVK_ANSI_Z) {
        if (type == NX_KEYDOWN) {
            if (isZDown) {
                // note: 使用这句，可以有线拖出来，但是效果比较卡，所以就用下一句没有线的
//            CGEventSetType(event, kCGEventMouseMoved);
//            CGEventSetType(event, kCGEventRightMouseDragged);


//            CGEventSetType(event, kCGEventRightMouseDown);

                replacedEvent = CGEventCreateMouseEvent((CGEventSourceRef) src, kCGEventRightMouseDragged, CGEventGetLocation(event), kCGMouseButtonRight);
//            CGEventSetFlags(replacedEvent, 0);
                CGEventSetIntegerValueField(replacedEvent, kCGEventSourceUserData, kUserPost);
                CGEventPost(tapLoc, replacedEvent); //
                CFRelease(replacedEvent);
                return nil;
//            CGEventSetType(event, kCGEventLeftMouseDragged);
                CGEventSetType(event, kCGEventLeftMouseDown);
//            CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, 0);
                goto RET;
            } else {
                if (onlyHasTheseFlags(flags, 0) ||
                        onlyHasTheseFlags(flags, kCGEventFlagMaskCommand) ||
                        onlyHasTheseFlags(flags, kCGEventFlagMaskShift) ||
                        onlyHasTheseFlags(flags, kCGEventFlagMaskCommand | kCGEventFlagMaskShift)
                        ) {
                    isZDown = true;

                    replacedEvent = CGEventCreateMouseEvent((CGEventSourceRef) src, kCGEventRightMouseDown, CGEventGetLocation(event), kCGMouseButtonRight);
//            NSLog(@"flag is %lld", flags);  // kCGEventFlagMaskNonCoalesced -> 0x100 -> 256
                    CGEventSetIntegerValueField(replacedEvent, kCGEventSourceUserData, kUserPost);
                    CGEventPost(tapLoc, replacedEvent); //
                    CFRelease(replacedEvent);
                    return nil;

                    CGEventSetType(event, kCGEventRightMouseDown);
                    goto RET;
//        NSLog(@"z down");

//        CGPoint point = CGEventGetLocation(event);
//        CGEventRef theEvent = CGEventCreateMouseEvent(NULL, kCGEventRightMouseDown, point, kCGMouseButtonRight);
                }
            }

        } else if (type == NX_KEYUP) {
//        NSLog(@"z up");
            if (isZDown) {
                isZDown = false;

                replacedEvent = CGEventCreateMouseEvent((CGEventSourceRef) src, kCGEventRightMouseUp, CGEventGetLocation(event), kCGMouseButtonRight);
//        CGEventSetFlags(replacedEvent, flags);
                CGEventSetIntegerValueField(replacedEvent, kCGEventSourceUserData, kUserPost);
                CGEventPost(tapLoc, replacedEvent); //
                CFRelease(replacedEvent);
                return nil;
            } else {
                goto RET;
            }
//            CGEventSetType(event, kCGEventRightMouseUp);
        }
    }

    if (isZDown) {
        replacedEvent = CGEventCreateMouseEvent((CGEventSourceRef) src, kCGEventRightMouseDragged, CGEventGetLocation(event), kCGMouseButtonRight);
//        CGEventSetFlags(replacedEvent, flags);
        CGEventSetIntegerValueField(replacedEvent, kCGEventSourceUserData, kUserPost);
        CGEventPost(tapLoc, replacedEvent); //
        CFRelease(replacedEvent);
        return nil;


//        CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, 0);
//        CGEventSetType(event, kCGEventMouseMoved);
        CGEventSetType(event, kCGEventRightMouseDragged);
//        CGEventSetType(event, kCGEventLeftMouseDragged);
        goto RET;
//        }
    }

    RET:
    count++;
//    NSLog(@"event finally is %u, count: %lld", CGEventGetType(event), count);
//    keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
//    flags = CGEventGetFlags(event);
//    type = CGEventGetType(event);
//    NSLog(@"final ---->> code = %d, type = %d, flag = %d", keycode, type, flags);
//    for (int i = 1; i <= 13; i++) {
//        int64_t value = CGEventGetIntegerValueField(event, i);
//        NSLog(@"intergerValueField %d = %d", i, value);
//    }
//    NSLog(@"---------------");
    return event;
}

void ensureAccessibility() {
    NSDictionary *options;
    options = @{(__bridge id) kAXTrustedCheckOptionPrompt: @NO};
    BOOL accessibilityEnabled = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef) options);
    if (!accessibilityEnabled) {
        NSString *urlString = @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility";
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlString]];
    }
}

void enableAccessibility() {
    NSString *script = @"tell application \"System Preferences\" \n reveal anchor \"Privacy\" of pane id \"com.apple.preference.security\" \n activate \n end tell";

    NSAppleScript *scriptObject = [[NSAppleScript alloc] initWithSource:script];
    [scriptObject executeAndReturnError:nil];
}

void createKeyEventListener(FILE *pLogFile) {
    int mask = CGEventMaskBit(kCGEventFlagsChanged) |
            CGEventMaskBit(kCGEventLeftMouseDown) |
            CGEventMaskBit(kCGEventLeftMouseUp) |
            CGEventMaskBit(kCGEventRightMouseDown) |
            CGEventMaskBit(kCGEventRightMouseUp) |
            CGEventMaskBit(kCGEventMouseMoved) |
            CGEventMaskBit(kCGEventLeftMouseDragged) |
            CGEventMaskBit(kCGEventRightMouseDragged) |
//            CGEventMaskBit(kCGEventScrollWheel) |
            CGEventMaskBit(kCGEventOtherMouseDown) |
            CGEventMaskBit(kCGEventOtherMouseUp) |
            CGEventMaskBit(kCGEventOtherMouseDragged) |
            CGEventMaskBit(kCGEventKeyDown) |
            CGEventMaskBit(kCGEventKeyUp);

    eventTap = CGEventTapCreate(kCGHIDEventTap,
            kCGHeadInsertEventTap,
            kCGEventTapOptionDefault,
//            kCGEventMaskForAllEvents,
            mask,
            captureKeyStroke,
            (void *) pLogFile);

    CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);

    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CFRelease(runLoopSource);

    CGEventTapEnable(eventTap, true);
    CFRelease(eventTap);

    eventSrc = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);

    CFRunLoopRun();

    CFRelease(eventSrc);
}

FILE *openLogFile(char *pLogFilename) {
    if (strcmp(pLogFilename, "stdout") == 0) {
        return stdout;
    }

    return fopen(pLogFilename, "a");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        ensureAccessibility();
        FILE *pLogFile = openLogFile("stdout");
        createKeyEventListener(pLogFile);
    }
    return 0;
}
