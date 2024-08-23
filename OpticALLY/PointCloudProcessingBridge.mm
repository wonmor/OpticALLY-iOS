#import "PointCloudProcessingBridge.h"
#include <open3d/Open3D.h>
#include <opencv2/opencv.hpp>
#import <Vision/Vision.h>
#include <vector>
#import <SceneKit/SceneKit.h>
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

// Static variable declaration
static NSMutableArray<NSMutableArray<NSValue *> *> *centroids2DArray = nil;

@implementation PointCloudProcessingBridge

+ (void)initialize {
    if (self == [PointCloudProcessingBridge self]) {
        centroids2DArray = [NSMutableArray array];
    }
}

+ (NSArray<NSValue *> *)getCentroids2DArrayAtIndex:(NSUInteger)index {
    if (index < centroids2DArray.count) {
        return centroids2DArray[index];
    }
    return nil;
}


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

            // Retrieve and print centroids (inlined version)
            const std::vector<cv::Point3f>& centroids = imageDepth->getCentroids();
            NSMutableArray<NSValue *> *centroidArray = [NSMutableArray arrayWithCapacity:centroids.size()];
            for (const auto &centroid : centroids) {
                SCNVector3 centroidVector = SCNVector3Make(centroid.x, centroid.y, centroid.z);
                [centroidArray addObject:[NSValue valueWithSCNVector3:centroidVector]];
            }

            // Add the centroids to the static array
            [centroids2DArray addObject:centroidArray];
            NSLog(@"Size of centroids2DArray after adding: %lu", (unsigned long)centroids2DArray.count);

            // Print the centroids
            NSUInteger index = 0;
            for (NSValue *centroidValue in centroidArray) {
                SCNVector3 centroid = [centroidValue SCNVector3Value];
                NSLog(@"[POINTCLOUDPROCESSING] Centroid %lu: (%f, %f, %f)", (unsigned long)index, centroid.x, centroid.y, centroid.z);
                index++;
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
    
    NSMutableArray<NSValue *> *centroidsA = centroids2DArray.count > 0 ? centroids2DArray[0] : nil;
    NSMutableArray<NSValue *> *centroidsB = centroids2DArray.count > 1 ? centroids2DArray[1] : nil;


        NSUInteger numPointsA = centroidsA.count;
        NSLog(@"Number of points in centroidsA: %lu", (unsigned long)numPointsA);
        Eigen::MatrixXd matrixA(3, numPointsA);

        for (NSUInteger i = 0; i < numPointsA; ++i) {
            SCNVector3 pointA = [centroidsA[i] SCNVector3Value];
            matrixA(0, i) = pointA.x;
            matrixA(1, i) = pointA.y;
            matrixA(2, i) = pointA.z;
            NSLog(@"centroidsA[%lu] -> SCNVector3(x: %f, y: %f, z: %f)", (unsigned long)i, pointA.x, pointA.y, pointA.z);
        }

        // Print out the matrixA
        std::cout << "Matrix A:\n" << matrixA << std::endl;

        NSUInteger numPointsB = centroidsB.count;
        NSLog(@"Number of points in centroidsB: %lu", (unsigned long)numPointsB);
        Eigen::MatrixXd matrixB(3, numPointsB);

        for (NSUInteger i = 0; i < numPointsB; ++i) {
            SCNVector3 pointB = [centroidsB[i] SCNVector3Value];
            matrixB(0, i) = pointB.x;
            matrixB(1, i) = pointB.y;
            matrixB(2, i) = pointB.z;
            NSLog(@"centroidsB[%lu] -> SCNVector3(x: %f, y: %f, z: %f)", (unsigned long)i, pointB.x, pointB.y, pointB.z);
        }

        // Print out the matrixB
        std::cout << "Matrix B:\n" << matrixB << std::endl;

    Eigen::Matrix3d R;
    Eigen::Vector3d t;

    // Objective-C++ TIPS & TRICKS
    // & means "Method Signature"
    // (It's like a memory address)
    // If your method rigidTransform3DWithMatrixA:matrixB:rotation:translation: expects void* pointers (which is the case if you're trying to avoid including Eigen in the header file), you'll need to pass the address of the Eigen objects.
  [self rigidTransform3DWithMatrixA: &matrixA matrixB: &matrixB rotation: &R translation: &t];
    
    
    
    if (centroidsA) {
        // Iterate over each point in centroidsA and apply the transformation
        for (NSUInteger i = 0; i < centroidsA.count; ++i) {
            // Get the current point as SCNVector3
            SCNVector3 pointA = [centroidsA[i] SCNVector3Value];

            // Convert SCNVector3 to Eigen::Vector3d
            Eigen::Vector3d pointVec(pointA.x, pointA.y, pointA.z);

            // Apply the rotation and translation
            Eigen::Vector3d transformedPoint = R * pointVec + t;

            // Convert the transformed point back to SCNVector3
            SCNVector3 transformedPointA = SCNVector3Make(transformedPoint.x(), transformedPoint.y(), transformedPoint.z());

            // Update the point in centroidsA
            centroidsA[i] = [NSValue valueWithSCNVector3:transformedPointA];
        }

        // Debugging: Print out the transformed centroids
        NSLog(@"Transformed centroids in centroidsA:");
        for (NSUInteger i = 0; i < centroidsA.count; ++i) {
            SCNVector3 transformedPointA = [centroidsA[i] SCNVector3Value];
            NSLog(@"Centroid %lu: (%f, %f, %f)", (unsigned long)i, transformedPointA.x, transformedPointA.y, transformedPointA.z);
        }
    } else {
        NSLog(@"centroidsA is empty or not available.");
    }
    
    // Step 2: Apply the same transformation to pointClouds[0]
    for (auto& point : pointClouds[1]->points_) {
        point = R * point + t;
    }
//
//    // Apply the rigid transformation to each point in pointClouds[0]
//    if (!pointClouds.empty()) {
//        auto& pointCloud = pointClouds[0]; // Assuming pointClouds[0] is the point cloud to transform
//
//        for (auto& point : pointCloud->points_) {
//            // Apply the rotation and translation
//            Eigen::Vector3d pointVec(point.x(), point.y(), point.z());
//            Eigen::Vector3d transformedPoint = R * pointVec + t;
//
//            // Update the point in the point cloud
//            point.x() = transformedPoint.x();
//            point.y() = transformedPoint.y();
//            point.z() = transformedPoint.z();
//        }
//    }

    // Combine all point clouds into a single point cloud
    auto combinedPointCloud = std::make_shared<PointCloud>();
    for (const auto &pointCloud : pointClouds) {
        *combinedPointCloud += *pointCloud;
    }

    // Debugging: Print combined point cloud size
    NSLog(@"Combined point cloud has %lu points", (unsigned long)combinedPointCloud->points_.size());

    // Process the combined point cloud if needed
    size_t depth = 9; // or another appropriate value based on your needs
    float scale = 1.1f;
    bool linear_fit = false; // Set to true if you need linear interpolation

    // Call the Poisson reconstruction with a single thread
    auto [mesh, densities] = open3d::geometry::TriangleMesh::CreateFromPointCloudPoisson(
        *combinedPointCloud,
        depth,
        0,
        scale,
        linear_fit,
        1
    );

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

    fs::path outputFilePath = cppOutputPaths[0];
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

    NSLog(@"Successfully exported OBJ file from combined point cloud.");
    return YES;
}

// Input: expects 3xN matrix of points
// Returns R, t
// R = 3x3 rotation matrix
// t = 3x1 column vector

+ (void)rigidTransform3DWithMatrixA:(Eigen::MatrixXd &)A matrixB:(Eigen::MatrixXd &)B rotation:(Eigen::Matrix3d &)R translation:(Eigen::Vector3d &)t {
    NSCAssert(A.rows() == 3 && B.rows() == 3 && A.cols() == B.cols(), @"Matrices A and B must be 3xN and have the same dimensions");

    int num_cols = static_cast<int>(A.cols());

    // Find mean column-wise
    Eigen::Vector3d centroid_A = A.rowwise().mean();
    Eigen::Vector3d centroid_B = B.rowwise().mean();

    // Subtract mean
    Eigen::MatrixXd Am = A.colwise() - centroid_A;
    Eigen::MatrixXd Bm = B.colwise() - centroid_B;

    Eigen::Matrix3d H = Am * Bm.transpose();

    // Perform SVD
    Eigen::JacobiSVD<Eigen::MatrixXd> svd(H, Eigen::ComputeFullU | Eigen::ComputeFullV);
    Eigen::Matrix3d U = svd.matrixU();
    Eigen::Matrix3d Vt = svd.matrixV().transpose();
    
    R = Vt.transpose() * U.transpose();

    // Special reflection case
    if (R.determinant() < 0) {
        NSLog(@"det(R) < 0, reflection detected! Correcting for it ...");
        Vt.row(2) *= -1;
        R = Vt.transpose() * U.transpose();
    }

    t = -R * centroid_A + centroid_B;
}

+ (SCNVector3)calculateCentroidForPoints:(NSArray<NSValue *> *)points {
    // Initialize variables to accumulate the sum of coordinates
    float sumX = 0.0f;
    float sumY = 0.0f;
    float sumZ = 0.0f;

    // Iterate over the points to accumulate their coordinates
    for (NSValue *value in points) {
        SCNVector3 point = [value SCNVector3Value];
        sumX += point.x;
        sumY += point.y;
        sumZ += point.z;
    }

    // Calculate the average for each coordinate
    NSUInteger pointCount = points.count;
    SCNVector3 centroid = SCNVector3Make(sumX / pointCount, sumY / pointCount, sumZ / pointCount);

    return centroid;
}


@end
