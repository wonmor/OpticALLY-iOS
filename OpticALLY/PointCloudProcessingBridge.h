#import <Foundation/Foundation.h>

@interface PointCloudProcessingBridge : NSObject

+ (BOOL)processPointCloudsWithCalibrationFile:(NSString *)calibrationFilePath
                                   imageFiles:(NSArray<NSString *> *)imageFiles
                                   depthFiles:(NSArray<NSString *> *)depthFiles
                                  outputPaths:(NSArray<NSString *> *)outputPaths
                                      noseTip:(CGPoint)noseTip
                                         chin:(CGPoint)chin
                              leftEyeLeftCorner:(CGPoint)leftEyeLeftCorner
                             rightEyeRightCorner:(CGPoint)rightEyeRightCorner
                              leftMouthCorner:(CGPoint)leftMouthCorner
                             rightMouthCorner:(CGPoint)rightMouthCorner;

@end
