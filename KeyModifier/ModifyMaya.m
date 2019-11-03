#import "Modify.h"


@interface ModifyMaya : NSObject <Modify>

@end

@implementation ModifyMaya
+ (NSString *)bundleIdentifier {
    return @"com.autodesk.Maya";
}

+ (CGEventRef)modifyWithCGEventType:(CGEventType)type ref:(CGEventRef)event; {
    return event;
}
@end

