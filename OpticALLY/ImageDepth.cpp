#include <iostream>
#include <fstream>
#include <vector>
#include <opencv2/core/types.hpp>
#include <string>
#include <opencv2/opencv.hpp>
#include <Eigen/Dense>
#include <nlohmann/json.hpp>
#include "cppcodec/base64_rfc4648.hpp"
#include <open3d/Open3D.h>

class ImageDepth {
public:
    ImageDepth(const std::string& calibration_file, const std::string& image_file, const std::string& depth_file,
               int width = 640, int height = 480, float min_depth = 0.1, float max_depth = 0.5, float normal_radius = 0.1)
    : image_file(image_file), calibration_file(calibration_file), depth_file(depth_file),
    width(width), height(height), min_depth(min_depth), max_depth(max_depth), normal_radius(normal_radius) {
        
        pose = Eigen::Matrix4f::Identity();
        loadCalibration(calibration_file);
        createUndistortionLookup();
        loadImage(image_file);
        loadDepth(depth_file);
    }
    
private:
    std::string image_file, calibration_file, depth_file;
    int width, height;
    float min_depth, max_depth, normal_radius;
    Eigen::Matrix4f pose;
    std::vector<float> lensDistortionLookup, inverseLensDistortionLookup;
    Eigen::Matrix3f intrinsic;
    cv::Mat map_x, map_y, img, depth_map, img_undistort, depth_map_undistort;
    
    void loadCalibration(const std::string& file) {
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
    
    float linearInterpolate(const std::vector<float>& lookup, float x) {
        int i = static_cast<int>(x);
        if (i < 0) return lookup.front();
        if (i >= static_cast<int>(lookup.size()) - 1) return lookup.back();
        
        float alpha = x - i;
        return lookup[i] * (1 - alpha) + lookup[i + 1] * alpha;
    }
    
    void createUndistortionLookup() {
        std::vector<cv::Point2f> xy;
        xy.reserve(width * height);
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                xy.emplace_back(x, y);
            }
        }
        
        cv::Mat xy_mat(height * width, 1, CV_32FC2, xy.data());
        xy_mat = xy_mat.reshape(2);
        
        cv::Mat center = (cv::Mat_<float>(1, 2) << intrinsic(0, 2), intrinsic(1, 2));
        cv::subtract(xy_mat, center, xy_mat);
        
        std::vector<float> r(height * width);
        for (int i = 0; i < height * width; ++i) {
            auto p = xy_mat.at<cv::Vec2f>(i);
            r[i] = std::sqrt(p[0] * p[0] + p[1] * p[1]);
        }
        
        float max_r = *std::max_element(r.begin(), r.end());
        for (auto& val : r) val /= max_r;
        
        std::vector<float> scale(r.size());
        for (size_t i = 0; i < scale.size(); ++i){
            float idx = r[i] * inverseLensDistortionLookup.size();
            scale[i] = 1.0f + linearInterpolate(inverseLensDistortionLookup, idx);
        }
        for (int i = 0; i < height * width; ++i) {
            auto& p = xy_mat.at<cv::Vec2f>(i);
            p[0] = p[0] * scale[i] + center.at<float>(0, 0);
            p[1] = p[1] * scale[i] + center.at<float>(0, 1);
        }
        
        map_x = cv::Mat(height, width, CV_32F);
        map_y = cv::Mat(height, width, CV_32F);
        for (int i = 0; i < height * width; ++i) {
            map_x.at<float>(i / width, i % width) = xy_mat.at<cv::Vec2f>(i)[0];
            map_y.at<float>(i / width, i % width) = xy_mat.at<cv::Vec2f>(i)[1];
        }
    }
    
    void loadImage(const std::string& file) {
        std::ifstream ifs(file, std::ios::binary);
        std::vector<uint8_t> img_data((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
        img = cv::Mat(height, width, CV_8UC4, img_data.data());
        cv::cvtColor(img, img, cv::COLOR_RGBA2RGB);
        img_undistort = cv::Mat();
        cv::remap(img, img_undistort, map_x, map_y, cv::INTER_LINEAR);
    }
    
    void loadDepth(const std::string& file) {
        std::ifstream ifs(file, std::ios::binary);
        std::vector<float> depth_data((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
        depth_map = cv::Mat(height, width, CV_32F, depth_data.data());
        depth_map_undistort = cv::Mat();
        cv::remap(depth_map, depth_map_undistort, map_x, map_y, cv::INTER_LINEAR);
    }
    
    std::vector<cv::Point3f> project3D(const std::vector<cv::Point2f>& points) {
        std::vector<cv::Point3f> points3D;
        points3D.reserve(points.size());

        for (const auto& pt : points) {
            int x = static_cast<int>(std::round(pt.x));
            int y = static_cast<int>(std::round(pt.y));

            // Ensure the point is within the image bounds
            if (x < 0 || x >= width || y < 0 || y >= height) continue;

            float depth = depth_map_undistort.at<float>(y, x);
            
            // Check if the depth value is within the valid range
            if (depth > min_depth && depth < max_depth) {
                // Convert from pixel coordinates to camera coordinates
                float z = depth;
                float x3D = (x - intrinsic(0, 2)) * z / intrinsic(0, 0);
                float y3D = (y - intrinsic(1, 2)) * z / intrinsic(1, 1);
                points3D.emplace_back(x3D, y3D, z);
            }
        }

        return points3D;
    }
};
