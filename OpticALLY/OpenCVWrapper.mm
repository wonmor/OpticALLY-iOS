//
//  OpenCVWrapper.m
//  OpticALLY
//
//  Created by John Seong on 2/9/24.
//

#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>
#import "OpenCVWrapper.h"

/*
 * add a method convertToMat to UIImage class
 */
@interface UIImage (OpenCVWrapper)
- (void)convertToMat: (cv::Mat *)pMat: (bool)alphaExists;
@end

@implementation UIImage (OpenCVWrapper)

- (void)convertToMat: (cv::Mat *)pMat: (bool)alphaExists {
    if (self.imageOrientation == UIImageOrientationRight) {
        /*
         * When taking picture in portrait orientation,
         * convert UIImage to OpenCV Matrix in landscape right-side-up orientation,
         * and then rotate OpenCV Matrix to portrait orientation
         */
        UIImageToMat([UIImage imageWithCGImage:self.CGImage scale:1.0 orientation:UIImageOrientationUp], *pMat, alphaExists);
        cv::rotate(*pMat, *pMat, cv::ROTATE_90_CLOCKWISE);
    } else if (self.imageOrientation == UIImageOrientationLeft) {
        /*
         * When taking picture in portrait upside-down orientation,
         * convert UIImage to OpenCV Matrix in landscape right-side-up orientation,
         * and then rotate OpenCV Matrix to portrait upside-down orientation
         */
        UIImageToMat([UIImage imageWithCGImage:self.CGImage scale:1.0 orientation:UIImageOrientationUp], *pMat, alphaExists);
        cv::rotate(*pMat, *pMat, cv::ROTATE_90_COUNTERCLOCKWISE);
    } else {
        /*
         * When taking picture in landscape orientation,
         * convert UIImage to OpenCV Matrix directly,
         * and then ONLY rotate OpenCV Matrix for landscape left-side-up orientation
         */
        UIImageToMat(self, *pMat, alphaExists);
        if (self.imageOrientation == UIImageOrientationDown) {
            cv::rotate(*pMat, *pMat, cv::ROTATE_180);
        }
    }
}
@end

@implementation OpenCVWrapper

+ (NSString *)getOpenCVVersion {
    return [NSString stringWithFormat:@"OpenCV Version %s",  CV_VERSION];
}

+ (UIImage *)undistortDepthMap:(UIImage *)depthMapImage mapX:(cv::Mat)mapX mapY:(cv::Mat)mapY {
    cv::Mat depthMap;
    UIImageToMat(depthMapImage, depthMap, true); // Assuming depth map is in grayscale

    cv::Mat undistortedDepthMap;
    cv::remap(depthMap, undistortedDepthMap, mapX, mapY, cv::INTER_LINEAR);

    return MatToUIImage(undistortedDepthMap);
}

+ (UIImage *)processImage:(UIImage *)image withMapX:(cv::Mat)mapX mapY:(cv::Mat)mapY {
    cv::Mat src;
    [image convertToMat:&src :false]; // Convert UIImage to cv::Mat without alpha

    // Convert to grayscale
    cv::Mat gray;
    cv::cvtColor(src, gray, cv::COLOR_RGB2GRAY);

    // Undistort the grayscale image
    cv::Mat undistortedGray;
    cv::remap(gray, undistortedGray, mapX, mapY, cv::INTER_LINEAR);

    return MatToUIImage(undistortedGray);
}

+ (UIImage *)undistortImage:(UIImage *)image withCameraMatrix:(NSArray<NSNumber *> *)cameraMatrix distortionCoefficients:(NSArray<NSNumber *> *)distCoeffs {
    cv::Mat src;
    UIImageToMat(image, src);

    // Convert NSArray to cv::Mat
    cv::Mat cameraMat(3, 3, CV_64F);
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < 3; ++j) {
            cameraMat.at<double>(i, j) = [cameraMatrix[i * 3 + j] doubleValue];
        }
    }

    cv::Mat distCoeffsMat(distCoeffs.count, 1, CV_64F);
    for (size_t i = 0; i < distCoeffs.count; ++i) {
        distCoeffsMat.at<double>(i, 0) = [distCoeffs[i] doubleValue];
    }

    cv::Mat dst;
    cv::undistort(src, dst, cameraMat, distCoeffsMat);

    return MatToUIImage(dst);
}

+ (UIImage *)grayscaleImg:(UIImage *)image {
    cv::Mat mat;
    [image convertToMat: &mat :false];
    
    cv::Mat gray;
    
    NSLog(@"channels = %d", mat.channels());

    if (mat.channels() > 1) {
        cv::cvtColor(mat, gray, cv::COLOR_RGB2GRAY);
    } else {
        mat.copyTo(gray);
    }

    UIImage *grayImg = MatToUIImage(gray);
    return grayImg;
}

+ (UIImage *)resizeImg:(UIImage *)image :(int)width :(int)height :(int)interpolation {
    cv::Mat mat;
    [image convertToMat: &mat :false];
    
    if (mat.channels() == 4) {
        [image convertToMat: &mat :true];
    }
    
    NSLog(@"source shape = (%d, %d)", mat.cols, mat.rows);
    
    cv::Mat resized;
    
//    cv::INTER_NEAREST = 0,
//    cv::INTER_LINEAR = 1,
//    cv::INTER_CUBIC = 2,
//    cv::INTER_AREA = 3,
//    cv::INTER_LANCZOS4 = 4,
//    cv::INTER_LINEAR_EXACT = 5,
//    cv::INTER_NEAREST_EXACT = 6,
//    cv::INTER_MAX = 7,
//    cv::WARP_FILL_OUTLIERS = 8,
//    cv::WARP_INVERSE_MAP = 16
    
    cv::Size size = {width, height};
    
    cv::resize(mat, resized, size, 0, 0, interpolation);
    
    NSLog(@"dst shape = (%d, %d)", resized.cols, resized.rows);
    
    UIImage *resizedImg = MatToUIImage(resized);
    
    return resizedImg;

}

@end
