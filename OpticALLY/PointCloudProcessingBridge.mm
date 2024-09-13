#import "PointCloudProcessingBridge.h"
#include <open3d/Open3D.h>
#include <opencv2/opencv.hpp>
#import <Vision/Vision.h>
#include <vector>
#import <SceneKit/SceneKit.h>
#include <memory>
#include <numeric>
#include <algorithm>
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
static SCNMatrix4 _rotationMatrix;
static SCNVector3 _translationVector;

@implementation PointCloudProcessingBridge

+ (void)initialize {
    if (self == [PointCloudProcessingBridge self]) {
        _rotationMatrix = SCNMatrix4Identity; // Initialize to identity matrix
        _translationVector = SCNVector3Make(0, 0, 0);
        centroids2DArray = [NSMutableArray array];
    }
}

+ (SCNMatrix4)rotationMatrix {
    return _rotationMatrix;
}

// Implement the translationVector property
+ (SCNVector3)translationVector {
    return _translationVector;
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

    // Convert NSArray to std::vector
    std::vector<std::pair<int, std::string>> numberedImageFiles;
    std::vector<std::pair<int, std::string>> numberedDepthFiles;
    std::vector<std::string> cppOutputPaths;

    auto extractNumber = [](const std::string &filename) -> int {
        std::regex re("\\d+");
        std::smatch match;
        if (std::regex_search(filename, match, re)) {
            return std::stoi(match.str());
        }
        return -1;
    };

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

    // Process each point cloud sequentially
    for (size_t i = 0; i < cppImageFiles.size(); ++i) {
        // Get the corresponding facial landmark points for the current index
        CGPoint noseTip = [noseTipArray[i] CGPointValue];
        CGPoint chin = [chinArray[i] CGPointValue];
        CGPoint leftEyeLeftCorner = [leftEyeLeftCornerArray[i] CGPointValue];
        CGPoint rightEyeRightCorner = [rightEyeRightCornerArray[i] CGPointValue];
        CGPoint leftMouthCorner = [leftMouthCornerArray[i] CGPointValue];
        CGPoint rightMouthCorner = [rightMouthCornerArray[i] CGPointValue];

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
            continue;
        }

        // Retrieve and store centroids
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

        pointClouds.push_back(pointCloud);
    }

    if (pointClouds.empty()) {
        NSLog(@"No valid point clouds generated");
        return NO;
    }
    
    NSMutableArray<NSValue *> *centroidsA = centroids2DArray.count > 0 ? centroids2DArray[0] : nil;
    NSMutableArray<NSValue *> *centroidsB = centroids2DArray.count > 1 ? centroids2DArray[1] : nil;

    // Transformation process for centroids and point cloud
    // The rest of the processing code remains the same as before

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

    [self rigidTransform3DWithMatrixA: &matrixA matrixB: &matrixB rotation: &R translation: &t];

    SCNMatrix4 rotationMatrix = SCNMatrix4Identity;
    rotationMatrix.m11 = R(0, 0);
    rotationMatrix.m12 = R(0, 1);
    rotationMatrix.m13 = R(0, 2);
    rotationMatrix.m21 = R(1, 0);
    rotationMatrix.m22 = R(1, 1);
    rotationMatrix.m23 = R(1, 2);
    rotationMatrix.m31 = R(2, 0);
    rotationMatrix.m32 = R(2, 1);
    rotationMatrix.m33 = R(2, 2);

    // Convert Eigen::Vector3d to SCNVector3
    SCNVector3 translationVector = SCNVector3Make(t.x(), t.y(), t.z());

    // Store these values in the static variables
    _rotationMatrix = rotationMatrix;
    _translationVector = translationVector;
    
    if (centroidsA) {
        // Calculate centroid of centroidsA before transformation
        Eigen::Vector3d originalCentroid(0, 0, 0);
        for (NSUInteger i = 0; i < centroidsA.count; ++i) {
            SCNVector3 pointA = [centroidsA[i] SCNVector3Value];
            originalCentroid += Eigen::Vector3d(pointA.x, pointA.y, pointA.z);
        }
        originalCentroid /= static_cast<double>(centroidsA.count);

        // Apply the transformation to centroidsA and calculate new centroid
        Eigen::Vector3d transformedCentroid(0, 0, 0);
        for (NSUInteger i = 0; i < centroidsA.count; ++i) {
            SCNVector3 pointA = [centroidsA[i] SCNVector3Value];
            Eigen::Vector3d pointVec(pointA.x, pointA.y, pointA.z);
            Eigen::Vector3d transformedPoint = R * pointVec + t;
            SCNVector3 transformedPointA = SCNVector3Make(transformedPoint.x(), transformedPoint.y(), transformedPoint.z());
            centroidsA[i] = [NSValue valueWithSCNVector3:transformedPointA];
            
            // Sum up transformed points to calculate the new centroid
            transformedCentroid += transformedPoint;
        }
        transformedCentroid /= static_cast<double>(centroidsA.count);

        // Calculate movement vector based on the difference in centroids
        Eigen::Vector3d movementVector = transformedCentroid - originalCentroid;

        // Debugging: Print out the transformed centroids and the movement vector
        NSLog(@"Original Centroid: (%f, %f, %f)", originalCentroid.x(), originalCentroid.y(), originalCentroid.z());
        NSLog(@"Transformed Centroid: (%f, %f, %f)", transformedCentroid.x(), transformedCentroid.y(), transformedCentroid.z());
        NSLog(@"Movement Vector: (%f, %f, %f)", movementVector.x(), movementVector.y(), movementVector.z());

        // Right now we're doing below operation within ImageDepth.cpp instead of here, hence I commented out
//        auto& pointCloud = pointClouds[0];
//
//        // Apply the movement vector to all points in the point cloud
//        for (auto& point : pointCloud->points_) {
//            point += movementVector;
//        }
        
        // Get the corresponding facial landmark points for index 0
        CGPoint noseTip0 = [noseTipArray[0] CGPointValue];
        CGPoint chin0 = [chinArray[0] CGPointValue];
        CGPoint leftEyeLeftCorner0 = [leftEyeLeftCornerArray[0] CGPointValue];
        CGPoint rightEyeRightCorner0 = [rightEyeRightCornerArray[0] CGPointValue];
        CGPoint leftMouthCorner0 = [leftMouthCornerArray[0] CGPointValue];
        CGPoint rightMouthCorner0 = [rightMouthCornerArray[0] CGPointValue];

        // Convert CGPoint to cv::Point2f for index 0
        cv::Point2f noseTipCV0 = cv::Point2f(noseTip0.x, noseTip0.y);
        cv::Point2f chinCV0 = cv::Point2f(chin0.x, chin0.y);
        cv::Point2f leftEyeLeftCornerCV0 = cv::Point2f(leftEyeLeftCorner0.x, leftEyeLeftCorner0.y);
        cv::Point2f rightEyeRightCornerCV0 = cv::Point2f(rightEyeRightCorner0.x, rightEyeRightCorner0.y);
        cv::Point2f leftMouthCornerCV0 = cv::Point2f(leftMouthCorner0.x, leftMouthCorner0.y);
        cv::Point2f rightMouthCornerCV0 = cv::Point2f(rightMouthCorner0.x, rightMouthCorner0.y);

        // Initialize the new ImageDepth object with the transformation applied to the first image and depth file
        auto transformedImageDepth = std::make_shared<ImageDepth>(
            [calibrationFilePath UTF8String],
            cppImageFiles[0],       // The first image file
            cppDepthFiles[0],       // The first depth file
            640,                    // Image width (adjust if necessary)
            480,                    // Image height (adjust if necessary)
            0.1,                    // Min depth (adjust if necessary)
            0.5,                    // Max depth (adjust if necessary)
            0.01,                   // Normal radius (adjust if necessary)
            noseTipCV0,              // Nose tip (as cv::Point2f)
            chinCV0,                 // Chin (as cv::Point2f)
            leftEyeLeftCornerCV0,    // Left eye corner (as cv::Point2f)
            rightEyeRightCornerCV0,  // Right eye corner (as cv::Point2f)
            leftMouthCornerCV0,      // Left mouth corner (as cv::Point2f)
            rightMouthCornerCV0,     // Right mouth corner (as cv::Point2f)
            R.cast<float>(),        // Rotation matrix (cast to float if needed)
            t.cast<float>()         // Translation vector (cast to float if needed)
        );

        // Get the transformed point cloud from the new ImageDepth object
        auto transformedPointCloud = transformedImageDepth->getPointCloud();

        if (transformedPointCloud && !transformedPointCloud->points_.empty()) {
            // Replace pointClouds[0] with the transformedPointCloud
            if (!pointClouds.empty()) {
                pointClouds[0] = transformedPointCloud;
            } else {
                // If pointClouds is empty, just add transformedPointCloud to it
                pointClouds.push_back(transformedPointCloud);
            }
            
        } else {
            NSLog(@"Transformed point cloud is empty or invalid.");
        }

    } else {
        NSLog(@"centroidsA is empty or not available.");
    }
    

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

+ (double)computeRMSD:(const Eigen::MatrixXd &)A alignedB:(const Eigen::MatrixXd &)B {
    Eigen::MatrixXd diff = A - B;
    return std::sqrt((diff.array().square().sum()) / A.cols());
}

+ (void)rigidTransform3DWithMatrixA:(Eigen::MatrixXd &)A matrixB:(Eigen::MatrixXd &)B
                           rotation:(Eigen::Matrix3d &)bestR
                         translation:(Eigen::Vector3d &)bestT {
    // Ensure A and B have the same number of columns (points)
    assert(A.cols() == B.cols());
    NSUInteger numPoints = A.cols();
    
    // Define variables for the best alignment
    double bestRMSD = std::numeric_limits<double>::infinity();
    
    // Initialize Eigen Matrix and Vector for the best rotation and translation
    Eigen::Matrix3d bestRotation = Eigen::Matrix3d::Identity();
    Eigen::Vector3d bestTranslation = Eigen::Vector3d::Zero();
    
    // Generate all permutations of points in B (6 permutations for 3 points)
    std::vector<int> indices(numPoints);
    std::iota(indices.begin(), indices.end(), 0); // Fill indices with 0, 1, ..., numPoints - 1

    // Create a matrix to store the permuted version of B
    Eigen::MatrixXd permutedB(3, numPoints);

    do {
        // Re-arrange B using the current permutation of indices
        for (size_t i = 0; i < numPoints; ++i) {
            permutedB.col(i) = B.col(indices[i]);
        }
        
        // Compute centroids of A and permutedB
        Eigen::Vector3d centroidA = A.rowwise().mean();
        Eigen::Vector3d centroidB = permutedB.rowwise().mean();

        // Center the points by subtracting the centroids
        Eigen::MatrixXd centeredA = A.colwise() - centroidA;
        Eigen::MatrixXd centeredB = permutedB.colwise() - centroidB;
        
        // Compute the covariance matrix
        Eigen::Matrix3d H = centeredA * centeredB.transpose();
        
        // Perform Singular Value Decomposition (SVD)
        Eigen::JacobiSVD<Eigen::MatrixXd> svd(H, Eigen::ComputeFullU | Eigen::ComputeFullV);
        Eigen::Matrix3d U = svd.matrixU();
        Eigen::Matrix3d V = svd.matrixV();
        
        // Compute the rotation matrix
        Eigen::Matrix3d R = V * U.transpose();
        
        // Handle reflection case (determinant should be 1, not -1)
        if (R.determinant() < 0) {
            V.col(2) *= -1;
            R = V * U.transpose();
        }
        
        // Compute the translation vector
        Eigen::Vector3d T = centroidB - R * centroidA;

        // Apply the transformation to A
        Eigen::MatrixXd alignedA = (R * A).colwise() + T;
        
        // Compute RMSD between aligned A and the current permutation of B
        // Because function declarations explicitly say void * since importing Eigen in header file is not allowed, make sure to add memory address sign '&' when passing in as params!
        double rmsdValue = [self computeRMSD:&alignedA alignedB:&permutedB];
        
        // Keep track of the best (lowest) RMSD and corresponding rotation/translation
        if (rmsdValue < bestRMSD) {
            bestRMSD = rmsdValue;
            bestRotation = R;
            bestTranslation = T;
        }

    } while (std::next_permutation(indices.begin(), indices.end()));

    // Output the best rotation and translation found
    bestR = bestRotation;
    bestT = bestTranslation;
}


@end
