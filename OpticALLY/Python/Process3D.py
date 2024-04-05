import sys
import glob
import math
import time
from pathlib import Path

import numpy as np
import open3d as o3d
import matplotlib.pyplot as plt
import cv2 as cv

def process3d(point_clouds):
    # Process each point cloud
    for idx, obj in enumerate(point_clouds):
        pcd = obj.pcd  # Get the point cloud from the current ImageDepth object
        pcd.estimate_normals()

        print(f"Processing Point Cloud {idx+1}/{len(point_clouds)} ...")

        # Poisson surface reconstruction (or any other processing you need)
        with o3d.utility.VerbosityContextManager(o3d.utility.VerbosityLevel.Debug) as cm:
            mesh, densities = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(pcd, depth=9)

        threshold = 0.004893

        print("remove large triangles")

        with o3d.utility.VerbosityContextManager(o3d.utility.VerbosityLevel.Debug) as cm:
            # Assuming 'mesh' is your input mesh and it's already defined

            # Compute edge lengths for each triangle
            def compute_edge_lengths(mesh):
                vertices = np.asarray(mesh.vertices)
                triangles = np.asarray(mesh.triangles)
                edge_lengths = []
                for triangle in triangles:
                    edge_lengths.append([
                        np.linalg.norm(vertices[triangle[i]] - vertices[triangle[(i + 1) % 3]])
                        for i in range(3)
                    ])
                return np.array(edge_lengths)

        edge_lengths = compute_edge_lengths(mesh)

        # Identify triangles with any edge length exceeding the threshold
        triangles_to_remove = np.any(edge_lengths > threshold, axis=1)

        # Remove those triangles
        mesh.remove_triangles_by_mask(triangles_to_remove)

        # You might want to clean up the mesh afterwards
        mesh.remove_unreferenced_vertices()
        mesh.remove_non_manifold_edges()

        # Generate unique filenames for each output
        output_mesh_file = f"{output_name}_mesh_{idx}.ply"
        output_point_cloud_file = f"{output_name}_point_cloud_{idx}.pcd"

        # Save processed mesh and point cloud
        o3d.io.write_triangle_mesh(output_mesh_file, mesh)
        o3d.io.write_point_cloud(output_point_cloud_file, pcd)

        # Optionally open a viewer for each processed point cloud
        custom_draw_geometry([mesh], name=f"Viewer_{idx}")
        
        return mesh

def merge_point_clouds(point_clouds):
    global_pcd = o3d.geometry.PointCloud()
    for obj in point_clouds:
        global_pcd += obj.pcd
    return global_pcd

def custom_draw_geometry(pcd, name="Open3D"):
    vis = o3d.visualization.Visualizer()
    vis.create_window(name)
    for p in pcd:
        vis.add_geometry(p)
    vis.run()
    vis.destroy_window()

# Define additional functions as needed, such as `find_sift_matches` if you're still doing feature-based processing without poses.

