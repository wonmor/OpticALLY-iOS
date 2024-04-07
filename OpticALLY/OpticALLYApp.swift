//
//  OpticALLYApp.swift
//  OpticALLY
//
//  Created by John Seong on 9/10/23.
//

import SwiftUI
import UIKit
import SystemConfiguration
import DevicePpi
import PythonSupport
import PythonKit
import Open3DSupport
import NumPySupport
import Accelerate
import opencv2

/// OpticALLYApp is the main entry point for the OpticALLY application, which is designed to use advanced computer vision and 3D reconstruction techniques to analyze and manipulate spatial data. This SwiftUI application integrates various technologies, including Python libraries for computational geometry and machine learning, to provide functionalities such as face tracking, 3D scanning, and object recognition.

/// The application initializes Python environments, loads necessary Python libraries, and sets up the infrastructure for reading and processing 3D data. It also includes utilities for matrix operations, singular value decomposition (SVD), and network connectivity checks, essential for data processing and analysis tasks.

/// Main Features:
/// - Face Tracking: Utilizes device capabilities and custom algorithms for real-time face tracking.
/// - 3D Scanning: Employs 3D reconstruction algorithms to scan objects and environments, creating detailed 3D models.
/// - Object Recognition: Integrates machine learning models to identify and classify objects within the scanned data.

/// Technical Details:
/// - Python Integration: Leverages PythonSupport and PythonKit for running Python code within the Swift environment.
/// - 3D Data Processing: Uses Open3DSupport and NumPySupport for handling 3D point clouds and numerical operations.
/// - Performance Optimization: Incorporates Accelerate framework for efficient matrix computations and linear algebra operations.

/// Usage:
/// The application's main view is managed by ContentView, which adapts its display based on the current application state, controlled by GlobalState. Users can navigate through different stages of the application, from introduction to scanning and post-scanning analysis, with the UI dynamically updating to reflect the current context.

/// Note: Due to the complex integration of Python and Swift, along with the use of external libraries for 3D data processing, it's crucial to manage resources wisely to ensure smooth performance and avoid memory leaks.

let devicePPI: Double = {
    switch Ppi.get() {
    case .success(let ppi):
        return ppi
    case .unknown(let bestGuessPpi, let error):
        // A bestGuessPpi value is provided but may be incorrect
        // Treat as a non-fatal error -- e.g. log to your backend and/or display a message
        return bestGuessPpi
    }
}()

func convertImageToBase64String(img: UIImage) -> String? {
    guard let imageData = img.jpegData(compressionQuality: 1.0) else { return nil }
    return imageData.base64EncodedString(options: .lineLength64Characters)
}

enum ViewState {
    case introduction
    case scanning
    case postScanning
}

class GlobalState: ObservableObject {
    @Published var currentView: ViewState = .introduction
}

var sys: PythonObject?
var o3d: PythonObject?
var np: PythonObject?
var imageDepth: PythonObject?

var standardOutReader: StandardOutReader?

@main
struct OpticALLYApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        DispatchQueue.global(qos: .userInitiated).async {
            PythonSupport.initialize()
            Open3DSupport.sitePackagesURL.insertPythonPath()
            NumPySupport.sitePackagesURL.insertPythonPath()
            
            sys = Python.import("sys")
            o3d = Python.import("open3d")
            np = Python.import("numpy")
            
            sys!.stdout = Python.open(NSTemporaryDirectory() + "stdout.txt", "w", encoding: "utf8")
            sys!.stderr = sys!.stdout
            
            print(sys!.stdout.encoding)
            
            standardOutReader = StandardOutReader(STDOUT_FILENO: Int32(sys!.stdout.fileno())!, STDERR_FILENO: Int32(sys!.stderr.fileno())!)
            
            sys!.path.insert(1, Bundle.main.bundlePath)
            
            imageDepth = Python.import("ImageDepth")
            
            print("Importing Python Code... \(imageDepth!.test_output())")
            print("Python \(sys!.version_info.major).\(sys!.version_info.minor)")
            print("Python Version: \(sys!.version)")
            print("Python Encoding: \(sys!.getdefaultencoding().upper())")
            print("Open3D Version: \(o3d!.__version__)")
        }
        
        for family: String in UIFont.familyNames
        {
            print(family)
            for names: String in UIFont.fontNames(forFamilyName: family)
            {
                print("== \(names)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(GlobalState())
        }
    }
    
    static func clearDocumentsFolder() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: [])
            for fileURL in fileURLs {
                try fileManager.removeItem(at: fileURL)
            }
            print("Cleared documents folder successfully.")
        } catch {
            print("Error clearing documents folder: \(error)")
        }
    }
    
    static func centroid(of matrix: [[Double]]) -> [Double] {
        guard !matrix.isEmpty else { return [] }
        let length = Double(matrix.first!.count)
        return matrix.map { $0.reduce(0, +) / length }
    }

    static func subtractMean(from matrix: [[Double]], using mean: [Double]) -> [[Double]] {
        return matrix.enumerated().map { index, row in
            row.map { $0 - mean[index] } // Use row.map instead of row.enumerated().map
        }
    }
    
    static func transpose(_ matrix: [[Double]]) -> [[Double]] {
        guard let rowCount = matrix.first?.count else { return [] }
        return (0..<rowCount).map { index in
            matrix.map { $0[index] }
        }
    }

    static func matrixMultiply(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
        let m = A.count
        let n = B[0].count
        let p = B.count
        var result = Array(repeating: Array(repeating: 0.0, count: n), count: m)
        var flattenedA = A.flatMap { $0 }
        var flattenedB = B.flatMap { $0 }
        var flattenedResult = Array(repeating: 0.0, count: m*n)

        flattenedResult.withUnsafeMutableBufferPointer { resultPtr in
            flattenedA.withUnsafeBufferPointer { aPtr in
                flattenedB.withUnsafeBufferPointer { bPtr in
                    vDSP_mmulD(aPtr.baseAddress!, 1,
                               bPtr.baseAddress!, 1,
                               resultPtr.baseAddress!, 1,
                               vDSP_Length(m), vDSP_Length(n), vDSP_Length(p))
                }
            }
        }

        // Reconstruct the 2D result matrix from the flattened result array
        for i in 0..<m {
            for j in 0..<n {
                result[i][j] = flattenedResult[i*n + j]
            }
        }

        return result
    }

    static func svd(_ matrix: [[Double]]) -> (U: [[Double]], S: [Double], Vt: [[Double]]) {
        var jobu: Int8 = 65 // 'A' All M columns of U are returned in array U
        var jobvt: Int8 = 65 // 'A' All N rows of Vt are returned in the array Vt
        var m = __CLPK_integer(matrix.count)
        var n = __CLPK_integer(matrix[0].count)
        var a = matrix.flatMap { $0 }
        var lda = m
        var ldu = m
        var ldvt = n
        var wkOpt = 0.0
        var lwork = __CLPK_integer(-1)
        var info = __CLPK_integer(0)

        var s = [Double](repeating: 0.0, count: Int(min(m, n)))
        var u = [Double](repeating: 0.0, count: Int(m * m))
        var vt = [Double](repeating: 0.0, count: Int(n * n))
        var iwork = [__CLPK_integer](repeating: 0, count: 8 * Int(min(m, n)))

        // Query optimal workspace size
        dgesdd_(&jobu, &m, &n, &a, &lda, &s, &u, &ldu, &vt, &ldvt, &wkOpt, &lwork, &iwork, &info)

        lwork = __CLPK_integer(wkOpt)
        var work = [Double](repeating: 0.0, count: Int(lwork))

        // Compute SVD
        dgesdd_(&jobu, &m, &n, &a, &lda, &s, &u, &ldu, &vt, &ldvt, &work, &lwork, &iwork, &info)

        let U = Array(u).chunked(into: Int(m))
        let Vt = Array(vt).chunked(into: Int(n))

        return (U, s, Vt)
    }

    
    static func determinant(_ matrix: [[Double]]) -> Double {
        guard matrix.count == 3 && matrix[0].count == 3 else {
            fatalError("Determinant can only be calculated for a 3x3 matrix.")
        }
        let a = matrix[0][0], b = matrix[0][1], c = matrix[0][2]
        let d = matrix[1][0], e = matrix[1][1], f = matrix[1][2]
        let g = matrix[2][0], h = matrix[2][1], i = matrix[2][2]
        return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    }

    
    static func matrixMultiplyVector(_ matrix: [[Double]], _ vector: [Double]) -> [Double] {
        var result = [Double](repeating: 0.0, count: matrix.count)
        for i in 0..<matrix.count {
            result[i] = zip(matrix[i], vector).map(*).reduce(0, +)
        }
        return result
    }

    static func subtractVectors(_ A: [Double], _ B: [Double]) -> [Double] {
        return zip(A, B).map(-)
    }
    
    static func rigidTransform3D(A: [[Double]], B: [[Double]]) -> (rotation: [[Double]], translation: [Double]) {
        print("I... \(A.count) \(B.count)")
        
        // Ensure A and B are 3xN
        guard A.count == 3, B.count == 3 else {
            fatalError("Input matrices A and B must be 3xN.")
        }

        // Compute centroids and subtract mean
        let centroidA = centroid(of: A)
        let centroidB = centroid(of: B)
        let Am = subtractMean(from: A, using: centroidA)
        let Bm = subtractMean(from: B, using: centroidB)

        // Compute matrix H and perform SVD
        let H = matrixMultiply(Am, transpose(Bm))
        let (U, _, Vt) = svd(H)

        // Compute rotation matrix R
        var R = matrixMultiply(Vt, transpose(U))
        if determinant(R) < 0 {
            print("Reflection detected, correcting for it...")
            R[2] = R[2].map { $0 * -1 }
            R = matrixMultiply(Vt, transpose(U))
        }

        // Compute translation vector t
        let t = subtractVectors(centroidB, matrixMultiplyVector(R, centroidA))

        return (R, t)
    }
    
    static func pairwiseRegistration(source: PythonObject, target: PythonObject, maxCorrespondenceDistanceCoarse: Double, maxCorrespondenceDistanceFine: Double) -> (PythonObject, PythonObject) {
        print("Apply point-to-plane ICP")
        let icpCoarse = o3d!.pipelines.registration.registration_icp(
            source, target, maxCorrespondenceDistanceCoarse, np!.identity(4),
            o3d!.pipelines.registration.TransformationEstimationPointToPlane())
        let icpFine = o3d!.pipelines.registration.registration_icp(
            source, target, maxCorrespondenceDistanceFine,
            icpCoarse.transformation,
            o3d!.pipelines.registration.TransformationEstimationPointToPlane())
        
        let transformationIcp = icpFine.transformation
        let informationIcp = o3d!.pipelines.registration.get_information_matrix_from_point_clouds(
            source, target, maxCorrespondenceDistanceFine, icpFine.transformation)
        
        return (transformationIcp, informationIcp)
    }
    
    static func fullRegistration(pcds: [PythonObject], maxCorrespondenceDistanceCoarse: Double, maxCorrespondenceDistanceFine: Double) -> PythonObject {
        let poseGraph = o3d!.pipelines.registration.PoseGraph()
        var odometry = np!.identity(4)
        poseGraph.nodes.append(o3d!.pipelines.registration.PoseGraphNode(odometry))
        
        for sourceId in 0..<pcds.count {
            for targetId in (sourceId + 1)..<pcds.count {
                let (transformationIcp, informationIcp) = pairwiseRegistration(
                    source: pcds[sourceId], target: pcds[targetId],
                    maxCorrespondenceDistanceCoarse: maxCorrespondenceDistanceCoarse,
                    maxCorrespondenceDistanceFine: maxCorrespondenceDistanceFine)
                
                print("Build o3d.pipelines.registration.PoseGraph")
                if targetId == sourceId + 1 {  // odometry case
                    odometry = np!.dot(transformationIcp, odometry)
                    poseGraph.nodes.append(
                        o3d!.pipelines.registration.PoseGraphNode(np!.linalg.inv(odometry)))
                    poseGraph.edges.append(
                        o3d!.pipelines.registration.PoseGraphEdge(sourceId, targetId,
                                                                  transformationIcp,
                                                                  informationIcp,
                                                                  uncertain: false))
                } else {  // loop closure case
                    poseGraph.edges.append(
                        o3d!.pipelines.registration.PoseGraphEdge(sourceId, targetId,
                                                                  transformationIcp,
                                                                  informationIcp,
                                                                  uncertain: true))
                }
            }
        }
        
        return poseGraph
    }
    
    static func base64StringToUIImage(base64String: String) -> UIImage? {
        // Decode the base64 string to Data
        guard let imageData = Data(base64Encoded: base64String) else {
            print("Error: Could not decode base64 string to Data")
            return nil
        }
        
        // Assuming the image data is in RGB format, create a CGImage from the data
        let imageWidth = 640  // Set the width of your image
        let imageHeight = 480  // Set the height of your image
        let bitsPerComponent = 8
        let bytesPerPixel = 3  // 3 bytes per pixel for RGB
        let bytesPerRow = bytesPerPixel * imageWidth
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Bitmap info: just the byte order, no alpha
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue

        guard let providerRef = CGDataProvider(data: imageData as CFData) else {
            print("Error: Could not create CGDataProvider from image data")
            return nil
        }

        guard let cgImage = CGImage(
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bytesPerPixel * bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: providerRef,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            print("Error: Could not create CGImage from provider")
            return nil
        }

        // Create UIImage from CGImage
        return UIImage(cgImage: cgImage)
    }
    
    // Fully on-device meshing...
    static func poissonReconstruction_PLYtoOBJ(json_string: String, image_file: String, depth_file: String) throws -> PythonObject {
        var imageDepthInstance: PythonObject?
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("temp", isDirectory: true)

        // Ensure the temporary directory exists
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

        // Get the list of files in the temporary directory
        let directoryContents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        
        // Filter out non-files and map to their names, focusing on .obj files
        let fileNames = directoryContents.filter { $0.pathExtension == "obj" }.map { $0.deletingPathExtension().lastPathComponent }
        
        // Extract the numeric parts of the filenames and find the maximum
        let fileIndices = fileNames.compactMap { Int($0) }
        let maxIndex = fileIndices.max() ?? 0 // Start from 0 if no files are found
        
        // Define the new filename using the next number in the sequence
        let newFileName = "\(maxIndex + 1)"

        // Define the output file path using the new file name
        let outputFilePath = tempDir.appendingPathComponent(newFileName).appendingPathExtension("obj")

        do {
            imageDepthInstance = imageDepth!.ImageDepth(json_string, image_file, depth_file)
            
            // Decode Base64 string to Data
            let imageLinear = base64StringToUIImage(base64String: String(imageDepthInstance!.get_image_linear())!)
            
            let src = Mat(uiImage: imageLinear!)
            
            let imgUndistort: Mat
            imgUndistort = Mat()
        
            let mapsAndDimensionsBase64 = String(imageDepthInstance!.get_maps_with_dimensions())!
            
            guard let jsonData = Data(base64Encoded: mapsAndDimensionsBase64),
                  let jsonString = String(data: jsonData, encoding: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let mapXBase64 = json["map_x"] as? String,
                  let mapYBase64 = json["map_y"] as? String,
                  let height = json["height"] as? Int,
                  let width = json["width"] as? Int else {
                fatalError("Failed to decode and parse JSON")
            }
            
            guard let mapXData = Data(base64Encoded: mapXBase64),
                  let mapYData = Data(base64Encoded: mapYBase64) else {
                fatalError("Failed to decode base64 strings for mapX and mapY")
            }

            // Convert the decoded Data to cv::Mat
            let mapXMat = createMat(from: mapXData, height: height, width: width)
            let mapYMat = createMat(from: mapYData, height: height, width: width)

            // Use remap to undistort the source image
            Imgproc.remap(src: src, dst: imgUndistort, map1: mapXMat, map2: mapYMat, interpolation: InterpolationFlags.INTER_LINEAR.rawValue)
            
            let imgUndistortBase64 = convertImageToBase64String(img: imgUndistort.toUIImage())
            
            imageDepthInstance!.set_image_undistort(imgUndistortBase64)
            
            imageDepthInstance!.load_depth()
            
            let depthMapAndDimensionsBase64 = String(imageDepthInstance!.get_depth_map_with_dimensions())!
            
            guard let jsonData = Data(base64Encoded: depthMapAndDimensionsBase64),
                  let jsonString = String(data: jsonData, encoding: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let depthMapBase64 = json["depth_map"] as? String,
                  let height = json["height"] as? Int,
                  let width = json["width"] as? Int else {
                fatalError("Failed to decode and parse JSON")
            }
            
            guard let depthMapData = Data(base64Encoded: depthMapBase64) else {
                fatalError("Failed to decode base64 strings for mapX and mapY")
            }

            // Convert the decoded Data to cv::Mat
            let depthMapMat = createMat(from: depthMapData, height: height, width: width)
            
            let depthMapUndistort: Mat
            depthMapUndistort = Mat()
            
            // Use remap to undistort the depth map
            Imgproc.remap(src: depthMapMat, dst: depthMapUndistort, map1: mapXMat, map2: mapYMat, interpolation: InterpolationFlags.INTER_LINEAR.rawValue)
            
            let depthMapUndistortBase64 = convertImageToBase64String(img: depthMapUndistort.toUIImage())
            
            imageDepthInstance!.set_depth_undistort(depthMapUndistortBase64)
            
            imageDepthInstance!.estimate_normals()
        }

        // Return the output file path, assuming the rest of the process creates or updates the OBJ file at this path
        return imageDepthInstance!
    }
    
    static func createMat(from data: Data, height: Int, width: Int) -> Mat {
        let size = Size(width: Int32(width), height: Int32(height))
        let mat = Mat(size: size, type: CvType.CV_32FC1, scalar: Scalar(0))

        // Access the bytes of the Data object
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            if let baseAddress = bytes.baseAddress {
                let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
                for y in 0..<height {
                    for x in 0..<width {
                        let value = floatBuffer[y * width + x]
                        do {
                            try mat.put(row: Int32(y), col: Int32(x), data: [value])
                        } catch {
                            print("Error putting data into Mat: \(error)")
                            return
                        }
                    }
                }
            }
        }

        return mat
    }

    static func ballPivotingSurfaceReconstruction_PLYtoOBJ(fileURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("temp", isDirectory: true)
        
        // Define the input and output file paths
        let inputFilePath = tempDir.appendingPathComponent(fileURL.lastPathComponent)
        let outputFilePath = inputFilePath.deletingPathExtension().appendingPathExtension("obj")
        
        // Remove the existing input file if it exists to avoid the 'item already exists' error
        if fileManager.fileExists(atPath: inputFilePath.path) {
            try fileManager.removeItem(at: inputFilePath)
        }
        
        // Create the temporary directory if it doesn't exist
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        
        // Copy the file to the temporary directory now that we've ensured there are no conflicts
        try fileManager.copyItem(at: fileURL, to: inputFilePath)
        
        do {
            let pointCloud = o3d!.io.read_point_cloud(inputFilePath.path)
            // let outlierRemovalResult = pointCloud.remove_statistical_outlier(nb_neighbors: 20, std_ratio: 2.0)
            // let filteredPointCloud = pointCloud.select_by_index(outlierRemovalResult[1])
            let filteredPointCloud = pointCloud
            
            if !Bool(filteredPointCloud.has_normals())! {
                filteredPointCloud.estimate_normals()
            }
            
            let distances = filteredPointCloud.compute_nearest_neighbor_distance()
            let avgSpacing = Double(np!.mean(distances))!
            let radii = [0.5, 1, 2, 4].map { avgSpacing * $0 }
            let mesh = o3d!.geometry.TriangleMesh.create_from_point_cloud_ball_pivoting(
                filteredPointCloud,
                o3d!.utility.DoubleVector(radii.map { PythonObject($0) })
            )
            
            if Bool(mesh.is_empty())! {
                throw NSError(domain: "AppErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mesh conversion resulted in an empty mesh."])
            }
            
            mesh.compute_vertex_normals()
            
            o3d!.io.write_triangle_mesh(outputFilePath.path, mesh)
            
            // Clean up the input file
            try FileManager.default.removeItem(at: inputFilePath)
            
            return outputFilePath
            
        } catch {
            // Clean up in case of failure
            if FileManager.default.fileExists(atPath: inputFilePath.path) {
                try? FileManager.default.removeItem(at: inputFilePath)
            }
            throw error
        }
    }
    
    // Network Reachability Check
    static func isConnectedToNetwork() -> Bool {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let defaultRouteReachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            return false
        }
        
        var flags: SCNetworkReachabilityFlags = []
        if !SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) {
            return false
        }
        
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        
        return (isReachable && !needsConnection)
    }
}

class PythonBridge: NSObject {
    @objc func input(_ prompt: String) -> String {
        Buffer.shared.append(prompt)
        //        print(prompt)
        return Buffer.shared.read()
    }
}

class Buffer: ObservableObject {
    static let shared = Buffer()
    
    @Published var text = ""
    
    @Published var input = ""
    
    var inputs: [String] = []
    
    let semaphore = DispatchSemaphore(value: 0)
    
    func append(_ string: String) {
        DispatchQueue.main.async {
            self.text.append(string)
        }
    }
    
    func read() -> String {
        if inputs.isEmpty {
            standardOutReader?.isBufferEnabled = false
            semaphore.wait()
            standardOutReader?.isBufferEnabled = true
        }
        return inputs.removeFirst()
    }
    
    func onCommit() {
        var t = input
        let table = [
            "\u{2018}": "\'", // ‘
            "\u{2019}": "\'", // ’
            "\u{201C}": "\"", // “
            "\u{201D}": "\"", // ”
        ]
        for (c, r) in table {
            t = t.replacingOccurrences(of: c, with: r)
        }
        print(input, "->", t)
        
        text.append(t.appending("\n"))
        inputs.append(t)
        input = ""
        semaphore.signal()
    }
}

class StandardOutReader {
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    
    var isBufferEnabled = true
    
    static var outputLines: [String] = [] // Array to store output lines
    
    init(STDOUT_FILENO: Int32 = Darwin.STDOUT_FILENO, STDERR_FILENO: Int32 = Darwin.STDERR_FILENO) {
        dup2(STDOUT_FILENO, outputPipe.fileHandleForWriting.fileDescriptor)
        
        dup2(inputPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(inputPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        // listening on the readabilityHandler
        inputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            
            self?.outputPipe.fileHandleForWriting.write(data)
            
            guard self?.isBufferEnabled ?? false else {
                return
            }
            
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.split(separator: "\n").map(String.init)
                DispatchQueue.main.async {
                    StandardOutReader.outputLines.append(contentsOf: lines)
                }
            }
            
            let str = String(data: data, encoding: .ascii) ?? "<Non-ascii data of size\(data.count)>\n"
            DispatchQueue.main.async {
                Buffer.shared.text += str
            }
        }
    }
}
