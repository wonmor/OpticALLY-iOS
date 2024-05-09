// ImageDepth.hpp
// OpticALLY

#ifndef IMAGE_DEPTH_HPP
#define IMAGE_DEPTH_HPP

#include <opencv2/opencv.hpp>
#include <vector>
#include <string>
#include "Eigen/Dense" // For Matrix operations

class ImageDepth {
private:
    std::string image_file;
    std::string calibration_file;
    std::string depth_file;
    int width;
    int height;
    float min_depth;
    float max_depth;
    float normal_radius;
    cv::Mat img;
    cv::Mat img_linear;
    cv::Mat img_undistort;
    cv::Mat depth_map;
    cv::Mat depth_map_undistort;
    cv::Mat map_x, map_y;
    std::vector<float> lensDistortionLookup;
    std::vector<float> inverseLensDistortionLookup;
    Eigen::Matrix3f intrinsic;
    Eigen::Matrix4f pose;

    void loadCalibration(const std::string& file);
    void createUndistortionLookup();
    void loadImage(const std::string& file);
    void processImage();
    void loadDepth(const std::string& file);
    void undistortDepthMap();
    std::tuple<cv::Mat, std::vector<cv::Point2f>, std::vector<int>> project3D(const std::vector<cv::Point2f>& pts);

public:
    ImageDepth(const std::string& calibration_file,
               const std::string& image_file,
               const std::string& depth_file,
               int width = 640,
               int height = 480,
               float min_depth = 0.1f,
               float max_depth = 0.5f,
               float normal_radius = 0.1f);
};

#endif // IMAGE_DEPTH_HPP
