//
//  ExternalData.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import UIKit
import AVFoundation
import CoreVideo
import SceneKit
import ARKit
import Foundation

/// ExternalData is a central repository for managing and processing 3D depth and color data, primarily focusing on creating point cloud geometries and exporting them in PLY format. It enables the integration of various sensory data inputs and computational geometry processing.

/// This struct is essential for applications dealing with 3D reconstruction, AR experiences, or any scenario where real-world spatial data needs to be captured and manipulated. Use ExternalData to generate and manage 3D point cloud geometries from depth and color data.

/// Example Usage:
/// /// ExternalData.createPointCloudGeometry(depthData: depthData, colorData: colorBuffer, width: width, height: height, bytesPerRow: bytesPerRow, calibrationData: calibrationData) /// ExternalData.exportGeometryAsPLY(to: fileURL) ///

/// > Note: The struct relies on depth data typically obtained from ARKit or similar frameworks and uses SceneKit for 3D geometry representation.

/// - Properties:
/// - renderingEnabled: A Boolean flag to enable or disable rendering.
/// - isSavingFileAsPLY: Indicates if the current operation involves saving data in PLY format.
/// - isMeshView: A Boolean to toggle between mesh view and other views.
/// - exportPLYData: Data object for storing PLY formatted data.
/// - pointCloudGeometries: An array of SCNGeometry objects representing the point clouds.
/// - faceYawAngle, facePitchAngle, faceRollAngle: Angles for face orientation in 3D space.
/// - verticesCount: The count of vertices in the current geometry.

/// - Methods:
/// - reset(): Resets and clears all the data, particularly the point cloud geometries.
/// - createPointCloudGeometry(...): Processes depth and color data to create a point cloud SCNGeometry.
/// - exportGeometryAsPLY(to:): Exports the current geometry as a PLY file to a specified URL.

/// - Notes:
/// - The struct uses advanced graphics frameworks like SceneKit and AVFoundation.
/// - It is designed to handle complex 3D data processing, making it suitable for AR applications or 3D modeling software.
/// - Care should be taken to manage memory efficiently, as 3D geometry processing can be resource-intensive.

struct ExternalData {
    static var renderingEnabled = true
    static var isSavingFileAsPLY = false
    static var isMeshView = false
    static var exportPLYData: Data?
    static var pointCloudGeometries: [SCNGeometry] = []
    static var faceYawAngle: Double = 0.0
    static var facePitchAngle: Double = 0.0
    static var faceRollAngle: Double = 0.0
    static var pupilDistance: Double = 0.0
    static var verticesCount: Int = 0
    static var faceAnchor: ARFaceAnchor?
    static var depthWidth: Int = 640
    static var depthHeight: Int = 480
    
    static func reset() {
        // Function to reset all variables
        pointCloudGeometries.removeAll()
    }
    
    // Function to convert depth and color data into a point cloud geometry
    static func createPointCloudGeometry(depthData: AVDepthData, imageSampler: CapturedImageSampler, width: Int, height: Int, calibrationData: AVCameraCalibrationData, percentile: Float = 35.0) {
        var vertices: [SCNVector3] = []
        var colors: [UIColor] = []
        var depthValues: [Float] = []
        
        let cameraIntrinsics = calibrationData.intrinsicMatrix
        
        let convertedDepthData = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16)
        let depthDataMap = convertedDepthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthDataMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthDataMap, .readOnly) }
        
        // Collect all depth values
        for y in 0..<height {
            for x in 0..<width {
                let depthOffset = y * CVPixelBufferGetBytesPerRow(depthDataMap) + x * MemoryLayout<UInt16>.size
                let depthPointer = CVPixelBufferGetBaseAddress(depthDataMap)!.advanced(by: depthOffset).assumingMemoryBound(to: UInt16.self)
                let depthValue = Float(depthPointer.pointee)
                depthValues.append(depthValue)
            }
        }
        
        let unsortedDepthValues = depthValues
        
        // Sort the depth values
        depthValues.sort()
        
        // Determine the depth threshold for the 30th percentile
        let index = Int(Float(depthValues.count) * percentile / 100.0)
        let depthThreshold = depthValues[max(0, min(index, depthValues.count - 1))]
        
        var counter = 1
        
        // Process points with depth values lower than the threshold
        for y in 0..<height {
            for x in 0..<width {
                let depthOffset = y * CVPixelBufferGetBytesPerRow(depthDataMap) + x * MemoryLayout<UInt16>.size
                let depthPointer = CVPixelBufferGetBaseAddress(depthDataMap)!.advanced(by: depthOffset).assumingMemoryBound(to: UInt16.self)
                let depthValue = Float(depthPointer.pointee)
                
                if depthValue > depthThreshold {
                    continue // Skip this point
                }
                
                // MARK - CUSTOM SCALE FACTOR
                let scaleFactor = Float(2.0) // Custom value for depth exaggeration
                
                let xrw = (Float(x) - cameraIntrinsics.columns.2.x) * depthValue / cameraIntrinsics.columns.0.x
                let yrw = (Float(y) - cameraIntrinsics.columns.2.y) * depthValue / cameraIntrinsics.columns.1.y
                let vertex = SCNVector3(x: xrw, y: yrw, z: depthValue * scaleFactor)
                
                vertices.append(vertex)
                
                // Get color using CapturedImageSampler
                let normalizedX = CGFloat(x) / CGFloat(width)
                let normalizedY = CGFloat(y) / CGFloat(height)
                if let color = imageSampler.getColor(atX: normalizedX, y: normalizedY) {
                    // Extract RGBA components from UIColor
                    var red: CGFloat = 0
                    var green: CGFloat = 0
                    var blue: CGFloat = 0
                    var alpha: CGFloat = 0
                    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

                    colors.append(color)
                }
                
                counter += 1
            }
        }
        
        // Create the geometry source for vertices
        let vertexSource = SCNGeometrySource(vertices: vertices)
        
        // Assuming the UIColor's data is not properly formatted for the SCNGeometrySource
        // Instead, create an array of normalized float values representing the color data
        
        // Convert UIColors to Float Components
        var colorComponents: [CGFloat] = []
        for color in colors {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            
            colorComponents += [red, green, blue, alpha]
        }
        
        // Create the geometry source for colors
        let colorData = NSData(bytes: colorComponents, length: colorComponents.count * MemoryLayout<CGFloat>.size)
        let colorSource = SCNGeometrySource(data: colorData as Data,
                                            semantic: .color,
                                            vectorCount: colors.count,
                                            usesFloatComponents: true,
                                            componentsPerVector: 4,
                                            bytesPerComponent: MemoryLayout<CGFloat>.size,
                                            dataOffset: 0,
                                            dataStride: MemoryLayout<CGFloat>.size * 4)
        
        // Combine Vertex and Color Sources
        let geometrySources = [vertexSource, colorSource]
        
        // Create the geometry element
        let indices: [Int32] = Array(0..<Int32(vertices.count))
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: indexData,
                                         primitiveType: .point,
                                         primitiveCount: vertices.count,
                                         bytesPerIndex: MemoryLayout<Int32>.size)
        
        // Create the point cloud geometry
       let newPointCloudGeometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
       newPointCloudGeometry.firstMaterial?.lightingModel = .constant
       newPointCloudGeometry.firstMaterial?.isDoubleSided = true
       
       // Append the new geometry to the array
       pointCloudGeometries.append(newPointCloudGeometry)
       
       print("Done constructing the 3D object!")
       LogManager.shared.log("Done constructing the 3D object!")
   }
    
    static func exportGeometryAsPLY(to url: URL) {
        guard let geometry: SCNGeometry? = pointCloudGeometries[0],
              let vertexSource = geometry!.sources.first(where: { $0.semantic == .vertex }),
              let colorSource = geometry!.sources.first(where: { $0.semantic == .color }) else {
            print("Unable to access vertex or color source from geometry")
            return
        }
        
        // Access vertex data
        guard let vertexData: Data? = vertexSource.data else {
            print("Unable to access vertex data")
            return
        }
        
        // Access color data
        guard let colorData: Data? = colorSource.data else {
            print("Unable to access color data")
            return
        }
        
        let vertexCount = vertexSource.vectorCount
        let vertices = vertexSource.data.toArray(type: SCNVector3.self, count: vertexCount)
        let colors = colorSource.data.toArray(type: Float.self, count: vertexCount * 4)
        
        var plyString = "ply\nformat ascii 1.0\nelement vertex \(vertexCount)\n"
        plyString += "property float x\nproperty float y\nproperty float z\n"
        plyString += "property uchar red\nproperty uchar green\nproperty uchar blue\nproperty uchar alpha\n"
        plyString += "end_header\n"
        
        for i in 0..<vertexCount {
            let vertex = vertices[i]
            let colorIndex = i * 4
            let color = colors[colorIndex..<colorIndex + 4].map { UInt8($0 * 255) }
            plyString += "\(vertex.x) \(vertex.y) \(vertex.z) \(color[0]) \(color[1]) \(color[2]) \(color[3])\n"
        }
        
        do {
            try plyString.write(to: url, atomically: true, encoding: .ascii)
            print("PLY file successfully saved to: \(url.path)")
        } catch {
            print("Failed to write PLY file: \(error)")
        }
    }
}
