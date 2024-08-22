#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "PointCloudMetalView.h"

NS_ASSUME_NONNULL_BEGIN

// Forward declare CameraViewController to resolve the unknown type name error
@class CameraViewController;

@interface DlibWrapper : NSObject

@property (assign, nonatomic) BOOL prepared;
@property (nonatomic, strong) PointCloudMetalView *pointCloudView;
@property (nonatomic, weak) CameraViewController *cameraViewController;

- (instancetype)initWithCameraViewController:(CameraViewController *)cameraViewController
                             pointCloudView:(PointCloudMetalView *)pointCloudView;

// Method to prepare the dlib wrapper (load the model)
- (void)prepare;

// Method to process the sample buffer and depth data
- (void)doWorkOnSampleBuffer:(CMSampleBufferRef)sampleBuffer inRects:(NSArray<NSValue *> *)rects withDepthData:(AVDepthData *)depthData;

- (simd_float3)convert2DPointTo3D:(simd_float2)point2D depth:(float)depth intrinsics:(simd_float3x3)intrinsics;

@end

NS_ASSUME_NONNULL_END
