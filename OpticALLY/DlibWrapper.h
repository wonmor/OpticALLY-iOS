#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

@interface DlibWrapper : NSObject

- (instancetype)init;
- (void)prepare;
- (void)doWorkOnSampleBuffer:(CMSampleBufferRef)sampleBuffer inRects:(NSArray<NSValue *> *)rects;
+ (NSString *)dlibVersionString;

@end
