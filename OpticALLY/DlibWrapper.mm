#import "DlibWrapper.h"
#import <UIKit/UIKit.h>
#include <dlib/image_processing.h>
#include <dlib/image_io.h>

@interface DlibWrapper ()

@property (assign) BOOL prepared;

+ (std::vector<dlib::rectangle>)convertCGRectValueArray:(NSArray<NSValue *> *)rects;

@end

@implementation DlibWrapper {
    dlib::shape_predictor sp;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _prepared = NO;
    }
    return self;
}

- (void)prepare {
    NSString *modelFileName = [[NSBundle mainBundle] pathForResource:@"shape_predictor_68_face_landmarks" ofType:@"dat"];
    if (!modelFileName) {
        NSLog(@"Model file not found in the bundle.");
        return;
    }
    
    const char *modelFileNameCString = [modelFileName UTF8String];
    if (!modelFileNameCString) {
        NSLog(@"Failed to convert NSString to C string.");
        return;
    }
    
    try {
        dlib::deserialize(modelFileNameCString) >> sp;
        self.prepared = YES;
        NSLog(@"DLib Wrapper Loading Completed!");
        
    } catch (const std::exception& e) {
        NSLog(@"Deserialization failed: %s", e.what());
    }
}

- (void)doWorkOnSampleBuffer:(CMSampleBufferRef)sampleBuffer inRects:(NSArray<NSValue *> *)rects {
    if (!self.prepared) {
        [self prepare];
        if (!self.prepared) {
            NSLog(@"Failed to prepare shape predictor.");
            return;
        }
    }
    
    dlib::array2d<dlib::bgr_pixel> img;
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    char *baseBuffer = (char *)CVPixelBufferGetBaseAddress(imageBuffer);
    
    img.set_size(height, width);
    
    img.reset();
    long position = 0;
    while (img.move_next()) {
        dlib::bgr_pixel& pixel = img.element();

        long bufferLocation = position * 4;
        char b = baseBuffer[bufferLocation];
        char g = baseBuffer[bufferLocation + 1];
        char r = baseBuffer[bufferLocation + 2];
        
        dlib::bgr_pixel newpixel(b, g, r);
        pixel = newpixel;
        
        position++;
    }
    
    CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    
    std::vector<dlib::rectangle> convertedRectangles = [DlibWrapper convertCGRectValueArray:rects];
    
    for (unsigned long j = 0; j < convertedRectangles.size(); ++j) {
        dlib::rectangle oneFaceRect = convertedRectangles[j];
        
        dlib::full_object_detection shape = sp(img, oneFaceRect);
        
        for (unsigned long k = 0; k < shape.num_parts(); k++) {
            dlib::point p = shape.part(k);
            draw_solid_circle(img, p, 3, dlib::rgb_pixel(0, 255, 255));
        }
        
        // Print out eye coordinates
        for (unsigned long k = 36; k <= 47; k++) {
            dlib::point p = shape.part(k);
            if (k <= 41) {
                NSLog(@"Left eye point %lu: (%ld, %ld)", k - 35, p.x(), p.y());
            } else {
                NSLog(@"Right eye point %lu: (%ld, %ld)", k - 41, p.x(), p.y());
            }
        }
    }
    
    CVPixelBufferLockBaseAddress(imageBuffer, 0);

    img.reset();
    position = 0;
    while (img.move_next()) {
        dlib::bgr_pixel& pixel = img.element();
        
        long bufferLocation = position * 4;
        baseBuffer[bufferLocation] = pixel.blue;
        baseBuffer[bufferLocation + 1] = pixel.green;
        baseBuffer[bufferLocation + 2] = pixel.red;
        
        position++;
    }
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
}

+ (std::vector<dlib::rectangle>)convertCGRectValueArray:(NSArray<NSValue *> *)rects {
    std::vector<dlib::rectangle> myConvertedRects;
    for (NSValue *rectValue in rects) {
        CGRect rect = [rectValue CGRectValue];
        long left = rect.origin.x;
        long top = rect.origin.y;
        long right = left + rect.size.width;
        long bottom = top + rect.size.height;
        dlib::rectangle dlibRect(left, top, right, bottom);

        myConvertedRects.push_back(dlibRect);
    }
    return myConvertedRects;
}

@end
