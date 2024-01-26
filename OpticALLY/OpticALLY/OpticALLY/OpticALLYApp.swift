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
    
    static func convertToObj(fileURL: URL) throws -> URL {
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
            // Use PythonKit to interact with Python
            let o3d = Python.import("open3d")
            let np = Python.import("numpy")
            
            let pointCloud = o3d.io.read_point_cloud(inputFilePath.path)
            let outlierRemovalResult = pointCloud.remove_statistical_outlier(nb_neighbors: 20, std_ratio: 2.0)
            let filteredPointCloud = pointCloud.select_by_index(outlierRemovalResult[1])
            
            if !Bool(filteredPointCloud.has_normals())! {
                filteredPointCloud.estimate_normals()
            }
            
            let distances = filteredPointCloud.compute_nearest_neighbor_distance()
            let avgSpacing = Double(np.mean(distances))!
            let radii = [0.5, 1, 2, 4].map { avgSpacing * $0 }
            let mesh = o3d.geometry.TriangleMesh.create_from_point_cloud_ball_pivoting(
                filteredPointCloud,
                o3d.utility.DoubleVector(radii.map { PythonObject($0) })
            )
            
            if Bool(mesh.is_empty())! {
                throw NSError(domain: "AppErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mesh conversion resulted in an empty mesh."])
            }
            
            // Perform the triangle inversion using Python's slice directly
            //                   let invertedTriangles = np.asarray(mesh.triangles)[:, Python.slice(None, None, None)].getitem([2, 1, 0])
            //                   mesh.triangles = o3d.utility.Vector3iVector(invertedTriangles)
            mesh.compute_vertex_normals()
            
            o3d.io.write_triangle_mesh(outputFilePath.path, mesh)
            
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
            
            let str = String(data: data, encoding: .ascii) ?? "<Non-ascii data of size\(data.count)>\n"
            DispatchQueue.main.async {
                Buffer.shared.text += str
            }
        }
    }
}
