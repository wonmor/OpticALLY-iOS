// PointCloudProcessingBridge.h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PointCloudProcessingBridge : NSObject

+ (BOOL)processPointCloudsWithCalibrationFile:(NSString *)calibrationFilePath
                                   imageFiles:(NSArray<NSString *> *)imageFiles
                                   depthFiles:(NSArray<NSString *> *)depthFiles
                                   outputPath:(NSString *)outputPath;

@end

NS_ASSUME_NONNULL_END
