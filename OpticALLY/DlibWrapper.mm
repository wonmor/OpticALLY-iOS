#import "DlibWrapper.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#include <dlib/image_processing.h>
#include <dlib/image_io.h>

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
    std::string modelFileNameCString = [modelFileName UTF8String];
    
    dlib::deserialize(modelFileNameCString) >> sp;
    
    // FIXME: test this stuff for memory leaks (cpp object destruction)
    self.prepared = YES;
}

- (void)doWorkOnSampleBuffer:(CMSampleBufferRef)sampleBuffer inRects:(NSArray<NSValue *> *)rects withDepthData:(AVDepthData *)depthData {
    if (!self.prepared) {
        [self prepare];
    }
    
    dlib::array2d<dlib::bgr_pixel> img;
    
    // MARK: magic
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    char *baseBuffer = (char *)CVPixelBufferGetBaseAddress(imageBuffer);
    
    // set_size expects rows, cols format
    img.set_size(height, width);
    
    // copy samplebuffer image data into dlib image format
    img.reset();
    long position = 0;
    while (img.move_next()) {
        dlib::bgr_pixel& pixel = img.element();

        // assuming bgra format here
        long bufferLocation = position * 4; //(row * width + column) * 4;
        char b = baseBuffer[bufferLocation];
        char g = baseBuffer[bufferLocation + 1];
        char r = baseBuffer[bufferLocation + 2];
        
        dlib::bgr_pixel newpixel(b, g, r);
        pixel = newpixel;
        
        position++;
    }
    
    // unlock buffer again until we need it again
    CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

    CGSize imageSize = CGSizeMake(width, height);
    
    // convert the face bounds list to dlib format
    std::vector<dlib::rectangle> convertedRectangles = [DlibWrapper convertCGRectValueArray:rects toVectorWithImageSize:imageSize];
    
    // Get depth data if available
    CVPixelBufferRef depthPixelBuffer = depthData.depthDataMap;
    CVPixelBufferLockBaseAddress(depthPixelBuffer, kCVPixelBufferLock_ReadOnly);
    float *depthDataPointer = (float *)CVPixelBufferGetBaseAddress(depthPixelBuffer);
    
    // for every detected face
    for (unsigned long j = 0; j < convertedRectangles.size(); ++j)
    {
        dlib::rectangle oneFaceRect = convertedRectangles[j];
        
        // detect all landmarks
        dlib::full_object_detection shape = sp(img, oneFaceRect);
        
        // Print specific landmarks
        dlib::point noseTip = shape.part(30);
        dlib::point chin = shape.part(8);
        dlib::point leftEyeLeftCorner = shape.part(36);
        dlib::point rightEyeRightCorner = shape.part(45);
        dlib::point leftMouthCorner = shape.part(48);
        dlib::point rightMouthCorner = shape.part(54);

        NSLog(@"Nose Tip: (%ld, %ld)", noseTip.x(), noseTip.y());
        NSLog(@"Chin: (%ld, %ld)", chin.x(), chin.y());
        NSLog(@"Left Eye Left Corner: (%ld, %ld)", leftEyeLeftCorner.x(), leftEyeLeftCorner.y());
        NSLog(@"Right Eye Right Corner: (%ld, %ld)", rightEyeRightCorner.x(), rightEyeRightCorner.y());
        NSLog(@"Left Mouth Corner: (%ld, %ld)", leftMouthCorner.x(), leftMouthCorner.y());
        NSLog(@"Right Mouth Corner: (%ld, %ld)", rightMouthCorner.x(), rightMouthCorner.y());

        // TO DO: Handle case where face is not visible within the bound of the camera view
        // Extract depth information for landmarks
        float noseDepth = depthDataPointer[noseTip.y() * width + noseTip.x()];
        float chinDepth = depthDataPointer[chin.y() * width + chin.x()];
        float leftEyeDepth = depthDataPointer[leftEyeLeftCorner.y() * width + leftEyeLeftCorner.x()];
        float rightEyeDepth = depthDataPointer[rightEyeRightCorner.y() * width + rightEyeRightCorner.x()];
        float leftMouthDepth = depthDataPointer[leftMouthCorner.y() * width + leftMouthCorner.x()];
        float rightMouthDepth = depthDataPointer[rightMouthCorner.y() * width + rightMouthCorner.x()];

        NSLog(@"Nose Depth: %f", noseDepth);
        NSLog(@"Chin Depth: %f", chinDepth);
        NSLog(@"Left Eye Depth: %f", leftEyeDepth);
        NSLog(@"Right Eye Depth: %f", rightEyeDepth);
        NSLog(@"Left Mouth Depth: %f", leftMouthDepth);
        NSLog(@"Right Mouth Depth: %f", rightMouthDepth);

        // and draw them into the image (samplebuffer)
        for (unsigned long k = 0; k < shape.num_parts(); k++) {
            dlib::point p = shape.part(k);
            draw_solid_circle(img, p, 3, dlib::rgb_pixel(0, 255, 255));
        }
    }
    
    // unlock depth buffer
    CVPixelBufferUnlockBaseAddress(depthPixelBuffer, kCVPixelBufferLock_ReadOnly);

    // lets put everything back where it belongs
    CVPixelBufferLockBaseAddress(imageBuffer, 0);

    // copy dlib image data back into samplebuffer
    img.reset();
    position = 0;
    while (img.move_next()) {
        dlib::bgr_pixel& pixel = img.element();
        
        // assuming bgra format here
        long bufferLocation = position * 4; //(row * width + column) * 4;
        baseBuffer[bufferLocation] = pixel.blue;
        baseBuffer[bufferLocation + 1] = pixel.green;
        baseBuffer[bufferLocation + 2] = pixel.red;
        
        position++;
    }
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
}

+ (dlib::rectangle)convertScaleCGRect:(CGRect)rect toDlibRectacleWithImageSize:(CGSize)size {
    long right = (1.0 - rect.origin.y ) * size.width;
    long left = right - rect.size.height * size.width;
    long top = rect.origin.x * size.height;
    long bottom = top + rect.size.width * size.height;
    
    dlib::rectangle dlibRect(left, top, right, bottom);
    return dlibRect;
}

+ (std::vector<dlib::rectangle>)convertCGRectValueArray:(NSArray<NSValue *> *)rects toVectorWithImageSize:(CGSize)size {
    std::vector<dlib::rectangle> myConvertedRects;
    for (NSValue *rectValue in rects) {
        CGRect singleRect = [rectValue CGRectValue];
        dlib::rectangle dlibRect = [DlibWrapper convertScaleCGRect:singleRect toDlibRectacleWithImageSize:size];
        myConvertedRects.push_back(dlibRect);
    }
    return myConvertedRects;
}

@end
