/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view implementing point cloud rendering
*/


#ifndef MetalImageDraw_h
#define MetalImageDraw_h

#import <MetalKit/MetalKit.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVDepthData.h>
#include <simd/simd.h>

@interface PointCloudMetalView : MTKView
@property (nonatomic, assign) BOOL shouldRender3DContent;
@property (nonatomic, strong) id<MTLBuffer> worldCoordinatesBuffer;

// Update depth frame
- (void)setDepthFrame:(AVDepthData* _Nullable)depth withTexture:(_Nullable CVPixelBufferRef)texture;

// Rotate around the Y axis
- (void)yawAroundCenter:(float)angle;

// Rotate around the X axis
- (void)pitchAroundCenter:(float)angle;

// Rotate around the Z axis
- (void)rollAroundCenter:(float)angle;

// Moves the camera towards the center point (or backwards)
- (void)moveTowardCenter:(float)scale;

- (void)processWorldCoordinates;

- (simd_float3)convert2DPointTo3D:(simd_float2)point2D
                           depth:(float)depth
                       intrinsics:(matrix_float3x3)intrinsics;

@end


#endif /* MetalImageDraw_h */
