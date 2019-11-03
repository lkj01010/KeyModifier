//
//  IModifier.h
//  KeyModifier
//
//  Created by 林 科俊 on 2019/11/1.
//  Copyright © 2019 Mid. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol Modify <NSObject>
+ (NSString *)bundleIdentifier;
+ (CGEventRef)modifyWithCGEventType:(CGEventType)type ref:(CGEventRef)event;
@end

