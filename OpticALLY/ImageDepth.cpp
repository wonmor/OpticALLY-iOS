// ImageDepth.cpp
// OpticALLY

#include "ImageDepth.hpp"
#include <iostream>
#include <fstream>
#include <nlohmann/json.hpp>
#include "cppcodec/base64_rfc4648.hpp"

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

float ImageDepth::linearInterpolate(const std::vector<float>& lookup, float x) {
    int i = static_cast<int>(x);
    if (i < 0) return lookup.front();
    if (i >= static_cast<int>(lookup.size()) - 1) return lookup.back();

    float alpha = x - i;
    return lookup[i] * (1 - alpha) + lookup[i + 1] * alpha;
}

void ImageDepth::srgbToLinear(cv::Mat& img) {
    img.convertTo(img, CV_32FC3, 1.0 / 255.0); // Normalize
    for (int i = 0; i < img.rows; ++i) {
        for (int j = 0; j < img.cols; ++j) {
            auto& pixel = img.at<cv::Vec3f>(i, j);
            for (int k = 0; k < 3; ++k) {
                if (pixel[k] <= 0.04045) {
                    pixel[k] /= 12.92;
                } else {
                    pixel[k] = std::pow((pixel[k] + 0.055) / 1.055, 2.4);
                }
            }
        }
    }
}

void ImageDepth::createUndistortionLookup() {
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
    for (size_t i = 0; i < scale.size(); ++i) {
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

void ImageDepth::loadImage(const std::string& file) {
    std::ifstream ifs(file, std::ios::binary);
    if (!ifs.is_open()) {
        std::cerr << "Failed to open image file: " << file << std::endl;
        return;
    }

    std::vector<uint8_t> img_data((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
    img = cv::Mat(height, width, CV_8UC4, img_data.data());
    cv::cvtColor(img, img, cv::COLOR_RGBA2RGB);

    srgbToLinear(img);

    img_undistort = cv::Mat();
    cv::remap(img, img_undistort, map_x, map_y, cv::INTER_LINEAR);
}

void ImageDepth::loadDepth(const std::string& file) {
    std::ifstream ifs(file, std::ios::binary);
    if (!ifs.is_open()) {
        std::cerr << "Failed to open depth file: " << file << std::endl;
        return;
    }

    std::vector<uint16_t> depth_data((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
    depth_map = cv::Mat(height, width, CV_16UC1, depth_data.data());

    depth_map_undistort = cv::Mat();
    cv::remap(depth_map, depth_map_undistort, map_x, map_y, cv::INTER_NEAREST);
}

std::vector<cv::Point3f> ImageDepth::project3D(const std::vector<cv::Point2f>& points) {
    std::vector<cv::Point3f> result;
    for (const auto& point : points) {
        int x = static_cast<int>(point.x);
        int y = static_cast<int>(point.y);
        float z = static_cast<float>(depth_map_undistort.at<uint16_t>(y, x)) * 0.001f;

        if (z < min_depth || z > max_depth) {
            continue;
        }

        cv::Point3f pt((x - intrinsic(0, 2)) * z / intrinsic(0, 0),
                       (y - intrinsic(1, 2)) * z / intrinsic(1, 1), z);
        result.push_back(pt);
    }

    return result;
}

void ImageDepth::createPointCloud(const cv::Mat& depth_map, const cv::Mat& mask) {
    pointCloud = std::make_shared<open3d::geometry::PointCloud>();
    std::vector<Eigen::Vector3d> points;
    std::vector<Eigen::Vector3d> colors;

    for (int y = 0; y < depth_map.rows; ++y) {
        for (int x = 0; x < depth_map.cols; ++x) {
            if (mask.at<uint8_t>(y, x) == 0) continue;

            float z = static_cast<float>(depth_map.at<uint16_t>(y, x)) * 0.001f;

            if (z < min_depth || z > max_depth) continue;

            Eigen::Vector3d pt((x - intrinsic(0, 2)) * z / intrinsic(0, 0),
                               (y - intrinsic(1, 2)) * z / intrinsic(1, 1), z);

            points.emplace_back(pt);

            // Assuming img is already in linear RGB format
            cv::Vec3f color = img_undistort.at<cv::Vec3f>(y, x);
            colors.emplace_back(Eigen::Vector3d(color[0], color[1], color[2]));
        }
    }

    pointCloud->points_ = points;
    pointCloud->colors_ = colors;
}
