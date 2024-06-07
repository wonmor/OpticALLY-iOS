import open3d as o3d
import numpy as np
# import cv2 as cv
import json
import struct
import base64

class ImageDepth:
    def __init__(self, calibration_file, image_file, depth_file, width=640, height=480, min_depth=0.1, max_depth=0.5, normal_radius=0.1):
        self.image_file = image_file
        self.calibration_file = calibration_file
        self.depth_file = depth_file
        self.width = width
        self.height = height
        self.min_depth = min_depth
        self.max_depth = max_depth
        self.normal_radius = normal_radius
        self.pose = np.eye(4, 4)

        self.load_calibration(calibration_file)
        self.create_undistortion_lookup()
        self.load_image(image_file)
        self.load_depth(depth_file)

    def load_calibration(self, file):
        with open(file) as f:
            data = json.load(f)

            lensDistortionLookupBase64 = data["lensDistortionLookup"]
            inverseLensDistortionLookupBase64 = data["inverseLensDistortionLookup"]
            lensDistortionLookupBytes = base64.decodebytes(lensDistortionLookupBase64.encode("ascii"))
            inverseLensDistortionLookupBytes = base64.decodebytes(inverseLensDistortionLookupBase64.encode("ascii"))

            lensDistortionLookup = struct.unpack(f'<{len(lensDistortionLookupBytes)//4}f', lensDistortionLookupBytes)
            inverseLensDistortionLookup = struct.unpack(f'<{len(inverseLensDistortionLookupBytes)//4}f', inverseLensDistortionLookupBytes)

            self.lensDistortionLookup = lensDistortionLookup
            self.inverseLensDistortionLookup = inverseLensDistortionLookup

            # Debug prints
            print("Lens Distortion Lookup:", self.lensDistortionLookup)
            print("Inverse Lens Distortion Lookup:", self.inverseLensDistortionLookup)

            self.intrinsic = np.array(data["intrinsic"]).reshape((3, 3)).transpose()

            # Debug print
            print("Intrinsic Matrix before scaling:\n", self.intrinsic)

            self.scale = float(self.width) / data["intrinsicReferenceDimensionWidth"]
            self.intrinsic[0, 0] *= self.scale
            self.intrinsic[1, 1] *= self.scale
            self.intrinsic[0, 2] *= self.scale
            self.intrinsic[1, 2] *= self.scale

            # Debug print
            print("Intrinsic Matrix after scaling:\n", self.intrinsic)

    def create_undistortion_lookup(self):
        xy_pos = [(x, y) for y in range(self.height) for x in range(self.width)]
        print("xy_pos (first 10 values):\n", xy_pos[:10])  # Debug

        xy = np.array(xy_pos, dtype=np.float32).reshape(-1, 2)
        print("xy (first 10 values):\n", xy[:10])  # Debug

        # Subtract center
        center = self.intrinsic[:2, 2]
        print("center:\n", center)  # Debug

        xy -= center
        print("xy after subtracting center (first 10 values):\n", xy[:10])  # Debug

        # Calculate radius from center
        r = np.sqrt(xy[:, 0]**2 + xy[:, 1]**2)
        print("radius r (first 10 values):\n", r[:10])  # Debug

        # Normalize radius
        max_r = np.max(r)
        print("max_r:\n", max_r)  # Debug

        norm_r = r / max_r
        print("normalized radius norm_r (first 10 values):\n", norm_r[:10])  # Debug

        # Interpolate the scale
        table = self.inverseLensDistortionLookup
        print("inverseLensDistortionLookup table:\n", table)  # Debug

        num = len(table)
        print("num:\n", num)  # Debug

        scale = 1.0 + np.interp(norm_r * num, np.arange(num), table)
        print("scale (first 10 values):\n", scale[:10])  # Debug

        new_xy = xy * np.expand_dims(scale, 1) + center
        print("new_xy (first 10 values):\n", new_xy[:10])  # Debug

        self.map_x = new_xy[:, 0].reshape((self.height, self.width)).astype(np.float32)
        print("map_x (first 10 values):\n", self.map_x.flatten()[:10])  # Debug

        self.map_y = new_xy[:, 1].reshape((self.height, self.width)).astype(np.float32)
        print("map_y (first 10 values):\n", self.map_y.flatten()[:10])  # Debug

    def load_depth(self, file):
        print(f"Loading depth file {file}")
        depth = np.fromfile(file, dtype='float32').astype(np.float32)
        print("Loaded depth data (first 10 values):", depth[:10])

        # Vectorized version, faster
        # All possible (x, y) positions
        idx = np.arange(self.width * self.height)
        xy = np.zeros((self.width * self.height, 2), dtype=np.float32)

        xy[:, 0] = np.mod(idx, self.width)
        xy[:, 1] = idx // self.width
        print("Generated xy positions (first 10 values):", xy[:10])

        # Remove bad values
        no_nan = np.invert(np.isnan(depth))
        depth1 = depth > self.min_depth
        depth2 = depth < self.max_depth
        idx = no_nan & depth1 & depth2
        print("Filtered valid depth indices (first 10 values):", idx[:10])

        print("Initial sizes:")
        print("xy shape:", xy.shape)
        print("img_undistort shape:", self.img_undistort.shape)
        print("idx size:", len(idx))

        xy = xy[np.where(idx)]
        img_undistort = self.img_undistort.reshape(-1, 3)
        rgb = img_undistort[np.where(idx)] / 255.0

        print("Filtered xy positions (first 10 values):", xy[:10])
        print("Filtered rgb values (first 10 values):", rgb[:10])

        print("Filtered sizes:")
        print("xy_filtered shape:", xy.shape)
        print("rgb_filtered shape:", rgb.shape)

        self.mask = np.ones(self.height * self.width, dtype=np.uint8) * 255
        self.mask[np.where(idx == False)] = 0
        self.mask = self.mask.reshape((self.height, self.width))
        print("Generated mask (first 10 values):", self.mask.flatten()[:10])

        # Mask out depth buffer
        self.depth_map = depth
        self.depth_map[np.where(idx == False)] = -1000
        self.depth_map = self.depth_map.reshape((self.height, self.width, 1))
        print("Generated depth map with mask (first 10 values):", self.depth_map.flatten()[:10])

        # Debug prints
        print("Depth map (first 10 values):", self.depth_map.flatten()[:10])

        self.undistort_depth_map()

        per = float(np.sum(idx == True)) / len(depth)
        print(f"Processing {file}, keeping={np.sum(idx == True)}/{len(depth)} ({per:.3f}) points")

        depth = np.expand_dims(self.depth_map_undistort.flatten()[np.where(idx)], 1)
        print("Expanded depth map for valid indices (first 10 values):", depth[:10])

        # Project to 3D
        xyz, _, good_idx = self.project3d(xy)
        xyz = xyz[good_idx]
        rgb = rgb[good_idx]
        print("Filtered projected 3D points (first 10 values):", xyz[:10])
        print("Filtered rgb values for 3D points (first 10 values):", rgb[:10])

        self.pcd = o3d.geometry.PointCloud()
        self.pcd.points = o3d.utility.Vector3dVector(xyz)
        self.pcd.colors = o3d.utility.Vector3dVector(rgb)

        # Calculate normal, required for ICP point-to-plane
        self.pcd.estimate_normals(search_param=o3d.geometry.KDTreeSearchParamHybrid(radius=self.normal_radius, max_nn=30))
        self.pcd.orient_normals_towards_camera_location()
        print("Estimated and oriented normals for point cloud")

    def project3d(self, pts):
        # Expect pts to be Nx2
        xy = np.round(pts).astype(int)
        print("Rounded xy positions (first 10 values):", xy[:10])

        fx = self.intrinsic[0, 0]
        fy = self.intrinsic[1, 1]
        cx = self.intrinsic[0, 2]
        cy = self.intrinsic[1, 2]

        depths = self.depth_map_undistort[xy[:, 1], xy[:, 0]]
        depths = np.expand_dims(depths, 1)
        print("Depths size:", depths.shape)
        print("xy size:", xy.shape)

        good_idx = np.where((depths > self.min_depth) & (depths < self.max_depth))[0]
        print("Filtered valid depths (first 10 values):", depths[:10])
        print("Good indices for valid depths (first 10 values):", good_idx[:10])

        pts = xy.astype(np.float32)
        pts -= np.array([cx, cy])
        pts /= np.array([fx, fy])
        pts *= depths
        pts = np.hstack((pts, depths))
        print("Projected 3D points (first 10 values):", pts[:10])

        return pts, xy, good_idx


    def undistort_depth_map(self):
        self.depth_map_undistort = cv.remap(self.depth_map, self.map_x, self.map_y, cv.INTER_LINEAR)
        # Debug print
        print("Undistorted depth map (first 10 values):", self.depth_map_undistort.flatten()[:10])

    def load_image(self, file):
        print(f"Loading {file}")
        self.img = np.fromfile(file, dtype='uint8')
        self.img = self.img.reshape((self.height, self.width, 4))
        self.img = self.img[:, :, :3]

        # Swap RB
        self.img = self.img[:, :, [2, 1, 0]]
        
        self.process_image()

    def process_image(self):
        # Convert the image from sRGB to linear space
        def srgb_to_linear(srgb):
            threshold = 0.04045
            below_threshold = srgb <= threshold
            linear_below = srgb / 12.92
            linear_above = ((srgb + 0.055) / 1.055) ** 2.4
            return np.where(below_threshold, linear_below, linear_above)

        # Apply sRGB to Linear conversion
        self.img_linear = srgb_to_linear(self.img.astype('float32') / 255.0)

        # Debug print
        print("Linear image (first 10 values):", self.img_linear.flatten()[:10])

        # Print first 10 values of map_x
        print("map_x (first 10 values):", self.map_x.flatten()[:10])

        # Print first 10 values of map_y
        print("map_y (first 10 values):", self.map_y.flatten()[:10])

        # Debug: Print shape and type of img_linear
        print(f"img_linear shape: {self.img_linear.shape}")
        print(f"img_linear dtype: {self.img_linear.dtype}")

        # Debug: Print max, min, and mean values of img_linear
        print(f"img_linear max value: {np.max(self.img_linear)}")
        print(f"img_linear min value: {np.min(self.img_linear)}")
        print(f"img_linear mean value: {np.mean(self.img_linear)}")

        # Convert img_linear to uint8 and multiply by 255
        img_linear_uint8 = (self.img_linear * 255).astype('uint8')

        # Debug: Print shape and type of img_linear_uint8
        print(f"img_linear_uint8 shape: {img_linear_uint8.shape}")
        print(f"img_linear_uint8 dtype: {img_linear_uint8.dtype}")

        # Debug: Print max, min, and mean values of img_linear_uint8
        print(f"img_linear_uint8 max value: {np.max(img_linear_uint8)}")
        print(f"img_linear_uint8 min value: {np.min(img_linear_uint8)}")
        print(f"img_linear_uint8 mean value: {np.mean(img_linear_uint8)}")

        # Debug: Print shape and type of map_x and map_y
        print(f"map_x shape: {self.map_x.shape}")
        print(f"map_x dtype: {self.map_x.dtype}")

        # Debug prints for map_x and map_y statistics
        print("map_x max value:", np.max(self.map_x))
        print("map_x min value:", np.min(self.map_x))
        print("map_x mean value:", np.mean(self.map_x))

        print(f"map_y shape: {self.map_y.shape}")
        print(f"map_y dtype: {self.map_y.dtype}")

        print("map_y max value:", np.max(self.map_y))
        print("map_y min value:", np.min(self.map_y))
        print("map_y mean value:", np.mean(self.map_y))

        # Apply remap
        self.img_undistort = cv.remap(img_linear_uint8, self.map_x, self.map_y, cv.INTER_LINEAR)

        # Debug: Print shape and type of img_undistort
        print(f"img_undistort shape: {self.img_undistort.shape}")
        print(f"img_undistort dtype: {self.img_undistort.dtype}")

        # Debug: Print max, min, and mean values of img_undistort
        print(f"img_undistort max value: {np.max(self.img_undistort)}")
        print(f"img_undistort min value: {np.min(self.img_undistort)}")
        print(f"img_undistort mean value: {np.mean(self.img_undistort)}")

        # Debug print
        print("Undistorted image (first 10 values):", self.img_undistort.flatten()[:10])

        # Print reshaped img_undistort
        reshaped_img = self.img_undistort.reshape(1, -1)
        print("Reshaped img_undistort (first 10 values):", reshaped_img.flatten()[:10])

# Usage example
# image_depth = ImageDepth("calibration.json", "image.bin", "depth.bin")
# point_cloud = image_depth.pcd
