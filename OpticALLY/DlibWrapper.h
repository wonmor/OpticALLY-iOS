#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DlibWrapper : NSObject

@property (assign, nonatomic) BOOL prepared;

// Method to prepare the dlib wrapper (load the model)
- (void)prepare;

// Method to process the sample buffer and depth data
- (void)doWorkOnSampleBuffer:(CMSampleBufferRef)sampleBuffer inRects:(NSArray<NSValue *> *)rects calibrationFilePath:(NSString *)calibrationFilePath
               depthFilePath:(NSString *)depthFilePath;

@end

NS_ASSUME_NONNULL_END
