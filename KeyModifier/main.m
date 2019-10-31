//
//  main.m
//  KeyModifier
//
//  Created by 林 科俊 on 2019/10/31.
//  Copyright © 2019 Mid. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

bool isZDown = false;
bool lastInMaya = false;


long long count = 0;

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
    CGEventFlags flags;

//    if (type == kCGEventLeftMouseUp) {
//        NSLog(@"left mouse up");
//    } else if (type == kCGEventRightMouseUp) {
//        if (isZDown) {
//            NSLog(@"z down, intersect right mouse up");
//            return nil;
//        }
//        NSLog(@"right mouse up");
////        return nil;
//    }

//    if (type != kCGEventKeyDown) {
//        if (type != kCGEventKeyUp) {
//            if (type != kCGEventFlagsChanged) {
////                NSLog(@"xxx");
//                return event;
//            }
//        }
//    }
    
    NSRunningApplication *frontmostApp = [NSWorkspace sharedWorkspace].frontmostApplication;
    if (frontmostApp) {
//        NSLog(@"frontmostApp's bundleIdentifier = %@", frontmostApp.bundleIdentifier);
        if (![frontmostApp.bundleIdentifier containsString: @"com.autodesk.Maya"])
            goto RET;
    }

    CGEventTimestamp timeStamp = CGEventGetTimestamp(event);
    long long keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

    CGEventKeyboardGetUnicodeString(event, 10, &ucc, uc);
    flags = CGEventGetFlags(event);

//    LogKeyStroke(&timeStamp, &type, &keycode, uc, &ucc, &flags, pLogFile);

//    NSLog(@"key code: %lld,  event: %d", keycode, type);

    if (keycode == 6 && type == NX_KEYDOWN) {
        if (isZDown) {
            // note: 使用这句，可以有线拖出来，但是效果比较卡，所以就用下一句没有线的
//            CGEventSetType(event, kCGEventRightMouseDragged);
            CGEventSetType(event, kCGEventRightMouseDown);
            goto RET;
        }
//        NSLog(@"z down");

//        CGPoint point = CGEventGetLocation(event);
//        CGEventRef theEvent = CGEventCreateMouseEvent(NULL, kCGEventRightMouseDown, point, kCGMouseButtonRight);
        isZDown = true;
        CGEventSetType(event, kCGEventRightMouseDown);
        goto RET;
    } else if (keycode == 6 && type == NX_KEYUP) {
//        NSLog(@"z up");
        isZDown = false;
        CGEventSetType(event, kCGEventRightMouseUp);
        goto RET;
    }

//    if (type == kCGEventRightMouseDown) {
//        NSLog(@"r mouse down");
//        isRightMouseDown = true;
//    } else if (type == kCGEventRightMouseUp) {
//        NSLog(@"r mouse up");
////        CGEventSetType(event, kCGEventNull);
////        return event;
//        isRightMouseDown = false;
//    }

//    if (isRightMouseDown) {
//        NSLog(@"right mouse downing %d", type);
//    }
//    if (isZDown) {
//        if (type == kCGEventMouseMoved) {
//            return nil;
//        } else if (type == kCGEventLeftMouseDown) {
//            CGEventSetType(event, kCGEventMouseMoved);
//            return event;
//        }
//    }

    if (isZDown) {
//        if (type == kCGEventMouseMoved) {
//            CGEventSetType(event, kCGEventRightMouseDragged);
//            return event;
//        } else {
        CGEventSetType(event, kCGEventRightMouseDragged);
        goto RET;
//        }
    }

    RET:
    count++;
//    NSLog(@"event finally is %u, count: %lld", CGEventGetType(event), count);
    return event;
}

void createKeyEventListener(FILE *pLogFile) {
    auto mask = CGEventMaskBit(kCGEventFlagsChanged) |
            CGEventMaskBit(kCGEventLeftMouseDown) |
            CGEventMaskBit(kCGEventLeftMouseUp) |
            CGEventMaskBit(kCGEventRightMouseDown) |
            CGEventMaskBit(kCGEventRightMouseUp) |
            CGEventMaskBit(kCGEventMouseMoved) |
            CGEventMaskBit(kCGEventLeftMouseDragged) |
            CGEventMaskBit(kCGEventRightMouseDragged) |
//            CGEventMaskBit(kCGEventScrollWheel) |
//            CGEventMaskBit(kCGEventOtherMouseDown) |
//            CGEventMaskBit(kCGEventOtherMouseUp) |
            CGEventMaskBit(kCGEventOtherMouseDragged) |
            CGEventMaskBit(kCGEventKeyDown) |
            CGEventMaskBit(kCGEventKeyUp);

    CFMachPortRef eventTap = CGEventTapCreate(kCGHIDEventTap,
            kCGHeadInsertEventTap,
            kCGEventTapOptionDefault,
//            kCGEventMaskForAllEvents,
            mask,
            captureKeyStroke,
            (void *) pLogFile);

    CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);

    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);
    CFRelease(runLoopSource);

    CFRunLoopRun();
}

FILE *openLogFile(char *pLogFilename) {
    if (strcmp(pLogFilename, "stdout") == 0) {
        return stdout;
    }

    return fopen(pLogFilename, "a");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        FILE *pLogFile = openLogFile("stdout");
        createKeyEventListener(pLogFile);
    }
    return 0;
}

