import open3d as o3d
import numpy as np

def invert_mesh_triangles_and_save(input_file_path, output_file_path):
    point_cloud = o3d.io.read_point_cloud(input_file_path)
    cl, ind = point_cloud.remove_statistical_outlier(nb_neighbors=20, std_ratio=2.0)
    point_cloud = point_cloud.select_by_index(ind)

    if not point_cloud.has_normals():
        point_cloud.estimate_normals()

    distances = point_cloud.compute_nearest_neighbor_distance()
    avg_spacing = np.mean(distances)

    radii = [avg_spacing * factor for factor in [0.5, 1, 2, 4]]
    mesh = o3d.geometry.TriangleMesh.create_from_point_cloud_ball_pivoting(
        point_cloud, o3d.utility.DoubleVector(radii))

    if mesh.is_empty():
        raise ValueError("Mesh conversion resulted in an empty mesh.")

    mesh.triangles = o3d.utility.Vector3iVector(np.asarray(mesh.triangles)[:, [2, 1, 0]])
    mesh.compute_vertex_normals()

    o3d.io.write_triangle_mesh(output_file_path, mesh)
    return output_file_path