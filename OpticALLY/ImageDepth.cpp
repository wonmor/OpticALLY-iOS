// ImageDepth.cpp
// OpticALLY

#include "ImageDepth.hpp"
#include <iostream>
#include <fstream>
#include <nlohmann/json.hpp>
#include "cppcodec/base64_rfc4648.hpp"
#include <open3d/geometry/PointCloud.h>
#include <open3d/geometry/KDTreeSearchParam.h>
#include "base64.hpp"

using json = nlohmann::json;
using namespace Eigen;

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
            Eigen::Matrix3d intrinsic;
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
                   xy_pos.emplace_back(x, y);
               }
           }
           std::cout << "xy_pos (first 10 values):\n";
           for (int i = 0; i < 10 && i < xy_pos.size(); ++i) {
               std::cout << xy_pos[i] << " ";
           }
           std::cout << std::endl;

           // Convert to cv::Mat and subtract center
           cv::Mat xy = cv::Mat(xy_pos).reshape(1).clone();
           cv::Point2f center(intrinsic(0, 2), intrinsic(1, 2));
           std::cout << "center:\n" << center << std::endl;

           xy -= cv::Scalar(center.x, center.y);
           std::cout << "xy after subtracting center (first 10 values):\n";
           for (int i = 0; i < 10; ++i) {
               std::cout << xy.at<cv::Point2f>(i) << " ";
           }
           std::cout << std::endl;

           // Calculate radius from center
           cv::Mat r;
           cv::sqrt(xy.col(0).mul(xy.col(0)) + xy.col(1).mul(xy.col(1)), r);
           std::cout << "radius r (first 10 values):\n";
           for (int i = 0; i < 10; ++i) {
               std::cout << r.at<float>(i) << " ";
           }
           std::cout << std::endl;

           // Normalize radius
           double max_r;
           cv::minMaxLoc(r, nullptr, &max_r);
           std::cout << "max_r:\n" << max_r << std::endl;

           cv::Mat norm_r = r / max_r;
           std::cout << "normalized radius norm_r (first 10 values):\n";
           for (int i = 0; i < 10; ++i) {
               std::cout << norm_r.at<float>(i) << " ";
           }
           std::cout << std::endl;

           // Interpolate the scale
           std::cout << "inverseLensDistortionLookup table:\n";
           for (const auto& val : inverseLensDistortionLookup) {
               std::cout << val << " ";
           }
           std::cout << std::endl;

           int num = inverseLensDistortionLookup.size();
           std::cout << "num:\n" << num << std::endl;

           std::vector<float> scale(norm_r.rows);
           for (int i = 0; i < norm_r.rows; ++i) {
               float interp_index = norm_r.at<float>(i) * num;
               int index = static_cast<int>(interp_index);
               float frac = interp_index - index;
               if (index >= num - 1) {
                   scale[i] = 1.0 + inverseLensDistortionLookup[num - 1];
               } else {
                   scale[i] = 1.0 + inverseLensDistortionLookup[index] + frac * (inverseLensDistortionLookup[index + 1] - inverseLensDistortionLookup[index]);
               }
           }
           std::cout << "scale (first 10 values):\n";
           for (int i = 0; i < 10; ++i) {
               std::cout << scale[i] << " ";
           }
           std::cout << std::endl;

           // Apply the scale
           for (int i = 0; i < xy.rows; ++i) {
               xy.at<cv::Point2f>(i) *= scale[i];
           }
           xy += cv::Scalar(center.x, center.y);
           std::cout << "new_xy (first 10 values):\n";
           for (int i = 0; i < 10; ++i) {
               std::cout << xy.at<cv::Point2f>(i) << " ";
           }
           std::cout << std::endl;

           // Reshape to map_x and map_y
           map_x = cv::Mat(height, width, CV_32F);
           map_y = cv::Mat(height, width, CV_32F);
           for (int y = 0; y < height; ++y) {
               for (int x = 0; x < width; ++x) {
                   int index = y * width + x;
                   map_x.at<float>(y, x) = xy.at<cv::Point2f>(index).x;
                   map_y.at<float>(y, x) = xy.at<cv::Point2f>(index).y;
               }
           }
           std::cout << "map_x (first 10 values):\n";
           for (int i = 0; i < 10; ++i) {
               std::cout << map_x.at<float>(i) << " ";
           }
           std::cout << std::endl;

           std::cout << "map_y (first 10 values):\n";
           for (int i = 0; i < 10; ++i) {
               std::cout << map_y.at<float>(i) << " ";
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
