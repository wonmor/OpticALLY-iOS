#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>

@interface PointCloudProcessingBridge : NSObject

+ (SCNMatrix4)rotationMatrix;
+ (SCNVector3)translationVector;

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

// Function to compute RMSD between two matrices (A and B)
// A and B are expected to be Eigen::MatrixXd*, cast from void*
+ (double)computeRMSD:(void *)A alignedB:(void *)B;

// Function to compute the rigid transformation between two matrices (A and B)
// A and B are expected to be Eigen::MatrixXd*, rotation is Eigen::Matrix3d*, and translation is Eigen::Vector3d*, cast from void*
+ (void)rigidTransform3DWithMatrixA:(void *)A
                           matrixB:(void *)B
                          rotation:(void *)rotation
                       translation:(void *)translation;

@end
