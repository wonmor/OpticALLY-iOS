#import "DlibWrapper.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#include <dlib/image_processing.h>
#include <dlib/image_io.h>
#include <opencv2/opencv.hpp>

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
    NSLog(@"Depth Data Map: %@", depthData.depthDataMap);

    CVPixelBufferRef depthPixelBuffer = depthData.depthDataMap;
    CVPixelBufferLockBaseAddress(depthPixelBuffer, kCVPixelBufferLock_ReadOnly);
    float *depthDataPointer = (float *)CVPixelBufferGetBaseAddress(depthPixelBuffer);

    // Ensure the original image is in BGR format (three channels)
    cv::Mat originalImg(height, width, CV_8UC4, baseBuffer);
    cv::Mat bgrOriginalImg;
    cv::cvtColor(originalImg, bgrOriginalImg, cv::COLOR_BGRA2BGR);

    // Create a grayscale depth map
    dlib::array2d<unsigned char> depthMap;
    depthMap.set_size(height, width); // Note the order: height (rows), width (cols)

    // Normalize depth values and copy to depthMap
    float minDepth = FLT_MAX, maxDepth = FLT_MIN;
    for (int i = 0; i < height; ++i) {
        for (int j = 0; j < width; ++j) {
            size_t depthOffset = i * CVPixelBufferGetBytesPerRow(depthPixelBuffer) + j * sizeof(UInt16); // Note: no transpose
            if (depthOffset >= CVPixelBufferGetDataSize(depthPixelBuffer)) {
                continue; // Skip if offset is out of bounds
            }
            UInt16 *depthPointer = (UInt16 *)((char *)CVPixelBufferGetBaseAddress(depthPixelBuffer) + depthOffset);
            float depthValue = (float)(*depthPointer);
            if (depthValue < minDepth) minDepth = depthValue;
            if (depthValue > maxDepth) maxDepth = depthValue;
        }
    }

    for (int i = 0; i < height; ++i) {
        for (int j = 0; j < width; ++j) {
            size_t depthOffset = i * CVPixelBufferGetBytesPerRow(depthPixelBuffer) + j * sizeof(UInt16); // Note: no transpose
            if (depthOffset >= CVPixelBufferGetDataSize(depthPixelBuffer)) {
                continue; // Skip if offset is out of bounds
            }
            UInt16 *depthPointer = (UInt16 *)((char *)CVPixelBufferGetBaseAddress(depthPixelBuffer) + depthOffset);
            float depthValue = (float)(*depthPointer);
            unsigned char intensity = (unsigned char)(255.0 * (depthValue - minDepth) / (maxDepth - minDepth));
            depthMap[i][j] = intensity; // No transpose
        }
    }

    // Convert dlib::array2d to cv::Mat
    cv::Mat depthMat(height, width, CV_8UC1); // Single channel grayscale
    for (int i = 0; i < height; ++i) {
        for (int j = 0; j < width; ++j) {
            depthMat.at<unsigned char>(i, j) = depthMap[i][j];
        }
    }

    // Convert the flipped depth map to a three-channel BGR image
    cv::Mat colorDepthMat;
    cv::cvtColor(depthMat, colorDepthMat, cv::COLOR_GRAY2BGR);

    // Alpha blend the depth map with the original image
    cv::Mat blendedImg;
    cv::addWeighted(bgrOriginalImg, 0.25, colorDepthMat, 0.75, 0.0, blendedImg);
    // for every detected face
    for (unsigned long j = 0; j < convertedRectangles.size(); ++j) {
        dlib::rectangle oneFaceRect = convertedRectangles[j];
        
        // detect all landmarks
        dlib::full_object_detection shape = sp(img, oneFaceRect);
        
        // Extract specific landmarks
        dlib::point noseTip = shape.part(30);
        dlib::point chin = shape.part(8);
        dlib::point leftEyeLeftCorner = shape.part(36);
        dlib::point rightEyeRightCorner = shape.part(45);
        dlib::point leftMouthCorner = shape.part(48);
        dlib::point rightMouthCorner = shape.part(54);

        auto safeDepthValueAt = [&](int x, int y, float defaultValue = 0.0f) -> float {
            if (!depthDataPointer || x < 0 || x >= width || y < 0 || y >= height) {
                return defaultValue;
            }
            size_t index = y * width + x;
            if (index >= CVPixelBufferGetDataSize(depthPixelBuffer) / sizeof(float)) {
                return defaultValue;
            }
            return depthDataPointer[index];
        };

        // Extract depth information for landmarks with null safety and bounds check
        float noseDepth = safeDepthValueAt(noseTip.x(), noseTip.y());
        float chinDepth = safeDepthValueAt(chin.x(), chin.y());
        float leftEyeDepth = safeDepthValueAt(leftEyeLeftCorner.x(), leftEyeLeftCorner.y());
        float rightEyeDepth = safeDepthValueAt(rightEyeRightCorner.x(), rightEyeRightCorner.y());
        float leftMouthDepth = safeDepthValueAt(leftMouthCorner.x(), leftMouthCorner.y());
        float rightMouthDepth = safeDepthValueAt(rightMouthCorner.x(), rightMouthCorner.y());

        // Print the coordinates and depths
        NSLog(@"Nose Tip: (%ld, %ld) Depth: %f", noseTip.x(), noseTip.y(), noseDepth);
        NSLog(@"Chin: (%ld, %ld) Depth: %f", chin.x(), chin.y(), chinDepth);
        NSLog(@"Left Eye Left Corner: (%ld, %ld) Depth: %f", leftEyeLeftCorner.x(), leftEyeLeftCorner.y(), leftEyeDepth);
        NSLog(@"Right Eye Right Corner: (%ld, %ld) Depth: %f", rightEyeRightCorner.x(), rightEyeRightCorner.y(), rightEyeDepth);
        NSLog(@"Left Mouth Corner: (%ld, %ld) Depth: %f", leftMouthCorner.x(), leftMouthCorner.y(), leftMouthDepth);
        NSLog(@"Right Mouth Corner: (%ld, %ld) Depth: %f", rightMouthCorner.x(), rightMouthCorner.y(), rightMouthDepth);

        // OpenCV head pose estimation
        cv::Mat cvImg(height, width, CV_8UC4, baseBuffer);
        cv::cvtColor(cvImg, cvImg, cv::COLOR_BGRA2BGR);
        
        std::vector<cv::Point2d> image_points;
        image_points.push_back(cv::Point2d(noseTip.x(), noseTip.y()));    // Nose tip
        image_points.push_back(cv::Point2d(chin.x(), chin.y()));          // Chin
        image_points.push_back(cv::Point2d(leftEyeLeftCorner.x(), leftEyeLeftCorner.y()));    // Left eye left corner
        image_points.push_back(cv::Point2d(rightEyeRightCorner.x(), rightEyeRightCorner.y()));    // Right eye right corner
        image_points.push_back(cv::Point2d(leftMouthCorner.x(), leftMouthCorner.y()));    // Left Mouth corner
        image_points.push_back(cv::Point2d(rightMouthCorner.x(), rightMouthCorner.y()));    // Right mouth corner

        std::vector<cv::Point3d> model_points;
        model_points.push_back(cv::Point3d(noseTip.x(), noseTip.y(), noseDepth));    // Nose tip
        model_points.push_back(cv::Point3d(chin.x(), chin.y(), chinDepth));          // Chin
        model_points.push_back(cv::Point3d(leftEyeLeftCorner.x(), leftEyeLeftCorner.y(), leftEyeDepth));    // Left eye left corner
        model_points.push_back(cv::Point3d(rightEyeRightCorner.x(), rightEyeRightCorner.y(), rightEyeDepth));    // Right eye right corner
        model_points.push_back(cv::Point3d(leftMouthCorner.x(), leftMouthCorner.y(), leftMouthDepth));    // Left Mouth corner
        model_points.push_back(cv::Point3d(rightMouthCorner.x(), rightMouthCorner.y(), rightMouthDepth));    // Right mouth corner

        double focal_length = cvImg.cols;
        cv::Point2d center = cv::Point2d(cvImg.cols / 2, cvImg.rows / 2);
        cv::Mat camera_matrix = (cv::Mat_<double>(3, 3) << focal_length, 0, center.x, 0, focal_length, center.y, 0, 0, 1);
        cv::Mat dist_coeffs = cv::Mat::zeros(4, 1, cv::DataType<double>::type); // Assuming no lens distortion

        cv::Mat rotation_vector;
        cv::Mat translation_vector;

        cv::solvePnP(model_points, image_points, camera_matrix, dist_coeffs, rotation_vector, translation_vector);

        // Convert rotation vector to rotation matrix
        cv::Mat rotation_matrix;
        cv::Rodrigues(rotation_vector, rotation_matrix);

        // Extract Euler angles from the rotation matrix
        cv::Vec3d euler_angles;
        cv::Mat R;
        cv::transpose(rotation_matrix, R);
        euler_angles[0] = atan2(R.at<double>(2,1), R.at<double>(2,2));
        euler_angles[1] = atan2(-R.at<double>(2,0), sqrt(R.at<double>(2,1)*R.at<double>(2,1) + R.at<double>(2,2)*R.at<double>(2,2)));
        euler_angles[2] = atan2(R.at<double>(1,0), R.at<double>(0,0));

        // Convert to degrees
        euler_angles *= (180.0 / CV_PI);

        // Print Euler angles in degrees
        NSLog(@"Euler Angles (degrees): Pitch: %f, Yaw: %f, Roll: %f", euler_angles[0], euler_angles[1], euler_angles[2]);

        // Project a 3D point (0, 0, 1000.0) onto the image plane.
        std::vector<cv::Point3d> nose_end_point3D;
        std::vector<cv::Point2d> nose_end_point2D;
        nose_end_point3D.push_back(cv::Point3d(0, 0, 1000.0));
        
        cv::projectPoints(nose_end_point3D, rotation_vector, translation_vector, camera_matrix, dist_coeffs, nose_end_point2D);
        
        // Convert image points and nose end point to dlib points
        dlib::point start_point(image_points[0].x, image_points[0].y);
        dlib::point end_point(nose_end_point2D[0].x, nose_end_point2D[0].y);

        // Calculate the distance and step size
        double distance = sqrt(pow(end_point.x() - start_point.x(), 2) + pow(end_point.y() - start_point.y(), 2));
        int num_steps = static_cast<int>(distance / 3); // 3 pixels apart
        double step_x = (end_point.x() - start_point.x()) / num_steps;
        double step_y = (end_point.y() - start_point.y()) / num_steps;

        // Draw the coordinate axes
        std::vector<cv::Point3d> axes_points3D;
        axes_points3D.push_back(cv::Point3d(100, 0, 0)); // X-axis
        axes_points3D.push_back(cv::Point3d(0, 100, 0)); // Y-axis
        axes_points3D.push_back(cv::Point3d(0, 0, 100)); // Z-axis
        
        std::vector<cv::Point2d> axes_points2D;
        cv::projectPoints(axes_points3D, rotation_vector, translation_vector, camera_matrix, dist_coeffs, axes_points2D);

        cv::line(cvImg, image_points[0], axes_points2D[0], cv::Scalar(0, 0, 255), 2); // X-axis in red
        cv::line(cvImg, image_points[0], axes_points2D[1], cv::Scalar(0, 255, 0), 2); // Y-axis in green
        cv::line(cvImg, image_points[0], axes_points2D[2], cv::Scalar(255, 0, 0), 2); // Z-axis in blue

        // Print rotation and translation vectors
        NSLog(@"Rotation Vector: [%f, %f, %f]", rotation_vector.at<double>(0), rotation_vector.at<double>(1), rotation_vector.at<double>(2));
        NSLog(@"Translation Vector: [%f, %f, %f]", translation_vector.at<double>(0), translation_vector.at<double>(1), translation_vector.at<double>(2));

        // Print nose end point
        NSLog(@"Nose End Point 2D: [%f, %f]", nose_end_point2D[0].x, nose_end_point2D[0].y);
        
        // Convert cv::Mat blendedImg to dlib::array2d<dlib::bgr_pixel>
        // VVIP: THIS HAS TO GO ON THE BOTTOM SO THAT DEBUG_OVERLAY SHOWS UP...
        img.set_size(height, width);
        for (int i = 0; i < height; ++i) {
            for (int j = 0; j < width; ++j) {
                cv::Vec3b rgb = blendedImg.at<cv::Vec3b>(i, j);
                img[i][j] = dlib::bgr_pixel(rgb[0], rgb[1], rgb[2]);
            }
        }
        
        // Draw landmarks onto the image
        for (unsigned long k = 0; k < shape.num_parts(); k++) {
            dlib::point p = shape.part(k);
            draw_solid_circle(img, p, 3, dlib::rgb_pixel(0, 255, 255));
        }
        
        for (int i = 0; i < image_points.size(); i++) {
            dlib::point p(image_points[i].x, image_points[i].y);
            draw_solid_circle(img, p, 3, dlib::rgb_pixel(0, 0, 255));
        }

        // Draw circles along the line
        for (int i = 0; i < num_steps; ++i) {
            int x = start_point.x() + step_x * i;
            int y = start_point.y() + step_y * i;
            dlib::point p(x, y);
            draw_solid_circle(img, p, 2, dlib::rgb_pixel(255, 0, 0));
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

+ (float)getDepthValueAtCoordinate:(int)x y:(int)y depthPixelBuffer:(CVPixelBufferRef)depthPixelBuffer {
    size_t depthOffset = y * CVPixelBufferGetBytesPerRow(depthPixelBuffer) + x * sizeof(UInt16); // No flip
    if (depthOffset >= CVPixelBufferGetDataSize(depthPixelBuffer)) {
        return 0.0; // Return a default value if offset is out of bounds
    }
    UInt16 *depthPointer = (UInt16 *)((char *)CVPixelBufferGetBaseAddress(depthPixelBuffer) + depthOffset);
    return (float)(*depthPointer);
}


@end
