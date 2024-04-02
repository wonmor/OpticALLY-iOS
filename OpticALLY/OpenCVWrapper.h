//
//  OpenCVWrapper.h
//  OpticALLY
//
//  Created by John Seong on 2/9/24.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OpenCVWrapper : NSObject

// Returns the version of OpenCV being used
+ (NSString *)getOpenCVVersion;

// Converts a given image to grayscale
+ (UIImage *)grayscaleImg:(UIImage *)image;

// Resizes a given image to specified width and height using a specified interpolation method
+ (UIImage *)resizeImg:(UIImage *)image width:(int)width height:(int)height interpolation:(int)interpolation;

// Processes an image using mapX and mapY matrices for transformations. Here, we use void* to represent cv::Mat in Objective-C.
+ (UIImage *)processImage:(UIImage *)image withMapX:(void *)mapX mapY:(void *)mapY;

// Undistorts an image using the specified camera matrix and distortion coefficients
+ (UIImage *)undistortImage:(UIImage *)image withCameraMatrix:(NSArray<NSNumber *> *)cameraMatrix distortionCoefficients:(NSArray<NSNumber *> *)distCoeffs;

@end

NS_ASSUME_NONNULL_END
