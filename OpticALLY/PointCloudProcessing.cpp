//
//  PointCloudProcessing.cpp
//  OpticALLY
//
//  Created by John Seong on 5/7/24.
//

#include "PointCloudProcessing.hpp"
#include "ImageDepth.hpp"
#include <open3d/Open3D.h>
#include <vector>
#include <memory>
#include <tuple>
#include <vector>

// Save point cloud to file
void savePointCloud(const std::string& filename, const std::shared_ptr<open3d::geometry::PointCloud>& pcd) {
    open3d::io::WritePointCloud(filename, *pcd);
}

// Reconstruct surface using Poisson reconstruction
void reconstructSurface(const std::shared_ptr<open3d::geometry::PointCloud>& pcd, const std::string& output) {
    // Ensure normals are estimated before reconstruction
    pcd->EstimateNormals();

    // Run Poisson surface reconstruction
    std::shared_ptr<open3d::geometry::TriangleMesh> mesh;
    std::vector<double> densities;
    std::tie(mesh, densities) = open3d::geometry::TriangleMesh::CreateFromPointCloudPoisson(*pcd);

    // Write mesh to file
    if (mesh && !mesh->IsEmpty()) {
        open3d::io::WriteTriangleMesh(output, *mesh);
    } else {
        std::cerr << "Failed to create mesh or mesh is empty." << std::endl;
    }
}

