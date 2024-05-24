// ImageDepth.cpp
// OpticALLY

#include "ImageDepth.hpp"
#include <iostream>
#include <fstream>
#include <nlohmann/json.hpp>
#include "cppcodec/base64_rfc4648.hpp"
#include <open3d/geometry/PointCloud.h>
#include <open3d/geometry/KDTreeSearchParam.h>

// Constructor implementation
ImageDepth::ImageDepth(const std::string& calibration_file, const std::string& image_file, const std::string& depth_file,
                       int width, int height, float min_depth, float max_depth, float normal_radius)
    : image_file(image_file), calibration_file(calibration_file), depth_file(depth_file),
      width(width), height(height), min_depth(min_depth), max_depth(max_depth), normal_radius(normal_radius) {
    pose = Eigen::Matrix4f::Identity();
    loadCalibration(calibration_file);
    createUndistortionLookup();
    loadImage(image_file);
    loadDepth(depth_file);
    createPointCloud(depth_map_undistort, cv::Mat());
}

std::shared_ptr<open3d::geometry::PointCloud> ImageDepth::getPointCloud() {
    return pointCloud;
}

void ImageDepth::loadCalibration(const std::string& file) {
    std::ifstream ifs(file);
    if (!ifs.is_open()) {
        std::cerr << "Error opening calibration file." << std::endl;
        return;
    }

    nlohmann::json data;
    ifs >> data;

    auto lensDistortionLookupBase64 = data["lensDistortionLookup"].get<std::string>();
    auto inverseLensDistortionLookupBase64 = data["inverseLensDistortionLookup"].get<std::string>();
    auto lensDistortionLookupBytes = cppcodec::base64_rfc4648::decode(lensDistortionLookupBase64);
    auto inverseLensDistortionLookupBytes = cppcodec::base64_rfc4648::decode(inverseLensDistortionLookupBase64);

    lensDistortionLookup.resize(lensDistortionLookupBytes.size() / sizeof(float));
    inverseLensDistortionLookup.resize(inverseLensDistortionLookupBytes.size() / sizeof(float));
    std::memcpy(lensDistortionLookup.data(), lensDistortionLookupBytes.data(), lensDistortionLookupBytes.size());
    std::memcpy(inverseLensDistortionLookup.data(), inverseLensDistortionLookupBytes.data(), inverseLensDistortionLookupBytes.size());

    intrinsic = Eigen::Map<Eigen::Matrix<float, 3, 3, Eigen::RowMajor>>(data["intrinsic"].get<std::vector<float>>().data());

    float scale = static_cast<float>(width) / data["intrinsicReferenceDimensionWidth"].get<int>();
    intrinsic(0, 0) *= scale;
    intrinsic(1, 1) *= scale;
    intrinsic(0, 2) *= scale;
    intrinsic(1, 2) *= scale;
}

void ImageDepth::createUndistortionLookup() {
    std::vector<Eigen::Vector2f> xy_pos;
            xy_pos.reserve(width * height);

            for (int y = 0; y < height; ++y) {
                for (int x = 0; x < width; ++x) {
                    xy_pos.emplace_back(static_cast<float>(x), static_cast<float>(y));
                }
            }

            Eigen::MatrixXf xy(xy_pos.size(), 2);
            for (size_t i = 0; i < xy_pos.size(); ++i) {
                xy.row(i) = xy_pos[i];
            }

            // Subtract center
            Eigen::Vector2f center = intrinsic.block<2, 1>(0, 2);
            xy.rowwise() -= center.transpose();

            // Calculate radius from center
            Eigen::VectorXf r = (xy.array().square().rowwise().sum()).sqrt();

            // Normalize radius
            float max_r = r.maxCoeff();
            Eigen::VectorXf norm_r = r / max_r;

            // Interpolate the scale
            int num = inverseLensDistortionLookup.size();
            Eigen::VectorXf table = Eigen::Map<Eigen::VectorXf>(inverseLensDistortionLookup.data(), num);
            Eigen::VectorXf indices = norm_r * static_cast<float>(num - 1);

            // Perform linear interpolation manually
            Eigen::VectorXf scale(indices.size());
            for (int i = 0; i < indices.size(); ++i) {
                int idx = static_cast<int>(indices(i));
                float fraction = indices(i) - idx;
                if (idx + 1 < num) {
                    scale(i) = 1.0f + (table(idx) * (1.0f - fraction) + table(idx + 1) * fraction);
                } else {
                    scale(i) = 1.0f + table(idx); // Handle the case where idx + 1 is out of bounds
                }
            }

            Eigen::MatrixXf new_xy = xy.array().colwise() * scale.array();
            new_xy.rowwise() += center.transpose();

            map_x.create(height, width, CV_32F);
            map_y.create(height, width, CV_32F);

            for (int i = 0; i < height; ++i) {
                for (int j = 0; j < width; ++j) {
                    map_x.at<float>(i, j) = new_xy(i * width + j, 0);
                    map_y.at<float>(i, j) = new_xy(i * width + j, 1);
                }
            }

            // Debug prints
            std::cout << "Remap matrix map_x (first 10 values):\n";
            for (int i = 0; i < 10; ++i) {
                std::cout << map_x.at<float>(i / width, i % width) << " ";
            }
            std::cout << "\n";

            std::cout << "Remap matrix map_y (first 10 values):\n";
            for (int i = 0; i < 10; ++i) {
                std::cout << map_y.at<float>(i / width, i % width) << " ";
            }
            std::cout << "\n";
        }

void ImageDepth::loadImage(const std::string& file) {
        std::cout << "Loading " << file << std::endl;
        // Load image file
        std::vector<uint8_t> buffer(width * height * 4);
        std::ifstream fileStream(file, std::ios::binary);
        fileStream.read(reinterpret_cast<char*>(buffer.data()), buffer.size());
        fileStream.close();

        // Reshape and convert image
        cv::Mat img(height, width, CV_8UC4, buffer.data());
        img = img(cv::Rect(0, 0, width, height)).clone(); // Extract 3 channels
        cv::cvtColor(img, img, cv::COLOR_BGRA2BGR); // Remove alpha and swap RB

    // Convert image from sRGB to linear space
           img_linear = img.clone();
           img_linear.convertTo(img_linear, CV_32F, 1.0 / 255.0);

           srgbToLinear(img_linear);

           // Debug print for the linear image
           std::cout << "Linear image (first 10 values): [";
           for (int i = 0; i < 10; ++i) {
               int y = i / img_linear.cols;
               int x = i % img_linear.cols;
               cv::Vec3f pixel = img_linear.at<cv::Vec3f>(y, x);
               std::cout << pixel[2] << ", " << pixel[1] << ", " << pixel[0];
               if (i < 9) std::cout << ", ";
           }
           std::cout << "]" << std::endl;
    
           std::cout << "map_x (first 10 values): ";
           for (int i = 0; i < 10 && i < map_x.total(); ++i) {
               std::cout << map_x.at<float>(i) << " ";
           }
           std::cout << std::endl;

           std::cout << "map_y (first 10 values): ";
           for (int i = 0; i < 10 && i < map_y.total(); ++i) {
               std::cout << map_y.at<float>(i) << " ";
           }
           std::cout << std::endl;

           // Undistort image
           cv::Mat img_undistort;
            // Convert linear space image to 8-bit
            cv::Mat img_temp;
            img_linear.convertTo(img_temp, CV_8UC1, 255.0);

            // Remap to undistort
            cv::remap(img_temp, img_undistort, map_x, map_y, cv::INTER_LINEAR);

            // Debug print
            std::vector<uchar> flattened(img_undistort.begin<uchar>(), img_undistort.end<uchar>());
            std::cout << "Undistorted image (first 10 values): ";
            for (int i = 0; i < 10 && i < flattened.size(); ++i) {
                std::cout << static_cast<int>(flattened[i]) << " ";
            }
           std::cout << std::endl;
       }
    


void ImageDepth::srgbToLinear(cv::Mat& img) {
    img.forEach<cv::Vec3f>([](cv::Vec3f& pixel, const int* position) -> void {
        for (int i = 0; i < 3; ++i) {
            float& channel = pixel[i];
            if (channel <= 0.04045f) {
                channel = channel / 12.92f;
            } else {
                channel = pow((channel + 0.055f) / 1.055f, 2.4f);
            }
        }
    });
}


void ImageDepth::loadDepth(const std::string& file) {
    std::cout << "Loading depth file: " << file << std::endl;
    std::ifstream ifs(file, std::ios::binary);
    if (!ifs.is_open()) {
        std::cerr << "Failed to open depth file: " << file << std::endl;
        return;
    }

    std::vector<uint16_t> depth_data((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
    depth_map = cv::Mat(height, width, CV_16UC1, depth_data.data());

    depth_map_undistort = cv::Mat();
    
    std::cout << "Remapping depth map..." << std::endl;
    cv::remap(depth_map, depth_map_undistort, map_x, map_y, cv::INTER_NEAREST);
}

void ImageDepth::createPointCloud(const cv::Mat& depth_map, const cv::Mat& mask) {
    std::cout << "Creating point cloud..." << std::endl;
    pointCloud = std::make_shared<open3d::geometry::PointCloud>();
    std::vector<Eigen::Vector3d> points;
    std::vector<Eigen::Vector3d> colors;

    for (int y = 0; y < depth_map.rows; ++y) {
        for (int x = 0; x < depth_map.cols; ++x) {
            if (mask.empty() || mask.at<uint8_t>(y, x) != 0) {
                float z = static_cast<float>(depth_map.at<uint16_t>(y, x)) * 0.001f; // scale factor for depth
                if (z < min_depth || z > max_depth) continue;

                Eigen::Vector3d pt(
                    (x - intrinsic(0, 2)) * z / intrinsic(0, 0),
                    (y - intrinsic(1, 2)) * z / intrinsic(1, 1),
                    z
                );
                points.push_back(pt);

                cv::Vec3f color = img_undistort.at<cv::Vec3f>(y, x);
                colors.push_back(Eigen::Vector3d(color[0], color[1], color[2]));
            }
        }
    }

    pointCloud->points_ = points;
    pointCloud->colors_ = colors;

    // Calculate normals
    pointCloud->EstimateNormals(
        open3d::geometry::KDTreeSearchParamHybrid(normal_radius, 30)
    );
    pointCloud->OrientNormalsTowardsCameraLocation();
}
