//
//  PointCloudProcessing.hpp
//  OpticALLY
//
//  Created by John Seong on 5/7/24.
//

#ifndef PointCloudProcessing_hpp
#define PointCloudProcessing_hpp

#include <stdio.h>
#include <opencv2/opencv.hpp>

using namespace cv;
using namespace std;

// PointCloudProcessing.hpp
#include <open3d/Open3D.h>
#include <string>
#include <vector>
#include <filesystem>
#include "ImageDepth.hpp"

namespace fs = std::filesystem; // Use C++17 filesystem for file handling

void processPointCloudsToObj(const std::string& calibrationFile, const std::vector<std::string>& imageFiles, const std::vector<std::string>& depthFiles, const std::string& outputPath);

#endif /* PointCloudProcessing_hpp */
