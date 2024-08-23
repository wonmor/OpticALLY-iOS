#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>

@interface PointCloudProcessingBridge : NSObject

+ (NSArray<NSValue *> *)getCentroids2DArrayAtIndex:(NSUInteger)index;

+ (BOOL)processPointCloudsWithCalibrationFile:(NSString *)calibrationFilePath
                                   imageFiles:(NSArray<NSString *> *)imageFiles
                                   depthFiles:(NSArray<NSString *> *)depthFiles
                                  outputPaths:(NSArray<NSString *> *)outputPaths
                                 noseTipArray:(NSArray<NSValue *> *)noseTipArray
                                    chinArray:(NSArray<NSValue *> *)chinArray
                          leftEyeLeftCornerArray:(NSArray<NSValue *> *)leftEyeLeftCornerArray
                         rightEyeRightCornerArray:(NSArray<NSValue *> *)rightEyeRightCornerArray
                          leftMouthCornerArray:(NSArray<NSValue *> *)leftMouthCornerArray
                         rightMouthCornerArray:(NSArray<NSValue *> *)rightMouthCornerArray;

// MAKE SURE YOU ADD "PLUS" SIGN IN FRONT OF FUNCTIONS FOR IT TO ACCESSIBLE BY OTHER "+" FUNCTIONS...
+ (SCNVector3)calculateCentroidForPoints:(NSArray<NSValue *> *)points;

+ (void)rigidTransform3DWithMatrixA:(void *)A
                            matrixB:(void *)B
                           rotation:(void *)R
                        translation:(void *)t;

@end
