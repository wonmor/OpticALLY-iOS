/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view implementing point cloud rendering
*/

#import <MetalKit/MetalKit.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <Foundation/Foundation.h>
#include "PointCloudMetalView.h"
#import "AAPLTransforms.h"
#include <simd/simd.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>

typedef struct {
    float x, y, z;
} VertexIn;

typedef struct {
    float x, y, z;
} VertexOut;



simd::float3 matrix4_mul_vector3(simd::float4x4 m, simd::float3 v) {
    simd::float4 temp = { v.x, v.y, v.z, 0.0f };
    temp = simd_mul(m, temp);
    return { temp.x, temp.y, temp.z };
}

@implementation PointCloudMetalView {
    dispatch_queue_t _syncQueue;
    AVDepthData* _internalDepthFrame;
    CVPixelBufferRef _internalColorTexture;
    CVMetalTextureCacheRef _depthTextureCache;
    CVMetalTextureCacheRef _colorTextureCache;
    simd::float3 _center;   // current point camera looks at
    simd::float3 _eye;      // current camera position
    simd::float3 _up;       // camera "up" direction
    simd::float2 point2D;
    matrix_float3x3 intrinsics;

    id<MTLCommandQueue> _commandQueue;
    id<MTLComputePipelineState> _computePipelineState;  // Add this line
       id<MTLRenderPipelineState> _renderPipelineState;
       id<MTLBuffer> _unsolvedVertexBuffer;
       id<MTLBuffer> _solvedVertexBuffer;
       NSUInteger numVertices;  // Declare numVertices
    id<MTLDepthStencilState> _depthStencilState;
}

- (void)updatePoint2DWithX:(float)x Y:(float)y {
    point2D = simd_make_float2(x, y);
    
    // Manually trigger a redraw to see the update
    [self setNeedsDisplay];
}

- (simd_float3)convert2DPointTo3D:(simd_float2)point2D {
    // Ensure the depth data is available
    if (!_internalDepthFrame) {
        NSLog(@"No depth data available.");
        return simd_make_float3(0, 0, 0);
    }

    // Get the depth data map (CVPixelBufferRef)
    CVPixelBufferRef depthFrame = _internalDepthFrame.depthDataMap;
    CVPixelBufferLockBaseAddress(depthFrame, kCVPixelBufferLock_ReadOnly);
    float *depthDataPointer = (float *)CVPixelBufferGetBaseAddress(depthFrame);

    // Get the width and height of the depth frame
    size_t depthWidth = CVPixelBufferGetWidth(depthFrame);
    size_t depthHeight = CVPixelBufferGetHeight(depthFrame);
    NSLog(@"Depth frame size: %zu x %zu", depthWidth, depthHeight);

    // Calculate the x and y indices within the depth map
    NSUInteger xIndex = MIN(MAX(point2D.x, 0), depthWidth - 1);
    NSUInteger yIndex = MIN(MAX(point2D.y, 0), depthHeight - 1);
    NSLog(@"2D Point: (%f, %f), Depth map indices: xIndex = %lu, yIndex = %lu", point2D.x, point2D.y, (unsigned long)xIndex, (unsigned long)yIndex);

    // Calculate the byte offset for the depth value at the given 2D point
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(depthFrame);
    size_t depthOffset = yIndex * bytesPerRow + xIndex * sizeof(float);
    if (depthOffset >= CVPixelBufferGetDataSize(depthFrame)) {
        NSLog(@"Offset out of bounds");
        CVPixelBufferUnlockBaseAddress(depthFrame, kCVPixelBufferLock_ReadOnly);
        return simd_make_float3(0, 0, 0);
    }

    // Get the depth value (assume it's float16)
    float depthValue = 0.0f;
    if (CVPixelBufferGetPixelFormatType(depthFrame) == kCVPixelFormatType_DepthFloat16) {
        UInt16 *depthPointer = (UInt16 *)((char *)CVPixelBufferGetBaseAddress(depthFrame) + depthOffset);
        depthValue = (float)(*depthPointer) / 65535.0f; // Normalize 16-bit depth to [0, 1]
    } else {
        float *depthPointer = (float *)((char *)CVPixelBufferGetBaseAddress(depthFrame) + depthOffset);
        depthValue = *depthPointer;
    }

    NSLog(@"Depth value at (%lu, %lu): %f", (unsigned long)xIndex, (unsigned long)yIndex, depthValue);

    CVPixelBufferUnlockBaseAddress(depthFrame, kCVPixelBufferLock_ReadOnly);

    // Extract the intrinsic parameters
    float fx = intrinsics.columns[0][0];
    float fy = intrinsics.columns[1][1];
    float cx = intrinsics.columns[2][0];
    float cy = intrinsics.columns[2][1];
    NSLog(@"Intrinsic parameters: fx = %f, fy = %f, cx = %f, cy = %f", fx, fy, cx, cy);
    
    // Back-project the 2D point into 3D space
    float xrw = (point2D.x - cx) * depthValue / fx;
    float yrw = (point2D.y - cy) * depthValue / fy;
    float zrw = depthValue;
    NSLog(@"3D World Coordinates: (%f, %f, %f)", xrw, yrw, zrw);
    
    // Return the 3D world coordinate
    return simd_make_float3(xrw, yrw, zrw);
}

- (simd_float3)query3DPointFrom2DCoordinates:(simd_float2)xyCoords {
    NSUInteger resolutionWidth = 640;
    NSUInteger resolutionHeight = 480;
    NSUInteger flatIndex = xyCoords.y * resolutionWidth + xyCoords.x;

    if (flatIndex < (resolutionWidth * resolutionHeight)) {
        VertexOut* solvedVertices = (VertexOut*)[_solvedVertexBuffer contents];
        return simd_make_float3(solvedVertices[flatIndex].x, solvedVertices[flatIndex].y, solvedVertices[flatIndex].z);
    } else {
        return simd_make_float3(0, 0, 0);  // Return a default value if the index is out of bounds
    }
}

- (nonnull instancetype)initWithFrame:(CGRect)frameRect device:(nullable id<MTLDevice>)device {
    self = [super initWithFrame:frameRect device:device];
    [self internalInit];
    return self;
}

- (nonnull instancetype)initWithCoder:(nonnull NSCoder *)coder {
    self = [super initWithCoder:coder];
    self.device = MTLCreateSystemDefaultDevice();
    [self internalInit];
    return self;
}

- (void)internalInit {
    dispatch_queue_attr_t attr = NULL;
    attr = dispatch_queue_attr_make_with_autorelease_frequency(attr, DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM);
    attr = dispatch_queue_attr_make_with_qos_class(attr, QOS_CLASS_USER_INITIATED, 0);
    _syncQueue = dispatch_queue_create("PointCloudMetalView sync queue", attr);

    NSUInteger numVertices = 640 * 480;
    _worldCoordinatesBuffer = [self.device newBufferWithLength:sizeof(float) * 3 * numVertices
                                                       options:MTLResourceStorageModeShared];

    [self configureMetal];

    CVMetalTextureCacheCreate(NULL, NULL, self.device, NULL, &_depthTextureCache);
    CVMetalTextureCacheCreate(NULL, NULL, self.device, NULL, &_colorTextureCache);

    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;

    [self resetView];
}

- (void)configureMetal {
    id<MTLLibrary> defaultLibrary = [self.device newDefaultLibrary];

    id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShaderPoints"];
    id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShaderPoints"];

    NSError *error = nil;

    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.label = @"Texturing Pipeline";
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    pipelineStateDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

    MTLDepthStencilDescriptor *pipelineDepthDescriptor = [[MTLDepthStencilDescriptor alloc] init];
    pipelineDepthDescriptor.depthWriteEnabled = true;
    pipelineDepthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
    _depthStencilState = [self.device newDepthStencilStateWithDescriptor:pipelineDepthDescriptor];

    _renderPipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];

    if (!_renderPipelineState) {
        NSLog(@"Failed to create pipeline state, error %@", error);
    }

    _commandQueue = [self.device newCommandQueue];

    NSUInteger numVertices = 640 * 480;
    _unsolvedVertexBuffer = [self.device newBufferWithLength:sizeof(VertexIn) * numVertices options:MTLResourceStorageModeShared];
    _solvedVertexBuffer = [self.device newBufferWithLength:sizeof(VertexOut) * numVertices options:MTLResourceStorageModeShared];
}


// PointXYZ structure
typedef struct {
    float x, y, z;
} PointXYZ;

- (void)processWorldCoordinates {
    VertexOut* solvedVertices = (VertexOut*)[_solvedVertexBuffer contents];
}

- (NSString *)documentsPathForFileName:(NSString *)name {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = [paths objectAtIndex:0];
    return [documentsPath stringByAppendingPathComponent:name];
}

- (void)setDepthFrame:(AVDepthData* _Nullable)depth withTexture:(CVPixelBufferRef _Nullable)texture {
    dispatch_sync(_syncQueue, ^{

            // Handle non-nil depth and texture as before
            self->_shouldRender3DContent = YES;
            self->_internalDepthFrame = depth;
            if (self->_internalColorTexture) {
                CVPixelBufferRelease(self->_internalColorTexture);
            }
            self->_internalColorTexture = texture;
            CVPixelBufferRetain(self->_internalColorTexture);
        
    });

    // Trigger a redraw of the view
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setNeedsDisplay];
    });
}

- (void)drawRect:(CGRect)rect {
    __block AVDepthData* depthData = nil;
    __block CVPixelBufferRef colorFrame = nullptr;
    
    dispatch_sync(_syncQueue, ^{
        depthData = self->_internalDepthFrame;
        colorFrame = self->_internalColorTexture;
        CVPixelBufferRetain(colorFrame);
    });
    
    if (depthData == nil || colorFrame == nullptr)
        return;
    
    // Create a Metal texture from the depth frame
    CVPixelBufferRef depthFrame = depthData.depthDataMap;
    CVMetalTextureRef cvDepthTexture = nullptr;
    if (kCVReturnSuccess != CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                      _depthTextureCache,
                                                                      depthFrame,
                                                                      nil,
                                                                      MTLPixelFormatR16Float,
                                                                      CVPixelBufferGetWidth(depthFrame),
                                                                      CVPixelBufferGetHeight(depthFrame),
                                                                      0,
                                                                      &cvDepthTexture)) {
        NSLog(@"Failed to create depth texture");
        CVPixelBufferRelease(colorFrame);
        return;
    }
    
    id<MTLTexture> depthTexture = CVMetalTextureGetTexture(cvDepthTexture);
    
    // Create a Metal texture from the color texture
    CVMetalTextureRef cvColorTexture = nullptr;
    if (kCVReturnSuccess != CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                      _colorTextureCache,
                                                                      colorFrame,
                                                                      nil,
                                                                      MTLPixelFormatBGRA8Unorm,
                                                                      CVPixelBufferGetWidth(colorFrame),
                                                                      CVPixelBufferGetHeight(colorFrame),
                                                                      0,
                                                                      &cvColorTexture)) {
        NSLog(@"Failed to create color texture");
        CVPixelBufferRelease(colorFrame);
        return;
    }
    
    id<MTLTexture> colorTexture = CVMetalTextureGetTexture(cvColorTexture);
    
    matrix_float3x3 intrinsics = depthData.cameraCalibrationData.intrinsicMatrix;
    CGSize referenceDimensions = depthData.cameraCalibrationData.intrinsicMatrixReferenceDimensions;
    
    float ratio = referenceDimensions.width / CVPixelBufferGetWidth(depthFrame);
    intrinsics.columns[0][0] /= ratio;
    intrinsics.columns[1][1] /= ratio;
    intrinsics.columns[2][0] /= ratio;
    intrinsics.columns[2][1] /= ratio;
    
    // Create a new command buffer for each renderpass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor *renderPassDescriptor = self.currentRenderPassDescriptor;
    
    if(renderPassDescriptor != nil) {
        MTLTextureDescriptor* depthTextureDescriptor = [[MTLTextureDescriptor alloc] init];
        depthTextureDescriptor.width = self.drawableSize.width;
        depthTextureDescriptor.height = self.drawableSize.height;
        depthTextureDescriptor.pixelFormat = MTLPixelFormatDepth32Float;
        depthTextureDescriptor.usage = MTLTextureUsageRenderTarget;
        
        id<MTLTexture> depthTestTexture = [self.device newTextureWithDescriptor:depthTextureDescriptor];
        
        renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
        renderPassDescriptor.depthAttachment.storeAction = MTLStoreActionStore;
        renderPassDescriptor.depthAttachment.clearDepth = 1.0;
        renderPassDescriptor.depthAttachment.texture = depthTestTexture;
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [renderEncoder setDepthStencilState:_depthStencilState];
        [renderEncoder setRenderPipelineState:_renderPipelineState];
        
        // set arguments to shader
        [renderEncoder setVertexTexture:depthTexture atIndex:0];
        
        simd::uint2 queryPos = {(uint)point2D.x, (uint)point2D.y};
                [renderEncoder setFragmentBytes:&queryPos length:sizeof(simd::uint2) atIndex:0];
        
        // Buffer to store the result
                id<MTLBuffer> resultBuffer = [self.device newBufferWithLength:sizeof(simd_float3) options:MTLResourceStorageModeShared];
                [renderEncoder setFragmentBuffer:resultBuffer offset:0 atIndex:1];
        
        simd::float4x4 finalViewMatrix = [self getFinalViewMatrix];
        
        [renderEncoder setVertexBytes:&finalViewMatrix length:sizeof(finalViewMatrix) atIndex:0];
        [renderEncoder setVertexBytes:&intrinsics length:sizeof(intrinsics) atIndex:1]; // Correctly bind the intrinsics buffer to index 2
        
        [renderEncoder setFragmentTexture:colorTexture atIndex:0];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypePoint
                          vertexStart:0
                          vertexCount:CVPixelBufferGetWidth(depthFrame) * CVPixelBufferGetHeight(depthFrame)];
        
        [renderEncoder endEncoding];
        
        // Schedule a present once the framebuffer is complete using the current drawable
        [commandBuffer presentDrawable:self.currentDrawable];
    }
    
    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
    
    CFRelease(cvDepthTexture);
    CFRelease(cvColorTexture);
    CVPixelBufferRelease(colorFrame);
}


- (void)rollAroundCenter:(float)angle {
    dispatch_sync(_syncQueue, ^{
        simd::float3 viewDir = self->_center - self->_eye;
        viewDir = simd::normalize(viewDir);
        simd::float4x4 rotMat = AAPL::rotate(angle, viewDir);
        self->_up = matrix4_mul_vector3(rotMat, self->_up);
    });
}

// rotate around Y axis
- (void)yawAroundCenter:(float)angle {
    dispatch_sync(_syncQueue, ^{
        simd::float4x4 rotMat = AAPL::rotate(angle, self->_up);

        self->_eye = self->_eye - self->_center;
        self->_eye = matrix4_mul_vector3(rotMat, self->_eye);
        self->_eye = self->_eye + self->_center;

        self->_up = matrix4_mul_vector3(rotMat, self->_up);
    });
}

// rotate around X axis
- (void)pitchAroundCenter:(float)angle {
    dispatch_sync(_syncQueue, ^{
        simd::float3 viewDirection = simd_normalize(self->_center - self->_eye);
        simd::float3 rightVector = simd_cross(self->_up, viewDirection);
        
        simd::float4x4 rotMat = AAPL::rotate(angle, rightVector);

        self->_eye = self->_eye - self->_center;
        self->_eye = matrix4_mul_vector3(rotMat, self->_eye);
        self->_eye = self->_eye + self->_center;

        self->_up = matrix4_mul_vector3(rotMat, self->_up);
    });
}

- (void)moveTowardCenter:(float)scale
{
    __block float _scale = scale;
    
    dispatch_sync(_syncQueue, ^{
        simd::float3 direction = self->_center - self->_eye;
        
        // don't move to the other side of _center
        float distance = sqrt(simd_dot(direction, direction));
        if (_scale > distance)
            _scale = distance - 3.0;
        
        direction = simd::normalize(direction);
        direction = direction * _scale;
        self->_eye += direction;
    });
}

-(void)resetView {
    dispatch_sync(_syncQueue, ^{
        self->_center = simd::float3 { 0, 0, 500 };   // start at a distance of ~50cm
        self->_eye = simd::float3 { 0, 0, 0 };
        // The TrueDepth camera outputs frames that are aligned to device landscape, so should be rotated 90 degrees counter-clockwise
        self->_up = simd_float3 { -1 , 0 ,0 };
        
    });
}

-(simd::float4x4)getFinalViewMatrix {
    float aspect = (self.drawableSize.width / self.drawableSize.height);

    // Use a magic number that simply looks good
    float vfov = 70;
    simd::float4x4 appleProjMat = AAPL::perspective_fov(vfov, aspect, 0.01f, 30000);

    __block simd::float3 eye, center, up;
    
    // take camera position in a synchornized way
    dispatch_sync(_syncQueue, ^{
        eye = self->_eye;
        center = self->_center;
        up = self->_up;
    });
                  
    simd::float4x4 appleViewMat = AAPL::lookAt(eye, center, up);
    
    // Final view matrix is projection * view * model. In our case, we never move the model itself, so we can ignore its matrix.
    return appleProjMat * appleViewMat;
}

@end



