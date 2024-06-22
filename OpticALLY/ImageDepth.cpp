// ImageDepth.cpp
// OpticALLY

#define TINYNDARRAY_IMPLEMENTATION

#include "ImageDepth.hpp"
#include <algorithm>
#include <iostream>
#include <iomanip>
#include <string>
#include <fstream>
#include <nlohmann/json.hpp>
#include "cppcodec/base64_rfc4648.hpp"
#include <open3d/geometry/PointCloud.h>
#include <open3d/geometry/KDTreeSearchParam.h>
#include "base64.hpp"
#include "tinyndarray.h"

using tinyndarray::NdArray;
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
    createPointCloud(depth_map_undistort, mask);
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
    xy = cv::Mat(xy_pos).reshape(2).clone();  // Reshape to have 2 columns (x and y)
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
    
    // Convert to CV_32FC1
    new_xy_channels[0].convertTo(map_x, CV_32FC1);
    new_xy_channels[1].convertTo(map_y, CV_32FC1);
    
    // Debug prints
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
    cv::cvtColor(img, img, cv::COLOR_BGRA2RGB); // Remove alpha and swap RB

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

    // Print first 10 values of map_x
    std::cout << "map_x (first 10 values):\n";
    for (int i = 0; i < 10; ++i) {
        std::cout << map_x.at<float>(i) << " ";
    }
    std::cout << std::endl;

    // Print first 10 values of map_y
    std::cout << "map_y (first 10 values):\n";
    for (int i = 0; i < 10; ++i) {
        std::cout << map_y.at<float>(i) << " ";
    }
    std::cout << std::endl;

    debugImageStats(img_linear, "img_linear");

   // Debug: Print shape and type of map_x and map_y
   debugImageStats(map_x, "map_x");
   debugImageStats(map_y, "map_y");

   cv::remap(img_linear, img_undistort, map_x, map_y, cv::INTER_LINEAR);

   // Debug: Print shape and type of img_undistort
   debugImageStats(img_undistort, "img_undistort");

    // Debug print the first 10 values
    std::cout << "Undistorted image (first 10 values):";
    for (int i = 0; i < 10; ++i) {
        std::cout << " " << static_cast<int>(img_undistort.data[i]);
    }
    std::cout << std::endl;
}

std::string getMatType(int type) {
    std::string r;

    uchar depth = type & CV_MAT_DEPTH_MASK;
    uchar chans = 1 + (type >> CV_CN_SHIFT);

    switch (depth) {
        case CV_8U:  r = "8U"; break;
        case CV_8S:  r = "8S"; break;
        case CV_16U: r = "16U"; break;
        case CV_16S: r = "16S"; break;
        case CV_32S: r = "32S"; break;
        case CV_32F: r = "32F"; break;
        case CV_64F: r = "64F"; break;
        default:     r = "User"; break;
    }

    r += "C";
    r += (chans + '0');

    return r;
}

void ImageDepth::debugImageStats(const cv::Mat& image, const std::string& name) {
    double min, max, mean;
    cv::minMaxLoc(image, &min, &max);
    mean = cv::mean(image)[0];

    std::cout << name << " shape: " << image.rows << " x " << image.cols << std::endl;
    std::cout << name << " type: " << getMatType(image.type()) << std::endl;
    std::cout << name << " max value: " << max << std::endl;
    std::cout << name << " min value: " << min << std::endl;
    std::cout << name << " mean value: " << mean << std::endl;
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
    std::cout << "Loading depth file " << file << std::endl;

    // Read binary file as float32
    std::ifstream in(file, std::ios::binary);
    if (!in) {
        std::cerr << "Cannot open file: " << file << std::endl;
        return;
    }
    
    in.seekg(0, std::ios::end);
    std::streampos fileSize = in.tellg();
    in.seekg(0, std::ios::beg);

    std::vector<float> depth(fileSize / sizeof(float));
    in.read(reinterpret_cast<char*>(depth.data()), fileSize);
    in.close();

    std::cout << "Loaded depth data (first 10 values): ";
    for (int i = 0; i < 10 && i < depth.size(); ++i)
        std::cout << depth[i] << " ";
    std::cout << std::endl;
    // All possible (x, y) positions
        std::vector<int> idx(width * height);
        std::iota(idx.begin(), idx.end(), 0);

        // Print first 10 values of idx array
        std::cout << "Generated idx array (first 10 values): [";
        for (int i = 0; i < 10; ++i) {
            std::cout << idx[i];
            if (i < 9) {
                std::cout << " ";
            }
        }
        std::cout << "]" << std::endl;

    xy = cv::Mat(height * width, 2, CV_32F);
        for (int i = 0; i < idx.size(); ++i) {
            xy.at<float>(i, 0) = idx[i] % width;
            xy.at<float>(i, 1) = idx[i] / width;
        }

        std::cout << "Generated xy positions (first 10 values): " << xy.rowRange(0, 10) << std::endl;
    
    // Remove bad values
        std::vector<bool> no_nan(depth.size());
        std::vector<bool> depth1(depth.size());
        std::vector<bool> depth2(depth.size());


        for (size_t i = 0; i < depth.size(); ++i) {
            no_nan[i] = !std::isnan(depth[i]);
            depth1[i] = depth[i] > min_depth;
            depth2[i] = depth[i] < max_depth;
            idx[i] = no_nan[i] && depth1[i] && depth2[i];
        }

    // Populate valid_indices
        valid_indices.clear();
        for (size_t i = 0; i < depth.size(); ++i) {
            if (!std::isnan(depth[i]) && depth[i] > min_depth && depth[i] < max_depth) {
                valid_indices.push_back(i);
            }
        }

        // Print first 10 values of valid_indices
        std::cout << "Filtered valid depth indices (first 10 values): [";
        for (size_t i = 0; i < 10 && i < valid_indices.size(); ++i) {
            std::cout << valid_indices[i];
            if (i < 9 && i < valid_indices.size() - 1) {
                std::cout << " ";
            }
        }
        std::cout << "]" << std::endl;

        std::cout << "Initial sizes:" << std::endl;
        std::cout << "xy shape: (" << xy.rows << ", " << xy.cols << ")" << std::endl;
        std::cout << "img_undistort shape: (" << img_undistort.rows << ", " << img_undistort.cols << ")" << std::endl;
        std::cout << "idx size: " << idx.size() << std::endl;

    // Filter xy and img_undistort based on idx
        std::vector<cv::Point2f> xy_filtered;
        std::vector<cv::Vec3f> rgb_filtered;

        for (size_t i = 0; i < idx.size(); ++i) {
            if (idx[i]) {
                xy_filtered.push_back(cv::Point2f(xy.at<float>(i, 0), xy.at<float>(i, 1)));
                cv::Vec3b color = img_undistort.at<cv::Vec3b>(i / width, i % width);
                rgb_filtered.push_back(cv::Vec3f(color[0] / 255.0f, color[1] / 255.0f, color[2] / 255.0f));
                
                // Print the color values
                       std::cout << "color[0]: " << static_cast<int>(color[0]) << ", "
                                 << "color[1]: " << static_cast<int>(color[1]) << ", "
                                 << "color[2]: " << static_cast<int>(color[2]) << std::endl;
            }
        }

        // Print first 10 values of filtered xy and rgb
        std::cout << "Filtered xy positions (first 10 values): [";
        for (size_t i = 0; i < 10 && i < xy_filtered.size(); ++i) {
            std::cout << "(" << xy_filtered[i].x << ", " << xy_filtered[i].y << ")";
            if (i < 9 && i < xy_filtered.size() - 1) {
                std::cout << " ";
            }
        }
        std::cout << "]" << std::endl;

        std::cout << "Filtered rgb values (first 10 values): [";
        for (size_t i = 0; i < 10 && i < rgb_filtered.size(); ++i) {
            std::cout << "(" << rgb_filtered[i][0] << ", " << rgb_filtered[i][1] << ", " << rgb_filtered[i][2] << ")";
            if (i < 9 && i < rgb_filtered.size() - 1) {
                std::cout << " ";
            }
        }
        std::cout << "]" << std::endl;

        // Print filtered sizes
        std::cout << "Filtered sizes:" << std::endl;
        std::cout << "xy_filtered size: " << xy_filtered.size() << std::endl;
        std::cout << "rgb_filtered size: " << rgb_filtered.size() << std::endl;
    
    // Convert xy_filtered to cv::Mat
       xy = cv::Mat(static_cast<int>(xy_filtered.size()), 2, CV_32F);
       for (size_t i = 0; i < xy_filtered.size(); ++i) {
           xy.at<float>(i, 0) = xy_filtered[i].x;
           xy.at<float>(i, 1) = xy_filtered[i].y;
       }

       // Convert rgb_filtered to cv::Mat
       rgb = cv::Mat(static_cast<int>(rgb_filtered.size()), 3, CV_32F);
       for (size_t i = 0; i < rgb_filtered.size(); ++i) {
           rgb.at<cv::Vec3f>(i, 0)[0] = rgb_filtered[i][0];
           rgb.at<cv::Vec3f>(i, 0)[1] = rgb_filtered[i][1];
           rgb.at<cv::Vec3f>(i, 0)[2] = rgb_filtered[i][2];
       }

       // Debug prints to verify the conversion
       std::cout << "Converted xy positions (first 10 values):" << std::endl;
       for (int i = 0; i < std::min(10, xy.rows); ++i) {
           std::cout << "(" << xy.at<float>(i, 0) << ", " << xy.at<float>(i, 1) << ")" << std::endl;
       }

       std::cout << "Converted rgb values (first 10 values):" << std::endl;
       for (int i = 0; i < std::min(10, rgb.rows); ++i) {
           std::cout << "(" << rgb.at<cv::Vec3f>(i, 0)[0] << ", " << rgb.at<cv::Vec3f>(i, 0)[1] << ", " << rgb.at<cv::Vec3f>(i, 0)[2] << ")" << std::endl;
       }

    // Create mask
      std::vector<uint8_t> mask(depth.size(), 255);
      for (size_t i = 0; i < idx.size(); ++i) {
          if (!idx[i]) {
              mask[i] = 0;
          }
      }

      // Reshape mask to (height, width)
      cv::Mat mask_mat(height, width, CV_8U, mask.data());

      // Print first 10 values of mask
      std::cout << "Generated mask (first 10 values): [";
      for (size_t i = 0; i < 10 && i < mask.size(); ++i) {
          std::cout << static_cast<int>(mask[i]);
          if (i < 9 && i < mask.size() - 1) {
              std::cout << " ";
          }
      }
      std::cout << "]" << std::endl;
    
    // Mask out depth buffer
        std::vector<float> depth_map = depth;
        for (size_t i = 0; i < depth_map.size(); ++i) {
            if (!idx[i]) {
                depth_map[i] = -1000.0f;
            }
        }

        // Reshape depth map to (height, width, 1)
        cv::Mat depth_map_mat(height, width, CV_32F, depth_map.data());

        // Print first 10 values of depth map
        std::cout << "Generated depth map with mask (first 10 values): [";
        for (size_t i = 0; i < 10 && i < depth_map.size(); ++i) {
            std::cout << depth_map[i];
            if (i < 9 && i < depth_map.size() - 1) {
                std::cout << " ";
            }
        }
        std::cout << "]" << std::endl;

        // Debug prints
        std::cout << "Depth map (first 10 values): [";
        for (size_t i = 0; i < 10 && i < depth_map.size(); ++i) {
            std::cout << depth_map[i];
            if (i < 9 && i < depth_map.size() - 1) {
                std::cout << " ";
            }
        }
        std::cout << "]" << std::endl;
    
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                map_x.at<float>(y, x) = static_cast<float>(x);
                map_y.at<float>(y, x) = static_cast<float>(y);
            }
        }

        cv::remap(depth_map_mat, depth_map_undistort, map_x, map_y, cv::INTER_LINEAR);

    
        // Print first 10 values of the undistorted depth map
        std::cout << "Undistorted depth map (first 10 values): [";
        for (size_t i = 0; i < 10 && i < depth_map_undistort.total(); ++i) {
            std::cout << depth_map_undistort.at<float>(i / width, i % width);
            if (i < 9 && i < depth_map_undistort.total() - 1) {
                std::cout << " ";
            }
        }
        std::cout << "]" << std::endl;
    
    // Calculate max, min, and average values
        double min_value, max_value;
        cv::minMaxLoc(depth_map_undistort, &min_value, &max_value);
        double sum = cv::sum(depth_map_undistort)[0];
        double average_value = sum / depth_map_undistort.total();

        // Print max, min, and average values
        std::cout << "Max value of undistorted depth map: " << max_value << std::endl;
        std::cout << "Min value of undistorted depth map: " << min_value << std::endl;
        std::cout << "Average value of undistorted depth map: " << average_value << std::endl;
    
    // Populate the rgb matrix with undistorted RGB values
       rgb = cv::Mat(height, width, CV_32FC3); // Initialize rgb matrix
       for (int y = 0; y < height; ++y) {
           for (int x = 0; x < width; ++x) {
               cv::Vec3b color = img_undistort.at<cv::Vec3b>(y, x);
               rgb.at<cv::Vec3f>(y, x) = cv::Vec3f(color[0] / 255.0f, color[1] / 255.0f, color[2] / 255.0f);
           }
       }

       // Debug prints for rgb
       std::cout << "rgb (first 10 values): [";
       for (int i = 0; i < 10; ++i) {
           int y = i / rgb.cols;
           int x = i % rgb.cols;
           cv::Vec3f color = rgb.at<cv::Vec3f>(y, x);
           std::cout << "(" << color[0] << ", " << color[1] << ", " << color[2] << ")";
           if (i < 9) {
               std::cout << ", ";
           }
       }
       std::cout << "]" << std::endl;
}

void ImageDepth::createPointCloud(const cv::Mat& depth_map, const cv::Mat& mask) {
    std::cout << "Creating point cloud..." << std::endl;
    pointCloud = std::make_shared<open3d::geometry::PointCloud>();
    std::vector<Eigen::Vector3d> points;
    std::vector<Eigen::Vector3d> colors;
    
    // Expect pts to be Nx2
       cv::Mat xy_converted;
       xy.convertTo(xy_converted, CV_32S);

       std::cout << "Rounded xy positions (first 10 values):" << std::endl;
       for (int i = 0; i < std::min(10, xy_converted.rows); ++i) {
           std::cout << "(" << xy_converted.at<int>(i, 0) << ", " << xy_converted.at<int>(i, 1) << ")" << std::endl;
       }

    double fx = intrinsic(0, 0);
    double fy = intrinsic(1, 1);
    double cx = intrinsic(0, 2);
    double cy = intrinsic(1, 2);

       std::cout << "fx: " << fx << ", fy: " << fy << ", cx: " << cx << ", cy: " << cy << std::endl;

    // Extract depths using xy_converted coordinates
       std::vector<float> depths;
       for (int i = 0; i < xy_converted.rows; ++i) {
           int x = xy_converted.at<int>(i, 0);
           int y = xy_converted.at<int>(i, 1);
           depths.push_back(depth_map_undistort.at<float>(y, x));
       }

       // Print the size of depths and xy_converted
       std::cout << "Depths size: " << depths.size() << std::endl;
       std::cout << "xy_converted size: " << xy_converted.rows << std::endl;

       // Print the first 10 values of depths
       std::cout << "First 10 values of depths: ";
       for (size_t i = 0; i < std::min(depths.size(), size_t(10)); ++i) {
           std::cout << depths[i] << " ";
       }
       std::cout << std::endl;

       // Filter valid depths
       std::vector<int> good_idx;
       for (size_t i = 0; i < depths.size(); ++i) {
           if (depths[i] > min_depth && depths[i] < max_depth) {
               good_idx.push_back(i);
           }
       }

       // Print filtered valid depths and good indices
       std::cout << "Filtered valid depths (first 10 values): ";
       for (size_t i = 0; i < std::min(depths.size(), size_t(10)); ++i) {
           std::cout << depths[i] << " ";
       }
       std::cout << std::endl;

       std::cout << "Good indices for valid depths (first 10 values): ";
       for (size_t i = 0; i < std::min(good_idx.size(), size_t(10)); ++i) {
           std::cout << good_idx[i] << " ";
       }
       std::cout << std::endl;

       // Project to 3D points
       std::vector<cv::Point3f> pts;
       for (size_t i = 0; i < good_idx.size(); ++i) {
           int idx = good_idx[i];
           int x = xy_converted.at<int>(idx, 0);
           int y = xy_converted.at<int>(idx, 1);
           float depth = depths[idx];

           float px = (x - cx) / fx * depth;
           float py = (y - cy) / fy * depth;

           pts.emplace_back(px, py, depth);
       }

       // Print projected 3D points
       std::cout << "Projected 3D points (first 10 values): ";
       for (size_t i = 0; i < std::min(pts.size(), size_t(10)); ++i) {
           std::cout << "(" << pts[i].x << ", " << pts[i].y << ", " << pts[i].z << ") ";
       }
       std::cout << std::endl;

    pointCloud->points_ = points;
    pointCloud->colors_ = colors;

    // Calculate normals
    pointCloud->EstimateNormals(
        open3d::geometry::KDTreeSearchParamHybrid(normal_radius, 30)
    );
    pointCloud->OrientNormalsTowardsCameraLocation();
}
