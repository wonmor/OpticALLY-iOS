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
import ModelIO

struct PointCloudMetadata {
    var yaw: Double
    var pitch: Double
    var roll: Double
    
    var leftEyePosition: CGPoint
    var rightEyePosition: CGPoint
    var chinPosition: CGPoint
    
    var leftEyePosition3D: SCNVector3
    var rightEyePosition3D: SCNVector3
    var chinPosition3D: SCNVector3
    
    var image: CVPixelBuffer
    var depth: AVDepthData
    
    var faceNode: SCNNode
    var faceAnchor: ARFaceAnchor
    var faceTexture: UIImage
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
    static var pointCloudNodes: [SCNNode] = []
    static var pointCloudDataArray: [PointCloudMetadata] = []
    static var verticesCount: Int = 0
    static var faceAnchor: ARFaceAnchor?
    static var depthWidth: Int = 640
    static var depthHeight: Int = 480
    
    static var scaleX: Float = 0.0
    static var scaleY: Float = 0.0
    static var scaleZ: Float = 0.0
    
    var vertices: [SCNVector3] = []
    var colors: [UIColor] = []
    
    static func reset() {
        // Function to reset all variables
        renderingEnabled = true
        isSavingFileAsPLY = false
        isMeshView = false
        exportPLYData = nil
        pointCloudGeometries.removeAll()
        pointCloudDataArray.removeAll()
        verticesCount = 0
    }
    
    static func convertDepthData(depthMap: CVPixelBuffer) -> [[Float16]] {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        var convertedDepthMap: [[Float16]] = Array(
            repeating: Array(repeating: 0, count: width),
            count: height
        )
        CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 2))
        let floatBuffer = unsafeBitCast(
            CVPixelBufferGetBaseAddress(depthMap),
            to: UnsafeMutablePointer<Float16>.self
        )
        for row in 0 ..< height {
            for col in 0 ..< width {
                convertedDepthMap[row][col] = floatBuffer[width * row + col]
            }
        }
        CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 2))
        return convertedDepthMap
    }
    
    static func convertLensDistortionLookupTable(lookupTable: Data) -> [Float] {
        let tableLength = lookupTable.count / MemoryLayout<Float>.size
        var floatArray: [Float] = Array(repeating: 0, count: tableLength)
        _ = floatArray.withUnsafeMutableBytes{lookupTable.copyBytes(to: $0)}
        return floatArray
    }
    
    static func wrapEstimateImageData(
        depthMap: CVPixelBuffer,
        calibration: AVCameraCalibrationData
    ) -> Data {
        let jsonDict: [String : Any] = [
            "calibration_data" : [
                "intrinsic_matrix" : (0 ..< 3).map{ x in
                    (0 ..< 3).map{ y in calibration.intrinsicMatrix[x][y]}
                },
                "pixel_size" : calibration.pixelSize,
                "intrinsic_matrix_reference_dimensions" : [
                    calibration.intrinsicMatrixReferenceDimensions.width,
                    calibration.intrinsicMatrixReferenceDimensions.height
                ],
                "lens_distortion_center" : [
                    calibration.lensDistortionCenter.x,
                    calibration.lensDistortionCenter.y
                ],
                "lens_distortion_lookup_table" : convertLensDistortionLookupTable(
                    lookupTable: calibration.lensDistortionLookupTable!
                ),
                "inverse_lens_distortion_lookup_table" : convertLensDistortionLookupTable(
                    lookupTable: calibration.inverseLensDistortionLookupTable!
                )
            ],
            "depth_data" : convertDepthData(depthMap: depthMap)
        ]
        let jsonStringData = try! JSONSerialization.data(
            withJSONObject: jsonDict,
            options: .prettyPrinted
        )
        return jsonStringData
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
    
    private static func applyTransformation(to geometry: inout SCNGeometry, translation: SCNVector3, rotation: SCNMatrix4) {
        // Assuming geometry has vertex data
        guard let vertexSource = geometry.sources.first(where: { $0.semantic == .vertex }) else {
            print("Geometry does not have vertex data")
            return
        }
        
        var vertices = vertexSource.data.toArray(type: SCNVector3.self, count: vertexSource.vectorCount)
        for index in 0..<vertices.count {
            vertices[index] = applyMatrixToVector3(vertices[index], with: rotation)
            vertices[index] += translation // Adding SCNVector3
        }
        
        // Replace old vertex data with transformed vertices
        let newVertexSource = SCNGeometrySource(vertices: vertices)
        let newGeometry = SCNGeometry(sources: [newVertexSource], elements: geometry.elements)
        geometry = newGeometry
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
    
    // Function to convert depth and color data into a point cloud geometry
    static func createAVPointCloudGeometry(depthData: AVDepthData, colorData: UnsafePointer<UInt8>, metadata: PointCloudMetadata, width: Int, height: Int, bytesPerRow: Int, scaleX: Float, scaleY: Float, scaleZ: Float, percentile: Float = 35.0) {
        var vertices: [SCNVector3] = []
        var colors: [UIColor] = []
        var depthValues: [Float] = []
        var depthValuesForLandmarks: [Float] = []
        
        let cameraIntrinsics = depthData.cameraCalibrationData!.intrinsicMatrix
        
        let convertedDepthData = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16)
        let depthDataMap = convertedDepthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthDataMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthDataMap, .readOnly) }
        
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
                
                let scaleFactor = Float(1.5) // Custom value for depth exaggeration
                let xrw = (Float(x) - cameraIntrinsics.columns.2.x) * depthValue / cameraIntrinsics.columns.0.x
                let yrw = (Float(y) - cameraIntrinsics.columns.2.y) * depthValue / cameraIntrinsics.columns.1.y
                let vertex = SCNVector3(x: xrw, y: yrw, z: depthValue * scaleFactor)
                
                // Check if within threshold range for left eye
                if Int(xrw) == Int(round(metadata.leftEyePosition.x)) && Int(yrw) == Int(round(metadata.leftEyePosition.y)) {
                    print("Near Left eye landmark point x: \(x), y: \(y), z: \(depthValue * scaleFactor)")
                }
                
                // Check if within threshold range for right eye
                if Int(xrw) == Int(round(metadata.rightEyePosition.x)) && Int(yrw) == Int(round(metadata.rightEyePosition.y)) {
                    print("Near Right eye landmark point x: \(x), y: \(y), z: \(depthValue * scaleFactor)")
                }
                
                vertices.append(vertex)
                
                let colorOffset = y * bytesPerRow + x * 4 // Assuming BGRA format
                let bComponent = Double(colorData[colorOffset]) / 255.0
                let gComponent = Double(colorData[colorOffset + 1]) / 255.0
                let rComponent = Double(colorData[colorOffset + 2]) / 255.0
                let aComponent = Double(colorData[colorOffset + 3]) / 255.0
                
                let color = UIColor(red: CGFloat(rComponent), green: CGFloat(gComponent), blue: CGFloat(bComponent), alpha: CGFloat(aComponent))
                colors.append(color)
                
                LogManager.shared.log("Converting \(counter)th point: \([rComponent, gComponent, bComponent, aComponent])")
                
                counter += 1
            }
        }
        //
        //        if let index: Int? = ExternalData.pointCloudGeometries.count,
        //           index! < ExternalData.pointCloudDataArray.count {
        //            let metadata = ExternalData.pointCloudDataArray[index!]
        //            let faceTransform = adjustARKitMatrixForSceneKit(metadata.faceAnchor.transform) // simd_float4x4
        //            let scnTransform = SCNMatrix4(faceTransform) // Convert to SCNMatrix4
        //            let invertedTransform = SCNMatrix4Invert(scnTransform)
        //
        //            // Assuming you have a function to extract yaw angle from the face anchor transform
        //             let yawAngle = Float(metadata.yaw)
        //
        //            // Calculate the counter-rotation (rotate in the opposite direction of the yaw)
        //            let counterRotation = SCNMatrix4MakeRotation(yawAngle, 0, 1, 0)
        //
        //            // Apply the inverted transformation to each vertex
        //            for i in 0..<vertices.count {
        //                vertices[i] = applyMatrixToVector3(vertices[i], with: invertedTransform)
        //                vertices[i] = applyMatrixToVector3(vertices[i], with: counterRotation)
        //            }
        //        }
        
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
        let pointCloudGeometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        
        // Set the lighting model to constant to ensure the points are fully lit
        pointCloudGeometry.firstMaterial?.lightingModel = .constant
        
        // Set additional material properties as needed, for example, to make the points more visible
        pointCloudGeometry.firstMaterial?.isDoubleSided = true
        
        var pointCloudNode = SCNNode(geometry: pointCloudGeometry)
        
        // Create rotation matrices
        let rotationY = SCNMatrix4MakeRotation(Float(metadata.yaw), 0, 1, 0)
        let rotationX = SCNMatrix4MakeRotation(Float(metadata.pitch), 1, 0, 0)
        let rotationZ = SCNMatrix4MakeRotation(Float(metadata.roll), 0, 0, 1)
        
        // Combine rotations
        let rotation = SCNMatrix4Invert(SCNMatrix4Mult(SCNMatrix4Mult(rotationZ, rotationX), rotationY))
        
        pointCloudNode = updateNodePivot(node: pointCloudNode, usingDepthData: depthData, withMetadata: metadata)
        
        // Set the transform of the previewFaceNode
        // pointCloudNode.transform = rotation
        
        // Match the world position of the faceAnchor
        // let worldTransform = SCNMatrix4(metadata.faceAnchor.transform)// Convert simd_float4x4 to SCNMatrix4
        // pointCloudNode.worldPosition = SCNVector3(worldTransform.m41, worldTransform.m42, worldTransform.m43)
        
        pointCloudGeometries.append(pointCloudGeometry)
        pointCloudNodes.append(pointCloudNode)
        
        // alignPointClouds(scaleX: scaleX, scaleY: scaleY, scaleZ: scaleZ)
        
        print("Done constructing the 3D object!")
        LogManager.shared.log("Done constructing the 3D object!")
    }
    
    static func updateNodePivot(node: SCNNode, usingDepthData depthData: AVDepthData, withMetadata metadata: PointCloudMetadata) -> SCNNode {
        // Convert yaw, pitch, and roll to radians
        let yawRad = Float(metadata.yaw) * (Float.pi / 180)
        let pitchRad = Float(metadata.pitch) * (Float.pi / 180)
        let rollRad = Float(metadata.roll) * (Float.pi / 180)
        
        // Create rotation matrices
        let rotationY = SCNMatrix4MakeRotation(yawRad, 0, 1, 0)
        let rotationX = SCNMatrix4MakeRotation(pitchRad, 1, 0, 0)
        let rotationZ = SCNMatrix4MakeRotation(rollRad, 0, 0, 1)
        
        // Combine rotations into a single matrix
        let combinedRotation = SCNMatrix4Mult(SCNMatrix4Mult(rotationZ, rotationX), rotationY)
        
        // Assuming the pivot should be at the center of the geometry
        if let geometry = node.geometry {
            let (minBound, maxBound) = geometry.boundingBox
            let center = SCNVector3Make(
                minBound.x + (maxBound.x - minBound.x) / 2,
                minBound.y + (maxBound.y - minBound.y) / 2,
                minBound.z + (maxBound.z - minBound.z) / 2
            )
            
            // Set the pivot to be the center of the geometry after applying the combined rotation
            node.pivot = SCNMatrix4Mult(SCNMatrix4MakeTranslation(center.x, center.y, center.z), combinedRotation)
        }
        
        return node
    }
    
    static func calculatePivotForNodes(nodes: [SCNNode], withMetadata metadataArray: [PointCloudMetadata]) -> SCNVector3 {
        guard !nodes.isEmpty && nodes.count == metadataArray.count else {
            return SCNVector3(0, 0, 0) // Return a default pivot if arrays are empty or mismatched
        }
        
        // Calculate the average position of all nodes
        var averagePosition = SCNVector3(0, 0, 0)
        for node in nodes {
            averagePosition.x += node.position.x
            averagePosition.y += node.position.y
            averagePosition.z += node.position.z
        }
        averagePosition.x /= Float(nodes.count)
        averagePosition.y /= Float(nodes.count)
        averagePosition.z /= Float(nodes.count)
        
        // Calculate the average orientation (yaw, pitch, roll) of all nodes
        var averageYaw: Float = 0, averagePitch: Float = 0, averageRoll: Float = 0
        for metadata in metadataArray {
            averageYaw += Float(metadata.yaw)
            averagePitch += Float(metadata.pitch)
            averageRoll += Float(metadata.roll)
        }
        averageYaw /= Float(metadataArray.count)
        averagePitch /= Float(metadataArray.count)
        averageRoll /= Float(metadataArray.count)
        
        // Convert average yaw, pitch, and roll to radians
        averageYaw *= (Float.pi / 180)
        averagePitch *= (Float.pi / 180)
        averageRoll *= (Float.pi / 180)
        
        // Apply an arbitrary formula to adjust the pivot based on the average orientation
        // This is a simple example and might need to be adjusted for your specific requirements
        let pivotAdjustment = SCNVector3(averageYaw * 5, averagePitch * 5, averageRoll * 5)
        
        // Calculate the final pivot point
        let finalPivot = SCNVector3(
            averagePosition.x + pivotAdjustment.x,
            averagePosition.y + pivotAdjustment.y,
            averagePosition.z + pivotAdjustment.z
        )
        
        return finalPivot
    }
    
    static func adjustARKitMatrixForSceneKit(_ matrix: simd_float4x4) -> simd_float4x4 {
        var adjustedMatrix = matrix
        
        // Invert the Z-axis
        adjustedMatrix.columns.2.z *= -1
        adjustedMatrix.columns.3.z *= -1
        
        return adjustedMatrix
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
        
        // alignPointClouds(scaleX: scaleX, scaleY: scaleY, scaleZ: scaleZ)
        
        print("Done constructing the 3D object!")
        LogManager.shared.log("Done constructing the 3D object!")
    }
    
    static func exportAV_GeometryAsPLY(to url: URL) {
        guard let geometry = pointCloudGeometries.first,
              let vertexSource = geometry.sources.first(where: { $0.semantic == .vertex }),
              let colorSource = geometry.sources.first(where: { $0.semantic == .color }) else {
            print("Unable to access vertex or color source from geometry")
            return
        }
        
        var plyString = "ply\nformat ascii 1.0\n"
        
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
        
        do {
            try plyString.write(to: url, atomically: true, encoding: .ascii)
            print("PLY file was successfully saved to: \(url.path)")
        } catch {
            print("Failed to write PLY file: \(error)")
        }
    }
    
    static func exportGeometryAsPLY(to url: URL) {
        let fileManager = FileManager.default
        let tempDirectoryURL = fileManager.temporaryDirectory
        var fileURLs = [URL]()
        
        // Export PLY files
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
        
        // Export OBJ files for faceNodes using MDLAsset
        for (index, metadata) in pointCloudDataArray.enumerated() {
            let objFileName = "faceNode_\(index).obj"
            let objFileURL = tempDirectoryURL.appendingPathComponent(objFileName)
            
            if let device = MTLCreateSystemDefaultDevice(),
               let mesh: MDLMesh? = MDLMesh(scnGeometry: metadata.faceNode.geometry!, bufferAllocator: MTKMeshBufferAllocator(device: device)) {
                let asset = MDLAsset()
                asset.add(mesh!)
                do {
                    try asset.export(to: objFileURL)
                    fileURLs.append(objFileURL)
                    
                    // Append the MTL reference to the OBJ file
                    let mtlFileName = "material_\(index).mtl"
                    let mtlReference = "mtllib \(mtlFileName)\n"
                    if var objContent = try? String(contentsOf: objFileURL) {
                        objContent = mtlReference + objContent
                        try objContent.write(to: objFileURL, atomically: true, encoding: .utf8)
                    }
                } catch {
                    print("Failed to write OBJ file: \(error)")
                }
            }
            
            // Export the texture image
            let textureFileName = "texture_\(index).png"
            let textureFileURL = tempDirectoryURL.appendingPathComponent(textureFileName)
            if let textureData = metadata.faceTexture.pngData() {
                do {
                    try textureData.write(to: textureFileURL)
                    fileURLs.append(textureFileURL)
                } catch {
                    print("Failed to write texture file: \(error)")
                }
            }
            
            // Create and export the MTL file
            let mtlFileName = "material_\(index).mtl"
            let mtlFileURL = tempDirectoryURL.appendingPathComponent(mtlFileName)
            let mtlContent = "newmtl Material\nmap_Kd \(textureFileName)\n"
            do {
                try mtlContent.write(to: mtlFileURL, atomically: true, encoding: .utf8)
                fileURLs.append(mtlFileURL)
            } catch {
                print("Failed to write MTL file: \(error)")
            }
        }
        
        // Create a ZIP file using SSZipArchive
        SSZipArchive.createZipFile(atPath: url.path, withFilesAtPaths: fileURLs.map { $0.path })
        
        // Cleanup temporary files
        fileURLs.forEach { try? fileManager.removeItem(at: $0) }
    }
    
    private static func createMTLString(textureFileName: String) -> String {
        var mtlString = "newmtl Material\n"
        mtlString += "map_Kd \(textureFileName)\n"
        return mtlString
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
