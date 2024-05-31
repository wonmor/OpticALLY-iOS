// ImageDepth.hpp
// OpticALLY

#ifndef ImageDepth_hpp
#define ImageDepth_hpp

#include <opencv2/opencv.hpp>
#include <open3d/Open3D.h>
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
    float scale;
    cv::Mat img;
    cv::Mat img_linear;
    cv::Mat img_undistort;
    cv::Mat depth_map;
    cv::Mat depth_map_undistort;
    cv::Mat map_x, map_y;
    cv::Mat mask;
    Eigen::Matrix3d intrinsic;
    Eigen::Matrix4f pose;
    std::vector<float> lensDistortionLookup;
    std::vector<float> inverseLensDistortionLookup;
    std::shared_ptr<open3d::geometry::PointCloud> pointCloud;
    open3d::geometry::PointCloud pcd;

    // Private utility methods
    void loadCalibration(const std::string& file);
    void createUndistortionLookup();
    void loadImage(const std::string& file);
    void loadDepth(const std::string& file);
    void srgbToLinear(cv::Mat& img);
    float linearInterpolate(const std::vector<float>& lookup, float x);
    void debugImageStats(const cv::Mat& image, const std::string& name);
    void project3d(const cv::Mat& pts, cv::Mat& xyz, std::vector<int>& good_idx);
    void undistort_depth_map();

public:
    // Constructor
    ImageDepth(const std::string& calibration_file,
               const std::string& image_file,
               const std::string& depth_file,
               int width = 640,
               int height = 480,
               float min_depth = 0.1f,
               float max_depth = 0.5f,
               float normal_radius = 0.1f);

    // Public methods
    std::shared_ptr<open3d::geometry::PointCloud> getPointCloud();
};

#endif // IMAGE_DEPTH_HPP
