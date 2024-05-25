// ImageDepth.cpp
// OpticALLY

#include "ImageDepth.hpp"
#include <algorithm>
#include <iostream>
#include <fstream>
#include <nlohmann/json.hpp>
#include "cppcodec/base64_rfc4648.hpp"
#include <open3d/geometry/PointCloud.h>
#include <open3d/geometry/KDTreeSearchParam.h>
#include "base64.hpp"

using json = nlohmann::json;
using namespace Eigen;

// Linear interpolation function
double interpolate(double x, const std::vector<double>& xp, const std::vector<double>& fp) {
    auto it = std::upper_bound(xp.begin(), xp.end(), x);
    if (it == xp.begin()) {
        return fp.front();
    }
    if (it == xp.end()) {
        return fp.back();
    }

    int idx = it - xp.begin();
    double x0 = xp[idx - 1];
    double x1 = xp[idx];
    double y0 = fp[idx - 1];
    double y1 = fp[idx];

    return y0 + (x - x0) * (y1 - y0) / (x1 - x0);
}

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

std::vector<float> bytes_to_floats(const std::vector<BYTE>& bytes) {
        std::vector<float> floats(bytes.size() / 4);
        for (size_t i = 0; i < bytes.size(); i += 4) {
            float value;
            std::memcpy(&value, &bytes[i], 4);
            floats[i / 4] = value;
        }
        return floats;
    }

void ImageDepth::loadCalibration(const std::string& file) {
    std::ifstream ifs(file);
           if (!ifs.is_open()) {
               std::cerr << "Error: Could not open file " << file << std::endl;
               return;
           }

           json data;
           ifs >> data;
           ifs.close();

           std::string lensDistortionLookupBase64 = data["lensDistortionLookup"];
           std::string inverseLensDistortionLookupBase64 = data["inverseLensDistortionLookup"];
           
           std::vector<BYTE> lensDistortionLookupBytes = base64_decode(lensDistortionLookupBase64);
           std::vector<BYTE> inverseLensDistortionLookupBytes = base64_decode(inverseLensDistortionLookupBase64);

           lensDistortionLookup = bytes_to_floats(lensDistortionLookupBytes);
           inverseLensDistortionLookup = bytes_to_floats(inverseLensDistortionLookupBytes);

           // Debug prints
           std::cout << "Lens Distortion Lookup: ";
           for (const auto& value : lensDistortionLookup) std::cout << value << " ";
           std::cout << std::endl;

           std::cout << "Inverse Lens Distortion Lookup: ";
           for (const auto& value : inverseLensDistortionLookup) std::cout << value << " ";
           std::cout << std::endl;

            std::vector<double> intrinsic_data = data["intrinsic"];

            // Create an Eigen matrix and fill it with the intrinsic data
            for (int i = 0; i < 3; ++i) {
                for (int j = 0; j < 3; ++j) {
                    intrinsic(i, j) = intrinsic_data[i * 3 + j];
                }
            }

            // Transpose the matrix
            intrinsic.transposeInPlace();

           // Debug print
           std::cout << "Intrinsic Matrix before scaling:\n" << intrinsic << std::endl;

           scale = static_cast<float>(width) / data["intrinsicReferenceDimensionWidth"].get<float>();
           intrinsic(0, 0) *= scale;
           intrinsic(1, 1) *= scale;
           intrinsic(0, 2) *= scale;
           intrinsic(1, 2) *= scale;

           // Debug print
           std::cout << "Intrinsic Matrix after scaling:\n" << intrinsic << std::endl;
       }
void ImageDepth::createUndistortionLookup() {
    // Create xy_pos
    std::vector<cv::Point2f> xy_pos;
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            xy_pos.emplace_back(static_cast<float>(x), static_cast<float>(y));
        }
    }
    
    std::cout << "xy_pos (first 10 values):\n";
    for (int i = 0; i < 10 && i < xy_pos.size(); ++i) {
        std::cout << xy_pos[i] << " ";
    }
    std::cout << std::endl;
    
    // Convert to cv::Mat and subtract center
    cv::Mat xy = cv::Mat(xy_pos).reshape(2).clone();  // Reshape to have 2 columns (x and y)
    cv::Point2f center(intrinsic(0, 2), intrinsic(1, 2));
    std::cout << "center:\n" << center << std::endl;
    
    for (int i = 0; i < xy.rows; ++i) {
        xy.at<cv::Vec2f>(i, 0)[0] -= center.x;
        xy.at<cv::Vec2f>(i, 0)[1] -= center.y;
    }
    
    std::cout << "xy after subtracting center (first 10 values):\n";
    for (int i = 0; i < 10; ++i) {
        std::cout << "[" << xy.at<cv::Vec2f>(i, 0)[0] << ", " << xy.at<cv::Vec2f>(i, 0)[1] << "] ";
    }
    std::cout << std::endl;
    
    int n = xy.rows;
    cv::Mat r = cv::Mat::zeros(n, 1, CV_64F);
    
    // Calculate radius from center
    for (int i = 0; i < n; ++i) {
        double x = xy.at<cv::Vec2f>(i, 0)[0]; // Access as Vec2f to get x, y
        double y = xy.at<cv::Vec2f>(i, 0)[1];
        r.at<double>(i, 0) = std::sqrt(x * x + y * y);
    }
    
    // Print first 10 values of r
    std::cout << "radius r (first 10 values):\n";
    for (int i = 0; i < std::min(n, 10); ++i) {
        std::cout << r.at<double>(i, 0) << std::endl;
    }
    
    // Normalize radius
    double max_r = 0.0;
    cv::minMaxIdx(r, nullptr, &max_r);
    std::cout << "max_r:\n" << max_r << std::endl;
    
    cv::Mat norm_r = r / max_r;
    
    // Print first 10 values of norm_r
    std::cout << "normalized radius norm_r (first 10 values):\n";
    for (int i = 0; i < std::min(n, 10); ++i) {
        std::cout << norm_r.at<double>(i, 0) << std::endl;
    }
    
    // Convert inverseLensDistortionLookup from float to double
    std::vector<double> table(inverseLensDistortionLookup.begin(), inverseLensDistortionLookup.end());
    std::cout << "inverseLensDistortionLookup table:\n";
    for (const auto& val : table) {
        std::cout << val << " ";
    }
    std::cout << std::endl;
    
    int num = table.size();
    std::cout << "num:\n" << num << std::endl;
    
    // Interpolate the scale
    cv::Mat scale = cv::Mat::ones(norm_r.size(), CV_64F);
    
    for (int i = 0; i < norm_r.rows; ++i) {
        double interpolated_value = interpolate(norm_r.at<double>(i, 0) * num, std::vector<double>(num), table);
        scale.at<double>(i, 0) = 1.0 + interpolated_value;
    }
    
    std::cout << "scale (first 10 values):\n";
    for (int i = 0; i < std::min(10, scale.rows); ++i) {
        std::cout << scale.at<double>(i, 0) << std::endl;
    }
    
    std::vector<cv::Point2d> new_xy(xy.rows);
    
    for (int i = 0; i < xy.rows; ++i) {
        cv::Point2d point = cv::Point2d(static_cast<double>(xy.at<cv::Vec2f>(i, 0)[0]), static_cast<double>(xy.at<cv::Vec2f>(i, 0)[1])) * scale.at<double>(i, 0) + cv::Point2d(center);
        new_xy[i] = point;
    }
    
    std::cout << "new_xy (first 10 values):\n";
    for (int i = 0; i < std::min(10, static_cast<int>(new_xy.size())); ++i) {
        std::cout << "[" << new_xy[i].x << ", " << new_xy[i].y << "] ";
    }
    std::cout << std::endl;
    
    // Convert new_xy to cv::Mat and reshape to match dimensions
    cv::Mat new_xy_mat(new_xy, true); // Convert to Mat
    new_xy_mat = new_xy_mat.reshape(2, height); // Reshape to (height, width, 2)
    
    // Split the Mat into two channels
    std::vector<cv::Mat> new_xy_channels(2);
    cv::split(new_xy_mat, new_xy_channels);
    
    map_x = new_xy_channels[0];
    map_y = new_xy_channels[1];
    
    
    std::cout << "map_x (first 10 values):\n";
    for (int i = 0; i < 10; ++i) {
        std::cout << map_x.at<double>(i) << " ";
    }
    std::cout << std::endl;
    
    std::cout << "map_y (first 10 values):\n";
    for (int i = 0; i < 10; ++i) {
        std::cout << map_y.at<double>(i) << " ";
    }
    std::cout << std::endl;
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
