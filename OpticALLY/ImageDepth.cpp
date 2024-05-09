// ImageDepth.cpp
// OpticALLY

#include "ImageDepth.hpp"
#include <fstream>
#include <json/json.h> // Assuming a JSON library for C++
#include <cmath>

ImageDepth::ImageDepth(const std::string& calibration_file, const std::string& image_file, const std::string& depth_file,
                       int width, int height, float min_depth, float max_depth, float normal_radius)
    : calibration_file(calibration_file), image_file(image_file), depth_file(depth_file),
      width(width), height(height), min_depth(min_depth), max_depth(max_depth),
      normal_radius(normal_radius), pose(Eigen::Matrix4f::Identity()) {
    loadCalibration(calibration_file);
    createUndistortionLookup();
    loadImage(image_file);
    loadDepth(depth_file);
}

void ImageDepth::loadCalibration(const std::string& file) {
    // Implement calibration file loading using a JSON parser, converting base64 strings
}

void ImageDepth::createUndistortionLookup() {
    // Implement undistortion lookup table generation logic
}

void ImageDepth::loadImage(const std::string& file) {
    img = cv::imread(file, cv::IMREAD_UNCHANGED);
    if (img.empty()) {
        std::cerr << "Error: Unable to load image " << file << std::endl;
    }
    processImage();
}

void ImageDepth::processImage() {
    // Implement image processing logic similar to Python's `process_image`
}

void ImageDepth::loadDepth(const std::string& file) {
    // Implement depth map loading logic similar to Python's `load_depth`
}

void ImageDepth::undistortDepthMap() {
    cv::remap(depth_map, depth_map_undistort, map_x, map_y, cv::INTER_LINEAR);
}

std::tuple<cv::Mat, std::vector<cv::Point2f>, std::vector<int>> ImageDepth::project3D(const std::vector<cv::Point2f>& pts) {
    // Implement the 3D projection logic
    // Return a tuple of projected points, indices, and good index flags
}

