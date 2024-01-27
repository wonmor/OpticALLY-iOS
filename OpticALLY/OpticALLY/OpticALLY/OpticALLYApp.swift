//
//  OpticALLYApp.swift
//  OpticALLY
//
//  Created by John Seong on 9/10/23.
//

import SwiftUI
import SystemConfiguration
import DevicePpi
import PythonSupport
import PythonKit
import Open3DSupport
import NumPySupport

let faceTrackingViewModel = FaceTrackingViewModel()

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
    
    let linalg = Python.import("numpy.linalg")
    
    func rigidTransform3D(A: PythonObject, B: PythonObject) -> (PythonObject, PythonObject) {
        let AShape = A.shape
        let BShape = B.shape
        
        // Ensure A and B are 3xN
        guard AShape[0] == 3, BShape[0] == 3 else {
            fatalError("Input matrices A and B must be 3xN. Received shapes: \(AShape) and \(BShape).")
        }
        
        // Compute centroids
        let centroidA = np!.mean(A, axis: 1).reshape(-1, 1)
        let centroidB = np!.mean(B, axis: 1).reshape(-1, 1)
        
        // Subtract mean
        let Am = A - centroidA
        let Bm = B - centroidB
        
        // Compute matrix H
        let H = np!.dot(Am, Bm.T)
        
        // Perform SVD
        let SVD = linalg.svd(H)
        let U = SVD[0]
        let Vt = SVD[2]
        
        // Compute rotation matrix R
        var R = np!.dot(Vt.T, U.T)
        
        // Check for reflection and correct if necessary
        if linalg.det(R) < 0 {
            print("Reflection detected, correcting for it...")
            Vt[2, Python.slice(Python.None)] *= -1
            R = np!.dot(Vt.T, U.T)
        }
        
        // Compute translation vector t
        let t = -np!.dot(R, centroidA) + centroidB
        
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
            let outlierRemovalResult = pointCloud.remove_statistical_outlier(nb_neighbors: 20, std_ratio: 2.0)
            let filteredPointCloud = pointCloud.select_by_index(outlierRemovalResult[1])
            
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
