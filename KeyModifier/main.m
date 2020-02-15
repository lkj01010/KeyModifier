//
//  main.m
//  KeyModifier
//
//  Created by 林 科俊 on 2019/10/31.
//  Copyright © 2019 Mid. All rights reserved.
//

/// !note: 好像改键的整个api可以替换成最新的 `addGlobalMonitorForEvents`

//#import "keycode.h"
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "ModifyMaya.m"

#import <Carbon/Carbon.h>

#import <objc/runtime.h>


enum App {
    None,
    App_Maya_Or_FbxReview,
    App_QQ,
    App_Xcode,
    App_Preview,
    App_Chrome,
    App_Terminal,
    App_Goland,
    App_Rider,
    App_PyCharm,
    App_Photoshop,
    App_ClipStudioPaint,
};

NSDictionary *wheelSensitivity;


enum App lastApp = None;
enum App curApp = None;

bool isZDown = false;
bool isTabDown = false;
bool isScaling = false;
bool isDeleting = false;
bool modifyEnable = true;

bool xcode_Tab = false;
bool xcode_ShiftTab = false;

bool ps_fill = false;
bool ps_clean = false;
bool ps_layerAdd = false;
bool ps_layerRemove = false;
bool ps_scaleBrush = false;
bool ps_cmdTab = false;
// 数字键和功能键交换
bool ps_nums[10] = {false, false, false, false, false,
    false, false, false, false, false};

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

void postKeyEventNoFlags(CGEventSourceRef src, CGKeyCode code, bool downOrUp) {
    CGEventRef event = CGEventCreateKeyboardEvent((CGEventSourceRef) src, code, downOrUp);
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, kUserPost);
    CGEventPost(kCGHIDEventTap, event); //  option              return nil;
    CFRelease(event);
}

void postScrollWheelEvent(CGEventSourceRef src, int32_t wheelCount, int32_t delta, CGEventFlags flags) {
    CGEventRef event = CGEventCreateScrollWheelEvent((CGEventSourceRef) src, kCGScrollEventUnitPixel, wheelCount, delta);
    CGEventSetFlags(event, flags);
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, kUserPost);
    CGEventPost(kCGHIDEventTap, event);
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
bool matchFlags(CGEventFlags flags, CGEventFlags validFlags) {
    // #uncertain: more flags ?
    uint64_t all = kCGEventFlagMaskAlternate |
    kCGEventFlagMaskCommand |
    kCGEventFlagMaskControl |
    kCGEventFlagMaskShift |
    kCGEventFlagMaskAlphaShift;

    uint64_t has = flags & all;
    if (has == validFlags) {
        return true;
    } else {
        return false;
    }
}

bool hasFlags(CGEventFlags flags, CGEventFlags validFlags) {
    // #uncertain: more flags ?
    uint64_t all = kCGEventFlagMaskAlternate |
    kCGEventFlagMaskCommand |
    kCGEventFlagMaskControl |
    kCGEventFlagMaskShift |
    kCGEventFlagMaskAlphaShift;

    uint64_t has = flags & all;
    if ((has & validFlags) == has) {
        return true;
    } else {
        return false;
    }
}

bool modifyKey(CGEventSourceRef src, int64_t keycode, CGEventType type, CGEventFlags flags,
               int64_t fromKey, CGEventFlags fromFlags, bool *var,
               int64_t toKey, CGEventFlags toFlags) {
    if (keycode == fromKey) {
        if (matchFlags(flags, fromFlags)) {
            if (type == kCGEventKeyDown) {
                *var = true;
                postKeyEvent(src, toKey, true, toFlags);
                return true;
            }
        }
        if (*var && type == kCGEventKeyUp) {
            *var = false;
            postKeyEvent(src, toKey, false, toFlags);
            return true;
        }
    }

    return false;
}

bool exchangeKey(CGEventSourceRef src, int64_t keycode, CGEventType type, CGEventFlags flags,
                int64_t fromKey, bool *var, int64_t toKey, CGEventFlags exclude) {
    
    if (keycode == fromKey) {
        if (type == kCGEventKeyDown) {
            if (matchFlags(flags, exclude)) {
                *var = true;
                postKeyEventNoFlags(src, toKey, true);
                return true;
            }
        }
        if (*var && type == kCGEventKeyUp) {
            *var = false;
            postKeyEventNoFlags(src, toKey, false);
            return true;
        }
    }
    return false;
}

void disable_Maya() {
    isZDown = false;
    isTabDown = false;
    isScaling = false;
    isDeleting = false;
}

void disable_XCode() {
    xcode_Tab = false;
    xcode_ShiftTab = false;
}

void disable_Ps() {
    ps_fill = false;
    ps_clean = false;
    ps_layerAdd = false;
    ps_layerRemove = false;
    ps_scaleBrush = false;
    ps_cmdTab = false;
    for (int i=0; i<10; i++)
    {
        ps_nums[i] = false;
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

#pragma mark - Modifer

CGEventRef captureKeyStroke(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *pLogFile) {
    
    CGEventFlags flags = CGEventGetFlags(event);
    int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
//    int64_t mouseDeltaX = CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
    int64_t mouseDeltaY = CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);
//    int64_t tabletPressure = CGEventGetIntegerValueField(event, kCGTabletEventPointPressure);
//    NSLog(@"mouse dx -> %lld, dy -> %lld, pressure -> %lld", mouseDeltaX, mouseDeltaY, tabletPressure);
//    NSLog(@"keycode -> %lld, flags -> %lld, eventType -> %u", keycode, flags, type);
    



    // 在调试或者其他时候，在这个callback里如果走了太多时间，系统会停用这个callback，导致之后无法在进入
    // 这里在出现这种情况时，重新enable这个tap，避免失效
    if (type == kCGEventTapDisabledByTimeout) {
        /* Reset eventTap */
        CGEventTapEnable(eventTap, true);
        NSLog(@"time out");
        return NULL;
    }
    
    int64_t userData = CGEventGetIntegerValueField(event, kCGEventSourceUserData);
    
//    CGEventSetIntegerValueField(event, kCGMouseEventPressure, (int64_t)(((float)tabletPressure) * 0.5));

    // note: 这里调用 frontmostApplication 会leak，但是它被包在main的 autoreleasepool 里，不允许调用 release()
    // 只能再写个 autoreleasepool (autoreleasepool 可以嵌套)
    // why: c风格的回调函数里面，无法想用外层的 autoreleasepool 吗？
    @autoreleasepool {
        NSWorkspace *ws = NSWorkspace.sharedWorkspace;
        NSRunningApplication *frontmostApp = ws.frontmostApplication;
        //        return event;
        
        if (frontmostApp) {
            if ([frontmostApp.bundleIdentifier containsString:@"com.autodesk.Maya"] ||
                [frontmostApp.bundleIdentifier containsString:@"com.autodesk.mas.fbxreview"]) {
                curApp = App_Maya_Or_FbxReview;
            } else if ([frontmostApp.bundleIdentifier containsString:@"com.apple.dt.Xcode"]) {
                curApp = App_Xcode;
            } else if ([frontmostApp.bundleIdentifier containsString:@"com.apple.Preview"]) {
                curApp = App_Preview;
            } else if ([frontmostApp.bundleIdentifier containsString:@"com.tencent.qq"]) {
                curApp = App_QQ;
            } else if ([frontmostApp.bundleIdentifier containsString:@"com.google.Chrome"]) {
                curApp = App_Chrome;
            } else if ([frontmostApp.bundleIdentifier containsString:@"com.apple.Terminal"]) {
                curApp = App_Terminal;
            } else if ([frontmostApp.bundleIdentifier containsString:@"com.jetbrains.goland"]) {
                curApp = App_Goland;
            } else if ([frontmostApp.bundleIdentifier containsString:@"com.jetbrains.rider"]) {
                curApp = App_Rider;
            } else if ([frontmostApp.bundleIdentifier containsString:@"com.jetbrains.pycharm"]) {
                curApp = App_PyCharm;
            }  else if ([frontmostApp.bundleIdentifier containsString:@"com.adobe.Photoshop"]) {
                curApp = App_Photoshop;
            }  else if ([frontmostApp.bundleIdentifier containsString:@"jp.co.celsys.CLIPSTUDIOPAINT"]) {
                curApp = App_ClipStudioPaint;
            } else {
                curApp = None;
            }
        } else {
            curApp = None;
        }
        
        if (curApp != lastApp) {
            if (lastApp == App_Maya_Or_FbxReview) {
                disable_Maya();
            } else if (lastApp == App_Xcode) {
                disable_XCode();
            } else if (lastApp == App_Photoshop) {
                disable_Ps();
            }
        }
        
        //        if (curApp == None) {
        //            goto RET;
        //        }
        
        lastApp = curApp;
    }
    
    // 自己post的消息会进入这个callback。
    // 检测标识位，如果时自己post的，那么直接发送出去。
    if (userData == kUserPost) {
        goto RET;
    }
    
    // opt + ~ 开启或停用改键的开关
    if ((flags & kCGEventFlagMaskAlternate) && (keycode == kVK_ANSI_Grave)) {
        if (type == kCGEventKeyDown) {
            modifyEnable = !modifyEnable;
            NSLog(@"modify enable = %d", modifyEnable);
            if (!modifyEnable) {
                disable_Maya();
                disable_XCode();
                disable_Ps();
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
    // for all application except some
    {
        // ctrl + mouse Y => wheel
        if (curApp != App_Photoshop &&
            curApp != App_ClipStudioPaint) {
            
            if (matchFlags(flags, kCGEventFlagMaskControl)) {
                if (llabs(mouseDeltaY) > 0) {
                    CGEventFlags flags_;
                    if (curApp == App_Preview) {
                        // 预览app，如果去掉了原始按下的 control flag,模拟滚动会无效
                        flags_ = flags;
                    } else {
                        // idea系列，必须去掉 control flag，才有效
                        flags_ = flags ^ kCGEventFlagMaskControl;
                    }
                    
                    float wheelSensitivity = 1;
                    if (curApp == App_Preview) {
                        wheelSensitivity = 2;
                    } else if (curApp == App_Chrome) {
                        wheelSensitivity = 2;
                    } else if (curApp == App_Terminal) {
                        wheelSensitivity = 1;
                    } else if (curApp == App_QQ) {
                        wheelSensitivity = 2;
                    }
                    
                    postScrollWheelEvent(src, 1, (int32_t)(mouseDeltaY * wheelSensitivity), flags_);
                    //                postScrollWheelEvent(src, 1, (int32_t)(mouseDeltaY, flags ^ kCGEventFlagMaskControl);
                }
                // ?: how to scroll horizantally
                //            else if (llabs(mouseDeltaX) > 0) {
                //                postScrollWheelEvent(src, 2, (int32_t)mouseDeltaY, flags ^ kCGEventFlagMaskControl);
                //            }
            }
        }
        
    }
    if (curApp == App_Maya_Or_FbxReview) {
        
        // cmd + 3 => del
        if (keycode == kVK_ANSI_3) {
            if (matchFlags(flags, kCGEventFlagMaskCommand)) {
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
                    if (matchFlags(flags, 0) ||
                        matchFlags(flags, kCGEventFlagMaskCommand) ||
                        matchFlags(flags, kCGEventFlagMaskShift) ||
                        matchFlags(flags, kCGEventFlagMaskCommand | kCGEventFlagMaskShift)
                        ) {
                        isZDown = true;
                        
                        replacedEvent = CGEventCreateMouseEvent((CGEventSourceRef) src, kCGEventRightMouseDown, CGEventGetLocation(event), kCGMouseButtonRight);
                        //            NSLog(@"flag is %lld", flags);  // kCGEventFlagMaskNonCoalesced -> 0x100 -> 256
                        CGEventSetIntegerValueField(replacedEvent, kCGEventSourceUserData, kUserPost);
                        CGEventPost(tapLoc, replacedEvent); //
                        CFRelease(replacedEvent);
                        return nil;
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
            
            
            //                CGEventSetType(event, kCGEventRightMouseDragged);
            //                goto RET;
            //        }
        }
        
    } else if (curApp == App_Xcode) {
        if (keycode == kVK_Tab) {
            if (type == kCGEventKeyDown) {
                if (matchFlags(flags, kCGEventFlagMaskShift)) {
                    xcode_ShiftTab = true;
                    postKeyEvent(src, kVK_ANSI_LeftBracket, true, kCGEventFlagMaskCommand);
                    return nil;
                } else if (matchFlags(flags, 0)) {
                    xcode_Tab = true;
                    postKeyEvent(src, kVK_ANSI_RightBracket, true, kCGEventFlagMaskCommand);
                    return nil;
                }
            }
            
            if (type == kCGEventKeyUp) {
                if (xcode_ShiftTab) {
                    xcode_ShiftTab = false;
                    postKeyEvent(src, kVK_ANSI_LeftBracket, false, kCGEventFlagMaskCommand);
                    return nil;
                } else if (xcode_Tab) {
                    xcode_Tab = false;
                    postKeyEvent(src, kVK_ANSI_RightBracket, false, kCGEventFlagMaskCommand);
                    return nil;
                }
            }
        }
    } else if (curApp == App_Photoshop) {
        // cmd + 3 => clean
        if (modifyKey(src, keycode, type, flags,
                      kVK_ANSI_3, kCGEventFlagMaskCommand, &ps_clean,
                      kVK_F7, kCGEventFlagMaskAlternate)) {
            return nil;
        }
        
        // cmd + 2 => fill
        if (modifyKey(src, keycode, type, flags,
                      kVK_ANSI_2, kCGEventFlagMaskCommand, &ps_fill,
                      kVK_Delete, kCGEventFlagMaskAlternate)) {
            return nil;
        }
        // opt + a => ctrl + opt + a
        if (modifyKey(src, keycode, type, flags,
                      kVK_ANSI_A, kCGEventFlagMaskAlternate, &ps_layerAdd,
                      kVK_ANSI_A, kCGEventFlagMaskControl|kCGEventFlagMaskCommand)) {
            return nil;
        }
        // opt + x => ctrl + cmd + x
        if (modifyKey(src, keycode, type, flags,
                      kVK_ANSI_X, kCGEventFlagMaskAlternate, &ps_layerRemove,
                      kVK_ANSI_X, kCGEventFlagMaskControl|kCGEventFlagMaskCommand)) {
            return nil;
        }

        if (keycode == kVK_Tab) {
            
            if (type == kCGEventKeyDown) {
                if (flags & kCGEventFlagMaskCommand) {
                    ps_cmdTab = true;
                }
                if ((flags & kCGEventFlagMaskAlternate) |
                    (flags & kCGEventFlagMaskCommand) |
                    (flags & kCGEventFlagMaskShift) |
                    (flags & kCGEventFlagMaskControl) |
                    (flags & kCGEventFlagMaskSecondaryFn)) {
                    return event;
                }
                if (!ps_scaleBrush) {
                    ps_scaleBrush = true;

                    postKeyEventNoFlags(src, kVK_Option, true);
                    postKeyEventNoFlags(src, kVK_Control, true);

                    postMouseEvent(src, kCGEventLeftMouseDown, CGEventGetLocation(event), kCGMouseButtonLeft, flags | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate);
                    
                    return nil;
                }
            } else if (type == kCGEventKeyUp && ps_scaleBrush) {
                // 保留系统的 cmd + tab
                if (ps_cmdTab) {
                    return event;
                }
                
                ps_scaleBrush = false;
                
                postKeyEventNoFlags(src, kVK_Control, false);
                postKeyEventNoFlags(src, kVK_Option, false);
                postMouseEvent(src, kCGEventLeftMouseUp, CGEventGetLocation(event), kCGMouseButtonLeft, 0);
                
                return nil;
            }
        }
        if (ps_scaleBrush) {
            postMouseEvent(src, NX_MOUSEMOVED, CGEventGetLocation(event), kCGMouseButtonLeft, flags | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate);
//
            return nil;
            
//            if (type == kCGEventLeftMouseDown) {
//                postKeyEvenNoFlags(src, kVK_Option, true);
//                postKeyEvenNoFlags(src, kVK_Control, true);
//                    postMouseEvent(src, kCGEventLeftMouseDown, CGEventGetLocation(event), kCGMouseButtonLeft, flags);
//                NSLog(@"mouseDown");
//            }
//            if (type == NX_MOUSEMOVED) {
//                postMouseEvent(src, NX_MOUSEMOVED, CGEventGetLocation(event), kCGMouseButtonLeft, flags | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate);
//            }
//            if (type == kCGEventLeftMouseUp) {
//                postKeyEvenNoFlags(src, kVK_Control, false);
//                postKeyEvenNoFlags(src, kVK_Option, false);
//                postMouseEvent(src, kCGEventLeftMouseUp, CGEventGetLocation(event), kCGMouseButtonLeft, 0);
//            }
        }
        
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_Grave, &ps_nums[0], kVK_ANSI_0, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_Grave, &ps_nums[0], kVK_ANSI_0, kCGEventFlagMaskShift)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_0, &ps_nums[0], kVK_ANSI_Grave, 0)) return nil;

        // cmd + F1为ps系统占用，所以 cmd + 1时，不置换成F1
        if (exchangeKey(src, keycode, type, flags, kVK_F1, &ps_nums[1], kVK_ANSI_1, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_1, &ps_nums[1], kVK_F1, 0)) return nil;

        if (exchangeKey(src, keycode, type, flags, kVK_F2, &ps_nums[2], kVK_ANSI_2, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_2, &ps_nums[2], kVK_F2, 0)) return nil;

        if (exchangeKey(src, keycode, type, flags, kVK_F3, &ps_nums[3], kVK_ANSI_3, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_3, &ps_nums[3], kVK_F3, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_3, &ps_nums[3], kVK_F3, kCGEventFlagMaskAlternate)) return nil;

        if (exchangeKey(src, keycode, type, flags, kVK_F4, &ps_nums[4], kVK_ANSI_4, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_4, &ps_nums[4], kVK_F4, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_4, &ps_nums[4], kVK_F4, kCGEventFlagMaskAlternate)) return nil;
//        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_4, &ps_nums[4], kVK_F4, kCGEventFlagMaskCommand)) return nil;
//        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_4, &ps_nums[4], kVK_F4, kCGEventFlagMaskCommand | kCGEventFlagMaskShift)) return nil;

        if (exchangeKey(src, keycode, type, flags, kVK_F5, &ps_nums[5], kVK_ANSI_5, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_5, &ps_nums[5], kVK_F5, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_5, &ps_nums[5], kVK_F5, kCGEventFlagMaskAlternate)) return nil;

        if (exchangeKey(src, keycode, type, flags, kVK_F6, &ps_nums[6], kVK_ANSI_6, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_6, &ps_nums[6], kVK_F6, 0)) return nil;
        
        if (exchangeKey(src, keycode, type, flags, kVK_F7, &ps_nums[7], kVK_ANSI_7, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_7, &ps_nums[7], kVK_F7, 0)) return nil;
        
        if (exchangeKey(src, keycode, type, flags, kVK_F8, &ps_nums[8], kVK_ANSI_8, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_8, &ps_nums[8], kVK_F8, 0)) return nil;
        
        if (exchangeKey(src, keycode, type, flags, kVK_F9, &ps_nums[9], kVK_ANSI_9, 0)) return nil;
        if (exchangeKey(src, keycode, type, flags, kVK_ANSI_9, &ps_nums[9], kVK_F9, 0)) return nil;

    }
    
//    NSLog(@"keycode -> %lld, flags -> %lld, eventType -> %u", keycode, flags, type);
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
