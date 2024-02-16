//
//  ParsePLY.swift
//  OpticALLY
//
//  Created by John Seong on 2/16/24.
//

import Foundation
import SceneKit

struct Vertex {
    var x: Float
    var y: Float
    var z: Float
    var r: Float // Red color component
    var g: Float // Green color component
    var b: Float // Blue color component
}

struct Face {
    var vertexIndices: [Int]
}

func createSceneKitModel(fromPLYFile filePath: String) -> SCNNode? {
    guard let (vertices, colors, normals) = parsePLYFile(atPath: filePath) else {
        print("Failed to parse PLY file.")
        return nil
    }

    let vertexSource = SCNGeometrySource(vertices: vertices)
    let normalSource = SCNGeometrySource(normals: normals)

    // Convert colors to a format suitable for SCNGeometrySource
    let colorData = Data(bytes: colors, count: colors.count * MemoryLayout<Float>.size * 3) // 3 components per color
    let colorSource = SCNGeometrySource(data: colorData,
                                        semantic: .color,
                                        vectorCount: colors.count,
                                        usesFloatComponents: true,
                                        componentsPerVector: 3,
                                        bytesPerComponent: MemoryLayout<Float>.size,
                                        dataOffset: 0,
                                        dataStride: MemoryLayout<Float>.size * 3)

    let indices: [Int32] = [0, 1, 2] // Define indices for your geometry. Adjust accordingly.
    let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
    let geometry = SCNGeometry(sources: [vertexSource, normalSource, colorSource], elements: [element])

    let node = SCNNode(geometry: geometry)
    return node
}

func parsePLYFile(atPath filePath: String) -> (vertices: [SCNVector3], colors: [Float], normals: [SCNVector3])? {
    do {
        let content = try String(contentsOfFile: filePath)
        let lines = content.split(separator: "\n")
        
        var isHeader = true
        var vertexCount = 0
        var vertices = [Vertex]()
        var colors = [Float]()
        
        for line in lines {
            if line.starts(with: "end_header") {
                isHeader = false
                continue
            }
            
            if isHeader {
                if line.starts(with: "element vertex") {
                    let parts = line.split(separator: " ")
                    if let count = Int(parts.last!) {
                        vertexCount = count
                    }
                }
                continue
            }
            
            if vertices.count < vertexCount {
                let parts = line.split(separator: " ").map { Float($0)! }
                let vertex = Vertex(x: parts[0], y: parts[1], z: parts[2], r: parts[3] / 255.0, g: parts[4] / 255.0, b: parts[5] / 255.0)
                vertices.append(vertex)
                colors.append(contentsOf: [vertex.r, vertex.g, vertex.b])
                continue
            }
        }
        
        let scnVertices = vertices.map { SCNVector3($0.x, $0.y, $0.z) }
        let normals = [SCNVector3]() // Calculate or load normals as needed
        
        return (scnVertices, colors, normals)
    } catch {
        print("Failed to read PLY file: \(error)")
        return nil
    }
}

