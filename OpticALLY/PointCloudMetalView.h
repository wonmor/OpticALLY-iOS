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

@end


#endif /* MetalImageDraw_h */
