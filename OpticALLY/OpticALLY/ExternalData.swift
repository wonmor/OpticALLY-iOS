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
import Compression
import ZipArchive

struct PointCloudMetadata {
    var yaw: Double
    var pitch: Double
    var roll: Double
    var leftEyePosition: SCNVector3
    var rightEyePosition: SCNVector3
    var noseTipPosition: SCNVector3
}

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
    static var pointCloudDataArray: [PointCloudMetadata] = []
    static var faceYawAngle: Double = 0.0
    static var facePitchAngle: Double = 0.0
    static var faceRollAngle: Double = 0.0
    static var pupilDistance: Double = 0.0
    static var verticesCount: Int = 0
    static var faceAnchor: ARFaceAnchor?
    static var depthWidth: Int = 640
    static var depthHeight: Int = 480
    
    var vertices: [SCNVector3] = []
    var colors: [UIColor] = []
    
    static func reset() {
        // Function to reset all variables
        pointCloudGeometries.removeAll()
    }
    
    // Function to apply a matrix transformation to a SCNVector3
    static func applyMatrixToVector3(_ vector: SCNVector3, with matrix: SCNMatrix4) -> SCNVector3 {
        let glkVector = GLKVector3Make(vector.x, vector.y, vector.z)
        let glkMatrix = SCNMatrix4ToGLKMatrix4(matrix)
        let transformed = GLKMatrix4MultiplyVector3(glkMatrix, glkVector)
        return SCNVector3(transformed.x, transformed.y, transformed.z)
    }

    // Function to calculate the rotation matrix
    static func rotationMatrix(from source: SCNVector3, to destination: SCNVector3) -> SCNMatrix4 {
        let sourceNormalized = source.normalized()
        let destinationNormalized = destination.normalized()
        let crossProduct = sourceNormalized.cross(destinationNormalized)
        let dotProduct = sourceNormalized.dot(destinationNormalized)
        let s = crossProduct.length()
        let c = dotProduct
        
        // Rodrigues' rotation formula components
        let kx = crossProduct.x
        let ky = crossProduct.y
        let kz = crossProduct.z
        
        return SCNMatrix4(
            m11: c + kx * kx * (1 - c),    m12: kx * ky * (1 - c) - kz * s, m13: kx * kz * (1 - c) + ky * s, m14: 0.0,
            m21: ky * kx * (1 - c) + kz * s, m22: c + ky * ky * (1 - c),    m23: ky * kz * (1 - c) - kx * s, m24: 0.0,
            m31: kz * kx * (1 - c) - ky * s, m32: kz * ky * (1 - c) + kx * s, m33: c + kz * kz * (1 - c),    m34: 0.0,
            m41: 0.0,                    m42: 0.0,                    m43: 0.0,                    m44: 1.0
        )
    }
    
    static func alignPointClouds() {
        guard !pointCloudGeometries.isEmpty,
              !pointCloudDataArray.isEmpty,
              pointCloudGeometries.count == pointCloudDataArray.count else {
            print("Data arrays are not properly initialized or don't match in count.")
            return
        }

        // Using the first point cloud as the reference model
        let referenceMetadata = pointCloudDataArray[0]

        for i in 1..<pointCloudGeometries.count {
            let currentMetadata = pointCloudDataArray[i]
            let geometry = pointCloudGeometries[i]

            // Calculate translation and rotation
            let translationVector = SCNVector3(
                x: referenceMetadata.leftEyePosition.x - currentMetadata.leftEyePosition.x,
                y: referenceMetadata.leftEyePosition.y - currentMetadata.leftEyePosition.y,
                z: referenceMetadata.leftEyePosition.z - currentMetadata.leftEyePosition.z
            )
            let rotationMatrix = rotationMatrix(from: currentMetadata.noseTipPosition, to: referenceMetadata.noseTipPosition)

            // Apply translation and rotation
            if let vertexSource = geometry.sources.first(where: { $0.semantic == .vertex }),
               let colorSource = geometry.sources.first(where: { $0.semantic == .color }) {
                var vertices = vertexSource.data.toArray(type: SCNVector3.self, count: vertexSource.vectorCount)
                for j in 0..<vertices.count {
                    vertices[j] = applyMatrixToVector3(vertices[j], with: rotationMatrix)
                    vertices[j].x += translationVector.x
                    vertices[j].y += translationVector.y
                    vertices[j].z += translationVector.z
                }
                
                // Update the geometry with transformed vertices
                let newVertexSource = SCNGeometrySource(vertices: vertices)
                let newGeometry = SCNGeometry(sources: [newVertexSource, colorSource], elements: geometry.elements)
                pointCloudGeometries[i] = newGeometry
            }
        }
    }
    
    // Function to calculate the center of a set of vertices
    static func calculateCenter(of vertices: [SCNVector3]) -> SCNVector3 {
        var sum = SCNVector3(0, 0, 0)
        guard !vertices.isEmpty else { return sum }
        
        for vertex in vertices {
            sum.x += vertex.x
            sum.y += vertex.y
            sum.z += vertex.z
        }
        
        let count = Float(vertices.count)
        return SCNVector3(sum.x / count, sum.y / count, sum.z / count)
    }
    
    static func rotateVertexAroundX(_ vertex: SCNVector3, around center: SCNVector3, angleDegrees: Float) -> SCNVector3 {
        // Convert angle from degrees to radians
        let angleRadians = angleDegrees * .pi / 180

        // Translate the vertex to the origin (relative to the center)
        var translatedVertex = vertex
        translatedVertex.y -= center.y
        translatedVertex.z -= center.z

        // Apply rotation around the X-axis
        let cosAngle = cos(angleRadians)
        let sinAngle = sin(angleRadians)

        let rotatedY = translatedVertex.y * cosAngle - translatedVertex.z * sinAngle
        let rotatedZ = translatedVertex.y * sinAngle + translatedVertex.z * cosAngle

        // Translate the vertex back (relative to the center)
        return SCNVector3(vertex.x, rotatedY + center.y, rotatedZ + center.z)
    }
    
    // Function to extract yaw angle from the transform matrix
    static func getYawAngle(from transform: SCNMatrix4) -> Float {
        return atan2(transform.m21, transform.m11)
    }
    
    static func createPointCloudGeometry(depthData: AVDepthData, imageSampler: CapturedImageSampler, width: Int, height: Int, calibrationData: AVCameraCalibrationData, transform: SCNMatrix4, percentile: Float = 35.0) {
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

        // Sort the depth values
        depthValues.sort()

        // Determine the depth threshold for the 30th percentile
        let index = Int(Float(depthValues.count) * percentile / 100.0)
        let depthThreshold = depthValues[max(0, min(index, depthValues.count - 1))]

        // Process points with depth values lower than the threshold
        for y in 0..<height {
            for x in 0..<width {
                let depthOffset = y * CVPixelBufferGetBytesPerRow(depthDataMap) + x * MemoryLayout<UInt16>.size
                let depthPointer = CVPixelBufferGetBaseAddress(depthDataMap)!.advanced(by: depthOffset).assumingMemoryBound(to: UInt16.self)
                let depthValue = Float(depthPointer.pointee)

                if depthValue > depthThreshold {
                    continue // Skip this point
                }

                let scaleFactor = Float(2.0) // Custom scale factor for depth exaggeration
                let xrw = (Float(x) - cameraIntrinsics.columns.2.x) * depthValue / cameraIntrinsics.columns.0.x
                let yrw = (Float(y) - cameraIntrinsics.columns.2.y) * depthValue / cameraIntrinsics.columns.1.y
                let vertex = SCNVector3(x: xrw, y: yrw, z: depthValue * scaleFactor)
                vertices.append(vertex)

                // Get color using CapturedImageSampler
                let normalizedX = CGFloat(x) / CGFloat(width)
                let normalizedY = CGFloat(y) / CGFloat(height)
                if let color = imageSampler.getColor(atX: normalizedX, y: normalizedY) {
                    colors.append(color)
                }
            }
        }
        
        if let index: Int? = ExternalData.pointCloudGeometries.count,
           index! < ExternalData.pointCloudDataArray.count {
               let metadata = ExternalData.pointCloudDataArray[index!]
               let yawAngle = Float(metadata.yaw)

               // Calculate the center
               let center = calculateCenter(of: vertices)

               // Rotate vertices around the Z-axis using the yaw angle
               for i in 0..<vertices.count {
                   vertices[i] = rotateVertexAroundX(vertices[i], around: center, angleDegrees: -yawAngle)
               }
           }
        
        // Create the geometry source for vertices
        let vertexSource = SCNGeometrySource(vertices: vertices)
        
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
        let fileManager = FileManager.default
        let tempDirectoryURL = fileManager.temporaryDirectory
        
        var fileURLs = [URL]()
        
        for (index, geometry) in pointCloudGeometries.enumerated() {
            let plyString = createPLYString(for: geometry)
            let plyFileName = "geometry_\(index).ply"
            let plyFileURL = tempDirectoryURL.appendingPathComponent(plyFileName)
            
            do {
                try plyString.write(to: plyFileURL, atomically: true, encoding: .ascii)
                fileURLs.append(plyFileURL)
            } catch {
                print("Failed to write PLY file: \(error)")
            }
        }
        
        // Create a ZIP file using SSZipArchive
        SSZipArchive.createZipFile(atPath: url.path, withFilesAtPaths: fileURLs.map { $0.path })
        
        // Cleanup temporary PLY files
        fileURLs.forEach { try? FileManager.default.removeItem(at: $0) }
    }
    
    private static func createPLYString(for geometry: SCNGeometry) -> String {
        var plyString = "ply\nformat ascii 1.0\n"

        guard let vertexSource = geometry.sources.first(where: { $0.semantic == .vertex }),
              let colorSource = geometry.sources.first(where: { $0.semantic == .color }) else {
            print("Unable to access vertex or color source from geometry")
            return ""
        }
        
        let vertexCount = vertexSource.vectorCount
        let vertices = vertexSource.data.toArray(type: SCNVector3.self, count: vertexCount)
        let colors = colorSource.data.toArray(type: SCNVector4.self, count: vertexCount) // Assuming SCNVector4 for colors

        plyString += "element vertex \(vertexCount)\n"
        plyString += "property float x\nproperty float y\nproperty float z\n"
        plyString += "property uchar red\nproperty uchar green\nproperty uchar blue\nproperty uchar alpha\n"
        plyString += "end_header\n"

        for i in 0..<vertexCount {
            let vertex = vertices[i]
            let color = colors[i]
            let colorComponents = [color.x, color.y, color.z, color.w].map { UInt8($0 * 255) }
            plyString += "\(vertex.x) \(vertex.y) \(vertex.z) \(colorComponents[0]) \(colorComponents[1]) \(colorComponents[2]) \(colorComponents[3])\n"
        }
        
        return plyString
    }
}
