//
//  ExternalData.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import UIKit
import AVFoundation
import CoreVideo
import MobileCoreServices
import Accelerate
import SwiftUI
import Vision
import SceneKit
import ARKit
import Combine
import Firebase
import Foundation

struct ExternalData {
    static var renderingEnabled = true
    static var isSavingFileAsPLY = false
    static var exportPLYData: Data?
    static var pointCloudGeometry: SCNGeometry?
    
    static func reset() {
        // Function to reset all variables
    }
    
    // Function to convert depth and color data into a point cloud geometry
    static func createPointCloudGeometry(depthData: AVDepthData, colorData: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int, calibrationData: AVCameraCalibrationData, percentile: Float = 35.0) -> SCNGeometry {
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
                
                let scaleFactor = Float(1.5) // Custom value for depth exaggeration
                let xrw = (Float(x) - cameraIntrinsics.columns.2.x) * depthValue / cameraIntrinsics.columns.0.x
                let yrw = (Float(y) - cameraIntrinsics.columns.2.y) * depthValue / cameraIntrinsics.columns.1.y
                let vertex = SCNVector3(x: xrw, y: yrw, z: depthValue * scaleFactor)
                
                vertices.append(vertex)
                
                let colorOffset = y * bytesPerRow + x * 4 // Assuming BGRA format
                let bComponent = Double(colorData[colorOffset]) / 255.0
                let gComponent = Double(colorData[colorOffset + 1]) / 255.0
                let rComponent = Double(colorData[colorOffset + 2]) / 255.0
                let aComponent = Double(colorData[colorOffset + 3]) / 255.0
                
                let color = UIColor(red: CGFloat(rComponent), green: CGFloat(gComponent), blue: CGFloat(bComponent), alpha: CGFloat(aComponent))
                colors.append(color)
                
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
        pointCloudGeometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        
        // Set the lighting model to constant to ensure the points are fully lit
        pointCloudGeometry!.firstMaterial?.lightingModel = .constant
        
        // Set additional material properties as needed, for example, to make the points more visible
        pointCloudGeometry!.firstMaterial?.isDoubleSided = true
        
        print("Done constructing the 3D object!")
        LogManager.shared.log("Done constructing the 3D object!")
        
        return pointCloudGeometry!
    }
    
    static func exportGeometryAsPLY(to url: URL) {
        guard let geometry = pointCloudGeometry,
              let vertexSource = geometry.sources.first(where: { $0.semantic == .vertex }),
              let colorSource = geometry.sources.first(where: { $0.semantic == .color }) else {
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
    
    static func exportGeometryAsUSDZ(to url: URL) {
        guard let geometry = pointCloudGeometry else {
            print("Point cloud geometry is not available")
            return
        }
        
        let scene = SCNScene()
        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)
        
        do {
            try scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)
            print("USDZ file successfully saved to: \(url.path)")
        } catch {
            print("Failed to write USDZ file: \(error)")
        }
    }
}
