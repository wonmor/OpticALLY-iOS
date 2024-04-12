import open3d as o3d
import numpy as np

import json
import struct
import base64

import pickle
import codecs

def test_output():
    return "Hello from ImageDepth"

class ImageDepth:
    def __init__(self,
        json_string,
        image_file,
        depth_file,
        width=640,
        height=480,
        min_depth=0.1,
        max_depth=0.5,
        normal_radius=0.01) :

        self.image_file = image_file
        self.json_string = json_string
        self.depth_file = depth_file
        self.width = width
        self.height = height
        self.min_depth = min_depth
        self.max_depth = max_depth
        self.normal_radius = normal_radius
        self.pose = np.eye(4, 4)

        self.load_calibration(json_string)
        self.create_undistortion_lookup()
        
        self.load_image(image_file)
        self.process_image()

        # self.estimate_normals(idx, file, xy)
        
    def load_image(self, file):
        print(f"Loading {file}")
        self.img = np.fromfile(file, dtype='uint8')
        self.img = self.img.reshape((self.height, self.width, 4))
        self.img = self.img[:,:,0:3]

        # swap RB
        self.img = self.img[:,:,[2,1,0]]

    def test_output2(self):
        return "Hello inside ImageDepth"

    def load_calibration(self, json_string):
        data = json.loads(json_string)

        lensDistortionLookupBase64 = data["lensDistortionLookup"]
        inverseLensDistortionLookupBase64 = data["inverseLensDistortionLookup"]
        lensDistortionLookupByte = base64.decodebytes(lensDistortionLookupBase64.encode("ascii"))
        inverseLensDistortionLookupByte = base64.decodebytes(inverseLensDistortionLookupBase64.encode("ascii"))

        lensDistortionLookup = struct.unpack(f"<{len(lensDistortionLookupByte)//4}f", lensDistortionLookupByte)
        inverseLensDistortionLookup = struct.unpack(f"<{len(inverseLensDistortionLookupByte)//4}f", inverseLensDistortionLookupByte)

        self.lensDistortionLookup = lensDistortionLookup
        self.inverseLensDistortionLookup = inverseLensDistortionLookup

        self.intrinsic = np.array(data["intrinsic"]).reshape((3,3))
        self.intrinsic = self.intrinsic.transpose()

        self.scale = float(self.width) / data["intrinsicReferenceDimensionWidth"]
        self.intrinsic[0,0] *= self.scale
        self.intrinsic[1,1] *= self.scale
        self.intrinsic[0,2] *= self.scale
        self.intrinsic[1,2] *= self.scale

    def create_undistortion_lookup(self):
        xy_pos = [(x,y) for y in range(0, self.height) for x in range(0, self.width)]
        xy = np.array(xy_pos, dtype=np.float32).reshape(-1,2)

        # subtract center
        center = self.intrinsic[0:1, 2]
        xy -= center

        # calc radius from center
        r = np.sqrt(xy[:,0]**2 + xy[:,1]**2)

        # normalize radius
        max_r = np.max(r)
        norm_r = r / max_r

        # interpolate the scale
        table = self.inverseLensDistortionLookup
        num = len(table)
        scale = 1.0 + np.interp(norm_r*num, np.arange(0, num), table)

        new_xy = xy*np.expand_dims(scale, 1) + center

        self.map_x = new_xy[:,0].reshape((self.height, self.width)).astype(np.float32)
        self.map_y = new_xy[:,1].reshape((self.height, self.width)).astype(np.float32)

    def load_depth(self):
        global idx, xy

        depth = np.fromfile(self.depth_file, dtype='float32').astype(np.float32)

        idx = np.arange(0, self.width*self.height)
        xy = np.zeros((self.width*self.height, 2), dtype=np.float32)

        xy[:,0] = np.mod(idx, self.width)
        xy[:,1] = idx // self.width

        # Remove bad values
        no_nan = np.invert(np.isnan(depth))
        depth1 = depth > self.min_depth
        depth2 = depth < self.max_depth
        idx = no_nan & depth1 & depth2

        if self.img_undistort.size == self.width * self.height * 3:
            # Ensure the image undistort is reshaped correctly
            self.img_undistort = self.img_undistort.reshape((self.height, self.width, 3))
            rgb = self.img_undistort.reshape(-1, 3)[idx] / 255.0
        else:
            print("Error: img_undistort size mismatch or incorrect reshaping parameters.")

        self.mask = np.ones(self.height*self.width, dtype=np.uint8)*255
        self.mask[np.where(idx == False)] = 0
        self.mask = self.mask.reshape((self.height, self.width))

        # mask out depth buffer
        self.depth_map = depth
        self.depth_map[np.where(idx == False)] = -1000
        self.depth_map = self.depth_map.reshape((self.height, self.width, 1))

    def estimate_normals(self):
        per = float(np.sum(idx==True))/len(depth)
        print(f"Processing {self.depth_file}, keeping={np.sum(idx==True)}/{len(depth)} ({per:.3f}) points")

        depth = np.expand_dims(self.depth_map_undistort.flatten()[np.where(idx)],1)

        # project to 3D
        xyz, _, good_idx = self.project3d(xy)
        xyz = xyz[good_idx]
        rgb = rgb[good_idx]

        self.pcd = o3d.geometry.PointCloud()
        self.pcd.points = o3d.utility.Vector3dVector(xyz)
        self.pcd.colors = o3d.utility.Vector3dVector(rgb)

        # calc normal, required for ICP point-to-plane
        self.pcd.estimate_normals(search_param=o3d.geometry.KDTreeSearchParamHybrid(radius=self.normal_radius, max_nn=30))
        self.pcd.orient_normals_towards_camera_location()
        
    def convert_rgb_image_to_base64(self, numpy_array):
        # Ensure the array is of type uint8
        assert numpy_array.dtype == np.uint8, "The input array should be of type np.uint8"

        # Convert the numpy array to bytes
        img_bytes = numpy_array.tobytes()

        # Encode the bytes to Base64
        base64_string = base64.b64encode(img_bytes).decode('utf-8')

        return base64_string
        
    def get_image_linear(self):
        return self.convert_rgb_image_to_base64((self.img_linear * 255).astype('uint8'))

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
        
    def numpy_array_to_base64(self, numpy_array):
        # Convert the NumPy array to bytes. For uint8 arrays, this is straightforward.
        # For float32 arrays, you need to ensure that the byte representation is preserved.
        # This is because the direct conversion of float32 to bytes and then to base64
        # can be decoded in Swift using Data(base64Encoded:) and then converted to the desired format.
        if numpy_array.dtype == np.uint8:
            # Directly convert uint8 numpy array to bytes
            array_bytes = numpy_array.tobytes()
        elif numpy_array.dtype == np.float32:
            # For float32 arrays, ensure that the byte representation is exact.
            # This might require flattening the array if it's multidimensional.
            flat_array = numpy_array.ravel()
            # Convert the flattened array to bytes
            array_bytes = flat_array.tobytes()
        else:
            raise ValueError("Unsupported numpy array data type. Expected uint8 or float32.")

        # Encode the bytes to Base64. The result is a Base64 encoded string that represents your numpy array.
        base64_string = base64.b64encode(array_bytes).decode('utf-8')

        return base64_string
        
    def get_maps_with_dimensions(self):
        data = {
            'map_x': self.numpy_array_to_base64(self.map_x),
            'map_y': self.numpy_array_to_base64(self.map_y),
            'height': self.height,
            'width': self.width
        }
        json_string = json.dumps(data)
        return base64.b64encode(json_string.encode()).decode()
        
    def get_depth_map_with_dimensions(self):
        data = {
            'depth_map': self.numpy_array_to_base64(self.depth_map),
            'height': self.height,
            'width': self.width
        }
        json_string = json.dumps(data)
        return base64.b64encode(json_string.encode()).decode()

    def set_img_undistort(self, img_undistort):
        self.img_undistort = self.base64_to_numpy_array(img_undistort)
        
    def set_depth_undistort(self, img_undistort):
        self.depth_undistort = self.base64_to_numpy_array_float32(img_undistort)
        
    def base64_to_numpy_array(self, base64_string):
        # Decode the base64 string
        img_bytes = base64.b64decode(base64_string)
        
        # Convert the bytes to a NumPy array
        return np.frombuffer(img_bytes, dtype=np.uint8)
        
    def base64_to_numpy_array_float32(self, base64_string):
        if base64_string is None or not isinstance(base64_string, str):
            raise ValueError("Invalid input: base64_string must be a non-empty string")

        # Decode the base64 string
        img_bytes = base64.b64decode(base64_string)

        # Convert the bytes to a NumPy array (convert uint8 to float32 which occured during transfer process from Swift, as conversion to UIImage was necessary which forces uint8 format)
        return np.frombuffer(img_bytes, dtype=np.uint8).astype(np.float32)
        
    def project3d(self, pts):
        # expect pts to be Nx2

        local_xy = np.round(pts).astype(int)

        fx = self.intrinsic[0,0]
        fy = self.intrinsic[1,1]
        cx = self.intrinsic[0,2]
        cy = self.intrinsic[1,2]

        depths = self.depth_map_undistort[local_xy[:,1], local_xy[:,0]]
        depths = np.expand_dims(depths, 1)
        good_idx = np.where((depths > self.min_depth) & (depths < self.max_depth))[0]

        pts -= np.array([cx, cy]) 
        pts /= np.array([fx, fy])
        pts *= depths
        pts = np.hstack((pts, depths))

        return pts, local_xy, good_idx
