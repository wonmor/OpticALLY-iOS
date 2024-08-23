#import "PointCloudProcessingBridge.h"
#include <open3d/Open3D.h>
#include <opencv2/opencv.hpp>
#import <Vision/Vision.h>
#include <vector>
#include <memory>
#include <fstream>
#include <Eigen/Dense>
#include <filesystem>
#include <regex>
#include <future>
#import <UIKit/UIKit.h>
#import "ImageDepth.hpp"

// Function to get texture images from a TriangleMesh
std::vector<open3d::geometry::Image> GetTextureImages(const open3d::geometry::TriangleMesh &mesh) {
    std::vector<open3d::geometry::Image> texture_images;
    if (mesh.textures_.empty()) {
        std::cerr << "No textures found in the mesh." << std::endl;
        return texture_images;
    }

    for (const auto &texture : mesh.textures_) {
        texture_images.push_back(texture);
    }

    return texture_images;
}

@implementation PointCloudProcessingBridge

+ (BOOL)processPointCloudsWithCalibrationFile:(NSString *)calibrationFilePath
                                   imageFiles:(NSArray<NSString *> *)imageFiles
                                   depthFiles:(NSArray<NSString *> *)depthFiles
                                  outputPaths:(NSArray<NSString *> *)outputPaths
                                 noseTipArray:(NSArray<NSValue *> *)noseTipArray
                                    chinArray:(NSArray<NSValue *> *)chinArray
                          leftEyeLeftCornerArray:(NSArray<NSValue *> *)leftEyeLeftCornerArray
                         rightEyeRightCornerArray:(NSArray<NSValue *> *)rightEyeRightCornerArray
                          leftMouthCornerArray:(NSArray<NSValue *> *)leftMouthCornerArray
                         rightMouthCornerArray:(NSArray<NSValue *> *)rightMouthCornerArray {

    using namespace open3d;
    using namespace geometry;
    namespace fs = std::filesystem;
    
    NSLog(@"Image files count: %lu", (unsigned long)imageFiles.count);
    NSLog(@"Depth files count: %lu", (unsigned long)depthFiles.count);
    NSLog(@"Output paths count: %lu", (unsigned long)outputPaths.count);

    // Print counts for each facial landmark array
    NSLog(@"Nose Tip Array count: %lu", (unsigned long)noseTipArray.count);
    NSLog(@"Chin Array count: %lu", (unsigned long)chinArray.count);
    NSLog(@"Left Eye Left Corner Array count: %lu", (unsigned long)leftEyeLeftCornerArray.count);
    NSLog(@"Right Eye Right Corner Array count: %lu", (unsigned long)rightEyeRightCornerArray.count);
    NSLog(@"Left Mouth Corner Array count: %lu", (unsigned long)leftMouthCornerArray.count);
    NSLog(@"Right Mouth Corner Array count: %lu", (unsigned long)rightMouthCornerArray.count);

    for (NSUInteger i = 0; i < imageFiles.count; i++) {
        NSString *imageFile = imageFiles[i];
        NSString *depthFile = depthFiles[i];
        NSString *outputPath = outputPaths[i];

        CGPoint noseTip = [noseTipArray[i] CGPointValue];
        CGPoint chin = [chinArray[i] CGPointValue];
        CGPoint leftEyeLeftCorner = [leftEyeLeftCornerArray[i] CGPointValue];
        CGPoint rightEyeRightCorner = [rightEyeRightCornerArray[i] CGPointValue];
        CGPoint leftMouthCorner = [leftMouthCornerArray[i] CGPointValue];
        CGPoint rightMouthCorner = [rightMouthCornerArray[i] CGPointValue];

        NSLog(@"[POINTCLOUDPROCESSING][Index %lu] Nose Tip: %@", (unsigned long)i, NSStringFromCGPoint(noseTip));
        NSLog(@"[POINTCLOUDPROCESSING][Index %lu] Chin: %@", (unsigned long)i, NSStringFromCGPoint(chin));
        NSLog(@"[POINTCLOUDPROCESSING][Index %lu] Left Eye Left Corner: %@", (unsigned long)i, NSStringFromCGPoint(leftEyeLeftCorner));
        NSLog(@"[POINTCLOUDPROCESSING][Index %lu] Right Eye Right Corner: %@", (unsigned long)i, NSStringFromCGPoint(rightEyeRightCorner));
        NSLog(@"[POINTCLOUDPROCESSING][Index %lu] Left Mouth Corner: %@", (unsigned long)i, NSStringFromCGPoint(leftMouthCorner));
        NSLog(@"[POINTCLOUDPROCESSING][Index %lu] Right Mouth Corner: %@", (unsigned long)i, NSStringFromCGPoint(rightMouthCorner));

        // Add more
    }

    // Helper function to extract numeric part from filename
    auto extractNumber = [](const std::string &filename) -> int {
        std::regex re("\\d+");
        std::smatch match;
        if (std::regex_search(filename, match, re)) {
            return std::stoi(match.str());
        }
        return -1;
    };

    // Convert NSArray to std::vector
    std::vector<std::pair<int, std::string>> numberedImageFiles;
    std::vector<std::pair<int, std::string>> numberedDepthFiles;
    std::vector<std::string> cppOutputPaths;

    for (NSString *path in imageFiles) {
        std::string stdPath = [path UTF8String];
        int number = extractNumber(stdPath);
        numberedImageFiles.emplace_back(number, stdPath);
    }

    for (NSString *path in depthFiles) {
        std::string stdPath = [path UTF8String];
        int number = extractNumber(stdPath);
        numberedDepthFiles.emplace_back(number, stdPath);
    }

    for (NSString *path in outputPaths) {
        std::string stdPath = [path UTF8String];
        cppOutputPaths.push_back(stdPath);
    }

    // Sort based on the extracted number
    std::sort(numberedImageFiles.begin(), numberedImageFiles.end());
    std::sort(numberedDepthFiles.begin(), numberedDepthFiles.end());

    // Extract sorted paths
    std::vector<std::string> cppImageFiles;
    std::vector<std::string> cppDepthFiles;

    for (const auto &pair : numberedImageFiles) {
        cppImageFiles.push_back(pair.second);
    }

    for (const auto &pair : numberedDepthFiles) {
        cppDepthFiles.push_back(pair.second);
    }

    if (cppImageFiles.empty() || cppDepthFiles.empty() || cppOutputPaths.empty()) {
        NSLog(@"No image, depth files or output paths found");
        return NO;
    }

    if (cppImageFiles.size() != cppDepthFiles.size() || cppImageFiles.size() != cppOutputPaths.size()) {
        NSLog(@"Mismatch between the number of image files, depth files, and output paths");
        return NO;
    }

    std::vector<std::shared_ptr<PointCloud>> pointClouds;

    // Print out the lengths of the arrays
    NSLog(@"Number of image files: %lu", (unsigned long)imageFiles.count);
    NSLog(@"Number of depth files: %lu", (unsigned long)depthFiles.count);
    NSLog(@"Number of output paths: %lu", (unsigned long)outputPaths.count);

    std::vector<std::future<std::shared_ptr<PointCloud>>> futures;

    // Process each point cloud in parallel
    for (size_t i = 0; i < cppImageFiles.size(); ++i) {
        // Get the corresponding facial landmark points for the current index
        CGPoint noseTip = [noseTipArray[i] CGPointValue];
        CGPoint chin = [chinArray[i] CGPointValue];
        CGPoint leftEyeLeftCorner = [leftEyeLeftCornerArray[i] CGPointValue];
        CGPoint rightEyeRightCorner = [rightEyeRightCornerArray[i] CGPointValue];
        CGPoint leftMouthCorner = [leftMouthCornerArray[i] CGPointValue];
        CGPoint rightMouthCorner = [rightMouthCornerArray[i] CGPointValue];
        
        // Create a future for each point cloud processing task
        futures.push_back(std::async(std::launch::async, [calibrationFilePath, cppImageFiles, cppDepthFiles, i, noseTip, chin, leftEyeLeftCorner, rightEyeRightCorner, leftMouthCorner, rightMouthCorner]() -> std::shared_ptr<PointCloud> {
            // Convert CGPoint to cv::Point2f
            cv::Point2f noseTipCV = cv::Point2f(noseTip.x, noseTip.y);
            cv::Point2f chinCV = cv::Point2f(chin.x, chin.y);
            cv::Point2f leftEyeLeftCornerCV = cv::Point2f(leftEyeLeftCorner.x, leftEyeLeftCorner.y);
            cv::Point2f rightEyeRightCornerCV = cv::Point2f(rightEyeRightCorner.x, rightEyeRightCorner.y);
            cv::Point2f leftMouthCornerCV = cv::Point2f(leftMouthCorner.x, leftMouthCorner.y);
            cv::Point2f rightMouthCornerCV = cv::Point2f(rightMouthCorner.x, rightMouthCorner.y);

            // Initialize the ImageDepth object with the calibration file, image, depth file, and additional parameters
            auto imageDepth = std::make_shared<ImageDepth>(
                [calibrationFilePath UTF8String],
                cppImageFiles[i],
                cppDepthFiles[i],
                640,
                480,
                0.1,
                0.5,
                0.01,
                noseTipCV,   // Pass the converted cv::Point2f
                chinCV,      // Pass the converted cv::Point2f
                leftEyeLeftCornerCV,  // Pass the converted cv::Point2f
                rightEyeRightCornerCV, // Pass the converted cv::Point2f
                leftMouthCornerCV,  // Pass the converted cv::Point2f
                rightMouthCornerCV  // Pass the converted cv::Point2f
            );

            // Get the point cloud from the ImageDepth object
            auto pointCloud = imageDepth->getPointCloud();
            if (!pointCloud || pointCloud->points_.empty()) {
                return nullptr;
            }

            // Retrieve and print centroids
            NSArray<NSValue *> *centroids = [PointCloudProcessingBridge retrieveCentroidsForImageDepth:imageDepth.get()];

            // Print the centroids
            for (NSValue *centroidValue in centroids) {
                SCNVector3 centroid = [centroidValue SCNVector3Value];
                NSLog(@"[POINTCLOUDPROCESSING] Centroid: (%f, %f, %f)", centroid.x, centroid.y, centroid.z);
            }

            return pointCloud;
        }));
    }
    
    // Collect all point clouds
    for (auto &f : futures) {
        auto pointCloud = f.get();
        if (pointCloud && !pointCloud->IsEmpty()) {
            pointClouds.push_back(pointCloud);
        }
    }

    if (pointClouds.empty()) {
        NSLog(@"No valid point clouds generated");
        return NO;
    }

    size_t depth = 9; // or another appropriate value based on your needs
    float scale = 1.1f;
    bool linear_fit = false; // Set to true if you need linear interpolation

    for (size_t i = 0; i < pointClouds.size(); ++i) {
        auto pointCloud = pointClouds[i];

        // Call the Poisson reconstruction with a single thread
        auto [mesh, densities] = open3d::geometry::TriangleMesh::CreateFromPointCloudPoisson(
            *pointCloud,
            depth,
            0,      // Width is ignored if depth is set
            scale,
            linear_fit,
            1       // Setting n_threads to 1 (VERY IMPORTANT)
        ); // VVIP: FORCE THREAD COUNT TO 1 TO PREVENT "FAILED CLOSING THE LOOP" ERROR!

        const double threshold = 0.004893;
        std::cout << "Remove artifacts and large triangles generated by screened Poisson" << std::endl;

        std::vector<bool> trianglesToRemove(mesh->triangles_.size(), false);
        for (size_t j = 0; j < mesh->triangles_.size(); ++j) {
            auto& tri = mesh->triangles_[j];
            double edgeLengths[3] = {
                (mesh->vertices_[tri[0]] - mesh->vertices_[tri[1]]).norm(),
                (mesh->vertices_[tri[1]] - mesh->vertices_[tri[2]]).norm(),
                (mesh->vertices_[tri[2]] - mesh->vertices_[tri[0]]).norm()
            };
            if (edgeLengths[0] > threshold || edgeLengths[1] > threshold || edgeLengths[2] > threshold) {
                trianglesToRemove[j] = true;
            }
        }

        mesh->RemoveTrianglesByMask(trianglesToRemove);
        mesh->RemoveUnreferencedVertices();
        mesh->RemoveNonManifoldEdges();

        std::cout << "Now exporting OBJ..." << std::endl;

        fs::path outputFilePath = cppOutputPaths[i];
        if (!fs::exists(outputFilePath.parent_path())) {
            std::cerr << "Output directory does not exist: " << outputFilePath.parent_path() << std::endl;
            return NO;
        }

        std::cout << "Mesh has " << mesh->vertices_.size() << " vertices and " << mesh->triangles_.size() << " triangles." << std::endl;
        if (mesh->vertices_.empty() || mesh->triangles_.empty()) {
            NSLog(@"Mesh is empty, cannot write to file.");
            return NO;
        }

        try {
            if (!io::WriteTriangleMesh(outputFilePath.string(), *mesh, false)) {
                NSLog(@"Failed to write OBJ file");
                return NO;
            }
        } catch (const std::exception &e) {
            std::cerr << "Exception occurred while writing OBJ file: " << e.what() << std::endl;
            return NO;
        }

        // Extract texture images from the mesh
        std::vector<open3d::geometry::Image> textureImages = GetTextureImages(*mesh);
        for (size_t j = 0; j < textureImages.size(); ++j) {

        }
    }

    NSLog(@"Successfully exported OBJ files.");

    return YES;
}

- (UIImage *)convertOpen3DImageToUIImage:(const open3d::geometry::Image &)open3dImage {
    int width = open3dImage.width_;
    int height = open3dImage.height_;
    int bytesPerPixel = 4; // Assuming RGBA format

    // Create a CGImage from Open3D image data
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, open3dImage.data_.data(), width * height * bytesPerPixel, NULL);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImage = CGImageCreate(width, height, 8, 32, width * bytesPerPixel, colorSpace, kCGBitmapByteOrderDefault, provider, NULL, NO, kCGRenderingIntentDefault);

    UIImage *uiImage = [UIImage imageWithCGImage:cgImage];

    // Release the created resources
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(cgImage);
    CGDataProviderRelease(provider);

    return uiImage;
}

- (void)saveUIImage:(UIImage *)image toPath:(NSString *)path {
    NSData *imageData = UIImageJPEGRepresentation(image, 1.0);
    if (![imageData writeToFile:path atomically:YES]) {
        NSLog(@"Failed to save image at path: %@", path);
    }
}

+ (NSArray<NSValue *> *)retrieveCentroidsForImageDepth:(ImageDepth *)imageDepth {
    // Get the centroids from the ImageDepth instance
    const std::vector<cv::Point3f>& centroids = imageDepth->getCentroids();
    
    // Convert the centroids to an NSArray of NSValue objects
    NSMutableArray<NSValue *> *centroidArray = [NSMutableArray arrayWithCapacity:centroids.size()];
    for (const auto &centroid : centroids) {
        SCNVector3 centroidVector = SCNVector3Make(centroid.x, centroid.y, centroid.z);
        [centroidArray addObject:[NSValue valueWithSCNVector3:centroidVector]];
    }
    
    return centroidArray;
}


@end
