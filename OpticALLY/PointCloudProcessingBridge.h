// PointCloudProcessingBridge.h
// OpticALLY

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface PointCloudProcessingBridge : NSObject

// Exposes a method to Swift that can take all necessary parameters for processing point clouds.
+ (BOOL)processPointCloudsWithCalibrationFile:(NSString *)calibrationFilePath
                                  imageFiles:(NSArray<NSString *> *)imageFiles
                                  depthFiles:(NSArray<NSString *> *)depthFiles
                                  outputPath:(NSString *)outputPath;

@end
