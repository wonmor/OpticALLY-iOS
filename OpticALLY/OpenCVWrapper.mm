//
//  OpenCVWrapper.m
//  OpticALLY
//
//  Created by John Seong on 5/3/24.
//

#import "OpenCVWrapper.h"

#import <opencv2/opencv.hpp>
#import <opencv2/imgcodecs/ios.h>
#import <Foundation/Foundation.h>

@implementation OpenCVWrapper
//- (UIImage *) detectLaneIn: (UIImage *) image {
//    
//    // convert uiimage to mat
//    cv::Mat opencvImage;
//    UIImageToMat(image, opencvImage, true);
//    
//    // convert colorspace to the one expected by the lane detector algorithm (RGB)
//    cv::Mat convertedColorSpaceImage;
//    cv::cvtColor(opencvImage, convertedColorSpaceImage, CV_RGBA2RGB);
//    
//    // Run lane detection
//    LaneDetector laneDetector;
//    cv::Mat imageWithLaneDetected = laneDetector.detect_lane(convertedColorSpaceImage);
//    
//    // convert mat to uiimage and return it to the caller
//    return MatToUIImage(imageWithLaneDetected);
//}

@end
