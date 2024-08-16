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
    float r, g, b;
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

    id<MTLCommandQueue> _commandQueue;
    id<MTLDepthStencilState> _depthStencilState;
    id<MTLComputePipelineState> _computePipelineState;  // Add this line
      id<MTLRenderPipelineState> _renderPipelineState;
      id<MTLBuffer> _unsolvedVertexBuffer;
      id<MTLBuffer> _solvedVertexBuffer;
      NSUInteger numVertices;  // Declare numVertices
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
    // Create a buffer to hold the world coordinates
       NSUInteger numVertices = 640 * 480; // Assuming width and height of the depth texture
       _worldCoordinatesBuffer = [self.device newBufferWithLength:sizeof(float) * 3 * numVertices
                                                         options:MTLResourceStorageModeShared];
    
    [self configureMetal];
    
    CVMetalTextureCacheCreate(NULL, NULL, self.device, NULL, &_depthTextureCache);
    CVMetalTextureCacheCreate(NULL, NULL, self.device, NULL, &_colorTextureCache);

    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    
    [self resetView];
}

- (void)configureMetal {
    // Load all the shader files with a metal file extension in the project
    id<MTLLibrary> defaultLibrary = [self.device newDefaultLibrary];

    // Load the vertex function from the library
    id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShaderPoints"];
    
    // Load the fragment function from the library
    id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShaderPoints"];
    
    // Load the compute function from the library
    id <MTLFunction> computeFunction = [defaultLibrary newFunctionWithName:@"solve_vertex"];

    // Create a compute pipeline state
    NSError *error = nil;
    _computePipelineState = [self.device newComputePipelineStateWithFunction:computeFunction error:&error];
    if (!_computePipelineState) {
        NSLog(@"Failed to created compute pipeline state, error %@", error);
    }

    // Set up the render pipeline
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
    
    _renderPipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                       error:&error];

    if (!_renderPipelineState) {
        NSLog(@"Failed to created pipeline state, error %@", error);
    }
    
    // Create the command queue
    _commandQueue = [self.device newCommandQueue];

    // Create buffers for the compute shader
    NSUInteger numVertices = 640 * 480; // Example vertex count
    _unsolvedVertexBuffer = [self.device newBufferWithLength:sizeof(VertexIn) * numVertices options:MTLResourceStorageModeShared];
    _solvedVertexBuffer = [self.device newBufferWithLength:sizeof(VertexOut) * numVertices options:MTLResourceStorageModeShared];
}


// PointXYZ structure
typedef struct {
    float x, y, z;
} PointXYZ;


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

- (void)processWorldCoordinates {
    // Access the world coordinates after rendering
    float* worldCoordinates = (float*)[_worldCoordinatesBuffer contents];

    NSUInteger numVertices = 640 * 480;
    
    // Process the coordinates (example: print or pass them to another function)
    for (int i = 0; i < numVertices; i++) {
        float x = worldCoordinates[i * 3];
        float y = worldCoordinates[i * 3 + 1];
        float z = worldCoordinates[i * 3 + 2];
        NSLog(@"World Coordinate [%d]: (%f, %f, %f)", i, x, y, z);
    }
}

- (void)drawRect:(CGRect)rect {
    if (!_shouldRender3DContent) {
        // Clear the view or skip drawing
        return;
    }

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
    
    // Initialize intrinsics
        matrix_float3x3 intrinsics = depthData.cameraCalibrationData.intrinsicMatrix;
        CGSize referenceDimensions = depthData.cameraCalibrationData.intrinsicMatrixReferenceDimensions;

    // Update _unsolvedVertexBuffer with data from the depth map or any other source
    [self updateUnsolvedVertexBufferWithDepth:depthFrame intrinsics:depthData.cameraCalibrationData.intrinsicMatrix];

    // Create a new command buffer for each renderpass to the current drawable
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    // Encode the compute command
    id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
    [computeEncoder setComputePipelineState:_computePipelineState];
    [computeEncoder setBuffer:_unsolvedVertexBuffer offset:0 atIndex:0];
    [computeEncoder setBuffer:_solvedVertexBuffer offset:0 atIndex:1];

    MTLSize gridSize = MTLSizeMake(numVertices, 1, 1);
    NSUInteger threadGroupSize = _computePipelineState.maxTotalThreadsPerThreadgroup;
    MTLSize threadGroup = MTLSizeMake(threadGroupSize, 1, 1);
    [computeEncoder dispatchThreads:gridSize threadsPerThreadgroup:threadGroup];
    [computeEncoder endEncoding];

    // Continue with rendering...
    MTLRenderPassDescriptor *renderPassDescriptor = self.currentRenderPassDescriptor;

    if (renderPassDescriptor != nil) {
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

        // Set arguments to the shader
        [renderEncoder setVertexTexture:depthTexture atIndex:0];
        [renderEncoder setVertexBuffer:_solvedVertexBuffer offset:0 atIndex:2];

        simd::float4x4 finalViewMatrix = [self getFinalViewMatrix];
        [renderEncoder setVertexBytes:&finalViewMatrix length:sizeof(finalViewMatrix) atIndex:0];
        [renderEncoder setVertexBytes:&intrinsics length:sizeof(intrinsics) atIndex:1];
        [renderEncoder setFragmentTexture:colorTexture atIndex:0];

        [renderEncoder drawPrimitives:MTLPrimitiveTypePoint vertexStart:0 vertexCount:numVertices];

        [renderEncoder endEncoding];

        [commandBuffer presentDrawable:self.currentDrawable];
    }

    [commandBuffer commit];

    CFRelease(cvDepthTexture);
    CFRelease(cvColorTexture);
    CVPixelBufferRelease(colorFrame);
}

- (void)updateUnsolvedVertexBufferWithDepth:(CVPixelBufferRef)depthFrame intrinsics:(matrix_float3x3)intrinsics {
    // Example function to populate the unsolvedVertexBuffer with depth data.
    // You would populate _unsolvedVertexBuffer here with your vertex data before running the compute shader.
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




