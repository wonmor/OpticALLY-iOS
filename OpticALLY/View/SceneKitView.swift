//
//  SceneKitView.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO
import ARKit
import Accelerate

let drawSphere = false // For visualizing landmark points

struct SceneKitView: UIViewRepresentable {
    // Binding variables to interact with your SwiftUI view
    var nodes: [SCNNode]
    
    @Binding var resetTrigger: Bool

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        let scene = SCNScene()
        scnView.scene = scene

        // Add primary nodes to the scene
        for node in nodes {
            if !drawSphere {
                scene.rootNode.addChildNode(node)
            }
        }

        if drawSphere {
            // Add all nodes from landmarkMultiNodes to the scene
            for landmarkNodes in ExternalData.landmarkMultiNodes {
                for landmarkNode in landmarkNodes {
                    scene.rootNode.addChildNode(landmarkNode)
                }
            }
        }

        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true
        scnView.backgroundColor = UIColor.white

        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        if resetTrigger {
            scnView.scene = SCNScene() // Reset the scene
            // Reconfigure the scene if neededIHL
            resetTrigger = false // Reset the trigger
        }

        // Assume sourcePoints and targetPoints are already defined and available
//        let sourcePoints: [[Double]] = nodes.map { [Double($0.position.x), Double($0.position.y), Double($0.position.z)] }
//        
//        // ADD 3D LANDMARK POINTS BELOW (TEMP: USING FIRST INDEX ONLY)
//        let targetPoints: [[Double]] = ExternalData.landmarkMultiNodes.map { [Double($0[0].position.x), Double($0[0].position.y), Double($0[0].position.z)] }
//        
//        let matrixA = nodes.map { [$0.position.x, $0.position.y, $0.position.z] }.transposed()
//        let matrixB = ExternalData.landmarkMultiNodes.map { [$0[0].position.x, $0[0].position.y, $0[0].position.z] }.transposed()
//
//        // Compute the rigid transformation
//        let (rotationMatrix, translationVector) = OpticALLYApp.rigidTransform3D(A: sourcePoints, B: targetPoints)
//
//        // Apply the transformation to each node
//        for (index, node) in nodes.enumerated() {
//            // Convert rotation matrix and translation vector to SceneKit types
//            let scnMatrix = rotationMatrixToSCNMatrix4(rotationMatrix)
//            let scnTranslation = SCNVector3(translationVector[0], translationVector[1], translationVector[2])
//
//            // Apply rotation and translation to the node
//            node.transform = scnMatrix
//            node.position = scnTranslation
//        }
    }

    // Helper function to convert a rotation matrix to SCNMatrix4
    private func rotationMatrixToSCNMatrix4(_ rotationMatrix: [[Double]]) -> SCNMatrix4 {
        // Ensure the matrix is 3x3
        guard rotationMatrix.count == 3 && rotationMatrix.allSatisfy({ $0.count == 3 }) else {
            fatalError("Rotation matrix must be 3x3.")
        }

        return SCNMatrix4(
            m11: Float(rotationMatrix[0][0]), m12: Float(rotationMatrix[0][1]), m13: Float(rotationMatrix[0][2]), m14: 0,
            m21: Float(rotationMatrix[1][0]), m22: Float(rotationMatrix[1][1]), m23: Float(rotationMatrix[1][2]), m24: 0,
            m31: Float(rotationMatrix[2][0]), m32: Float(rotationMatrix[2][1]), m33: Float(rotationMatrix[2][2]), m34: 0,
            m41: 0, m42: 0, m43: 0, m44: 1
        )
    }
}

struct SceneKitUSDZView: UIViewRepresentable {
    var usdzFileName: String
    
    @ObservedObject var viewModel: FaceTrackingViewModel
    
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.autoenablesDefaultLighting = true
        sceneView.backgroundColor = .clear
        
        if let faceAnchor = ExternalData.faceAnchor {
            let transform = SCNMatrix4(faceAnchor.transform)
            sceneView.scene?.rootNode.childNodes.first?.transform = transform
        }
        
        if let scene = SCNScene(named: usdzFileName) {
            // Enumerate through all nodes in the scene
            scene.rootNode.enumerateChildNodes { (node, _) in
                node.geometry?.materials.forEach { material in
                    // Set the diffuse color of each material to white
                    material.diffuse.contents = UIColor.white
                }
            }
            
            sceneView.scene = scene
        }
        
        return sceneView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let faceAnchor = viewModel.faceAnchor else { return }
        let faceTransform = SCNMatrix4(faceAnchor.transform)
        uiView.scene?.rootNode.childNodes.first?.transform = faceTransform
    }
}


struct SceneKitMDLView: UIViewRepresentable {
    var mdlAsset: MDLAsset
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        
        // Configure the scene
        let scene = SCNScene()
        scnView.scene = scene
        
        if let object = mdlAsset.object(at: 0) as? MDLMesh, let geometry: SCNGeometry? = SCNGeometry(mdlMesh: object) {
            // Modify each material to be double-sided
            geometry!.materials.forEach { material in
                material.isDoubleSided = true
            }
            
            ExternalData.verticesCount = object.vertexCount
            
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(x: 0, y: 0, z: 0)
            node.eulerAngles.z = .pi / -2
            
            scene.rootNode.addChildNode(node)
        }
        
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true
        scnView.backgroundColor = UIColor.black
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
