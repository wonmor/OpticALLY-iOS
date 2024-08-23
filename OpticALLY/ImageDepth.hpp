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
    cv::Mat mask;
    cv::Mat map_x, map_y;
    cv::Mat xy, rgb, reshaped_img;
    
    cv::Point2f noseTip;
        cv::Point2f chin;
        cv::Point2f leftEyeLeftCorner;
        cv::Point2f rightEyeRightCorner;
        cv::Point2f leftMouthCorner;
        cv::Point2f rightMouthCorner;
    
    Eigen::Matrix4f pose;
    
    std::shared_ptr<open3d::geometry::PointCloud> pointCloud;
    
    std::vector<int> valid_indices;
    std::vector<cv::Point2f> xy_filtered;
    std::vector<cv::Vec3f> rgb_filtered;

    // Private utility methods
    void debugPrint(const std::string& msg, const cv::Mat& mat);

public:
    // Constructor
    ImageDepth(const std::string& calibration_file,
               const std::string& image_file,
               const std::string& depth_file,
               int width = 640,
               int height = 480,
               float min_depth = 0.1f,
               float max_depth = 0.5f,
               float normal_radius = 0.1f,
               const cv::Point2f& noseTip = cv::Point2f(),
                          const cv::Point2f& chin = cv::Point2f(),
                          const cv::Point2f& leftEyeLeftCorner = cv::Point2f(),
                          const cv::Point2f& rightEyeRightCorner = cv::Point2f(),
                          const cv::Point2f& leftMouthCorner = cv::Point2f(),
                          const cv::Point2f& rightMouthCorner = cv::Point2f());
    
    std::vector<float> lensDistortionLookup;
    std::vector<float> inverseLensDistortionLookup;

    // Public methods
    std::shared_ptr<open3d::geometry::PointCloud> getPointCloud();
    std::vector<cv::Point3f> project3D(const std::vector<cv::Point2f>& points);
    
    Eigen::Matrix3d intrinsic;

    // Utility methods
    void loadCalibration(const std::string& file);
    void createUndistortionLookup();
    void loadImage(const std::string& file);
    void processImage();
    void loadDepth(const std::string& file);
    float linearInterpolate(const std::vector<float>& lookup, float x);
    void createPointCloud(const cv::Mat& depth_map, const cv::Mat& mask);
    void debugImageStats(const cv::Mat& image, const std::string& name);
    
    cv::Mat srgb_to_linear(const cv::Mat& srgb_img);
    
    // New function to project specific (x, y) to 3D
    std::tuple<float, float, float> projectTo3D(int x, int y) const;
};

#endif // IMAGE_DEPTH_HPP
