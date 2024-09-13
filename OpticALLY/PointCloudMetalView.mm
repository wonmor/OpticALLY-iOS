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
    matrix_float3x3 intrinsics;

    id<MTLCommandQueue> _commandQueue;
    id<MTLComputePipelineState> _computePipelineState;  // Add this line
       id<MTLRenderPipelineState> _renderPipelineState;
       id<MTLBuffer> _unsolvedVertexBuffer;
       id<MTLBuffer> _solvedVertexBuffer;
       NSUInteger numVertices;  // Declare numVertices
    id<MTLDepthStencilState> _depthStencilState;
}

// Add this function before the convert2DPointTo3D method
float halfToFloat(uint16_t half) {
    uint32_t sign = (half >> 15) & 0x00000001;
    uint32_t exponent = (half >> 10) & 0x0000001F;
    uint32_t mantissa = half & 0x000003FF;

    if (exponent == 0) {
        if (mantissa == 0) {
            // Zero
            return sign ? -0.0f : 0.0f;
        } else {
            // Subnormal number
            while ((mantissa & 0x00000400) == 0) {
                mantissa <<= 1;
                exponent -= 1;
            }
            exponent += 1;
            mantissa &= ~0x00000400;
        }
    } else if (exponent == 31) {
        if (mantissa == 0) {
            // Infinity
            return sign ? -INFINITY : INFINITY;
        } else {
            // NaN
            return NAN;
        }
    }

    exponent = exponent + (127 - 15);
    uint32_t bits = (sign << 31) | (exponent << 23) | (mantissa << 13);
    float result;
    memcpy(&result, &bits, sizeof(result));
    return result;
}

- (simd_float3)convert2DPointTo3D:(simd_float2)point2D {
    __block AVDepthData* depthData = nil;

    // Synchronize access to the depth data
    dispatch_sync(_syncQueue, ^{
        depthData = self->_internalDepthFrame;
    });

    // Ensure depth data is available
    if (!depthData) {
        NSLog(@"Depth data is not available.");
        return simd_make_float3(0, 0, 0);
    } else {
        NSLog(@"Depth data is available.");
    }

    // Get the depth map from the depth data
    CVPixelBufferRef depthFrame = depthData.depthDataMap;

    // Lock the base address of the depth frame for reading
    CVReturn lockResult = CVPixelBufferLockBaseAddress(depthFrame, kCVPixelBufferLock_ReadOnly);
    if (lockResult != kCVReturnSuccess) {
        NSLog(@"Failed to lock depth frame base address.");
        return simd_make_float3(0, 0, 0);
    } else {
        NSLog(@"Depth frame base address locked.");
    }

    // Get the dimensions of the depth frame
    size_t width = CVPixelBufferGetWidth(depthFrame);
    size_t height = CVPixelBufferGetHeight(depthFrame);
    NSLog(@"Depth frame dimensions: width=%zu, height=%zu", width, height);

    // Ensure the provided 2D point is within bounds
    int x = (int)point2D.x;
    int y = (int)point2D.y;

    if (x < 0 || x >= width || y < 0 || y >= height) {
        NSLog(@"2D point (%d, %d) is out of bounds.", x, y);
        CVPixelBufferUnlockBaseAddress(depthFrame, kCVPixelBufferLock_ReadOnly);
        return simd_make_float3(0, 0, 0);
    } else {
        NSLog(@"2D point (%d, %d) is within bounds.", x, y);
    }

    // Access the depth value at the given point
    void* baseAddress = CVPixelBufferGetBaseAddress(depthFrame);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(depthFrame);
    NSLog(@"Base address acquired. Bytes per row: %zu", bytesPerRow);

    OSType pixelFormat = CVPixelBufferGetPixelFormatType(depthFrame);
    float depthValue = 0;

    if (pixelFormat == kCVPixelFormatType_DisparityFloat16 || pixelFormat == kCVPixelFormatType_DepthFloat16) {
        NSLog(@"Pixel format is 16-bit float.");
        // For 16-bit half-precision float
        uint16_t* dataPtr = (uint16_t*)baseAddress;
        size_t rowBytes = bytesPerRow / sizeof(uint16_t);
        size_t index = y * rowBytes + x;
        uint16_t depth16 = dataPtr[index];
        depthValue = halfToFloat(depth16);
        NSLog(@"Depth value at (%d, %d): %f (after conversion from half)", x, y, depthValue);
    } else if (pixelFormat == kCVPixelFormatType_DisparityFloat32 || pixelFormat == kCVPixelFormatType_DepthFloat32) {
        NSLog(@"Pixel format is 32-bit float.");
        // For 32-bit float
        float* dataPtr = (float*)baseAddress;
        size_t rowBytes = bytesPerRow / sizeof(float);
        size_t index = y * rowBytes + x;
        depthValue = dataPtr[index];
        NSLog(@"Depth value at (%d, %d): %f", x, y, depthValue);
    } else {
        // Unsupported pixel format
        NSLog(@"Unsupported pixel format: %u", (unsigned int)pixelFormat);
        CVPixelBufferUnlockBaseAddress(depthFrame, kCVPixelBufferLock_ReadOnly);
        return simd_make_float3(0, 0, 0);
    }

    // Unlock the depth frame after reading
    CVPixelBufferUnlockBaseAddress(depthFrame, kCVPixelBufferLock_ReadOnly);
    NSLog(@"Depth frame base address unlocked.");

    // Validate the depth value
    if (isnan(depthValue) || depthValue <= 0) {
        NSLog(@"Invalid depth value: %f", depthValue);
        return simd_make_float3(0, 0, 0);
    } else {
        NSLog(@"Valid depth value: %f", depthValue);
    }

    // Obtain and adjust the intrinsic matrix based on the depth frame dimensions
    matrix_float3x3 adjustedIntrinsics = depthData.cameraCalibrationData.intrinsicMatrix;
    CGSize referenceDimensions = depthData.cameraCalibrationData.intrinsicMatrixReferenceDimensions;
    NSLog(@"Intrinsic matrix reference dimensions: width=%f, height=%f", referenceDimensions.width, referenceDimensions.height);

    float ratioX = referenceDimensions.width / (float)width;
    float ratioY = referenceDimensions.height / (float)height;
    NSLog(@"Scaling ratios: ratioX=%f, ratioY=%f", ratioX, ratioY);

    adjustedIntrinsics.columns[0][0] /= ratioX; // fx
    adjustedIntrinsics.columns[1][1] /= ratioY; // fy
    adjustedIntrinsics.columns[2][0] /= ratioX; // cx
    adjustedIntrinsics.columns[2][1] /= ratioY; // cy

    // Extract intrinsic parameters
    float fx = adjustedIntrinsics.columns[0][0];
    float fy = adjustedIntrinsics.columns[1][1];
    float cx = adjustedIntrinsics.columns[2][0];
    float cy = adjustedIntrinsics.columns[2][1];
    NSLog(@"Adjusted intrinsic parameters: fx=%f, fy=%f, cx=%f, cy=%f", fx, fy, cx, cy);

    // Compute the 3D point in camera space
    float px = (point2D.x - cx) / fx * depthValue;
    float py = (point2D.y - cy) / fy * depthValue;
    float pz = depthValue;
    NSLog(@"Computed 3D point: (%f, %f, %f)", px, py, pz);

    simd_float3 point3D = {px, py, pz};

    return point3D;
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



