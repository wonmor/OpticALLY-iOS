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
+ (NSString *)getOpenCVVersion;
+ (UIImage *)grayscaleImg:(UIImage *)image;
+ (UIImage *)resizeImg:(UIImage *)image :(int)width :(int)height :(int)interpolation;
+ (UIImage *)undistortImage:(UIImage *)image withCameraMatrix:(NSArray<NSNumber *> *)cameraMatrix distortionCoefficients:(NSArray<NSNumber *> *)distCoeffs;
@end

NS_ASSUME_NONNULL_END
