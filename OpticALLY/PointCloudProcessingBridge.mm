// PointCloudProcessingBridge.mm
// OpticALLY

#import "PointCloudProcessingBridge.h"
#include "PointCloudProcessing.hpp" // Include the C++ header that has the processing function.

@implementation PointCloudProcessingBridge

+ (BOOL)processPointCloudsWithCalibrationFile:(NSString *)calibrationFilePath
                                   imageFiles:(NSArray<NSString *> *)imageFiles
                                   depthFiles:(NSArray<NSString *> *)depthFiles
                                   outputPath:(NSString *)outputPath {
    // Convert NSArray to std::vector because our C++ code expects std::vector
    std::vector<std::string> cppImageFiles;
    for (NSString *path in imageFiles) {
        cppImageFiles.push_back([path UTF8String]);
    }

    std::vector<std::string> cppDepthFiles;
    for (NSString *path in depthFiles) {
        cppDepthFiles.push_back([path UTF8String]);
    }

    // Call the C++ function
    try {
        processPointCloudsToObj([calibrationFilePath UTF8String], cppImageFiles, cppDepthFiles, [outputPath UTF8String]);
    } catch (const std::exception &e) {
        NSLog(@"C++ Exception: %s", e.what());
        return NO; // Return NO in case of failure
    }

    return YES; // Return YES if the processing is successful
}

@end
