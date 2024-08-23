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
import simd

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

struct SceneKitSingleView: UIViewRepresentable {
    var node: SCNNode

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor.black // Set the background color to black
        
        let scene = SCNScene()
        scnView.scene = scene
        scnView.scene?.rootNode.addChildNode(node)
        
        // Rotate the entire scene 90 degrees clockwise around the Y-axis
        scnView.scene?.rootNode.eulerAngles.y = -Float.pi / 2

        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true
        
        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        // Reapply the rotation to ensure it persists through updates
        scnView.scene?.rootNode.eulerAngles.y = -Float.pi / 2
    }
}


struct SceneKitUSDZView: UIViewRepresentable {
    var usdzFileName: String
    
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
//        guard let faceAnchor = cameraViewController.faceAnchor else { return }
//        let faceTransform = SCNMatrix4(faceAnchor.transform)
//        uiView.scene?.rootNode.childNodes.first?.transform = faceTransform
    }
}

struct SceneKitTEMPView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = UIColor.black
        scnView.scene = SCNScene()
        
        // Locate the 'output_from_server.obj' file within the app bundle
        if let objUrl = Bundle.main.url(forResource: "output_from_server", withExtension: "obj") {
            let mdlAsset = MDLAsset(url: objUrl)
            
            if let object = mdlAsset.object(at: 0) as? MDLMesh, let geometry: SCNGeometry? = SCNGeometry(mdlMesh: object) {
                // Modify each material to be double-sided and other configurations
                geometry!.materials.forEach { material in
                    material.lightingModel = .constant // Example configuration
                    material.isDoubleSided = true
                }
                
                // Customize the geometry's material properties as needed
                
                let node = SCNNode(geometry: geometry)
                node.position = SCNVector3(x: 0, y: 0, z: 0)
                node.eulerAngles.z = .pi / 2
                node.eulerAngles.y = .pi
                
                // Add the node to the scene
                scnView.scene?.rootNode.addChildNode(node)
            }
        } else {
            print("Failed to locate 'output_from_server.obj' in the app bundle.")
        }
        
        scnView.allowsCameraControl = true
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update the view if needed
    }
}

struct SceneKitMDLView: UIViewRepresentable {
    @Binding var snapshot: UIImage?
    
    var url: URL?
    var nodeFirst: SCNNode?
    var node: SCNNode? // Optional SCNNode to display
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        
        // Configure the scene
        let scene = SCNScene()
        scnView.scene = scene
        
        // Load the 3D model from the URL if available
        if let url = url, let object = MDLAsset(url: url).object(at: 0) as? MDLMesh, let geometry: SCNGeometry? = SCNGeometry(mdlMesh: object) {
            // Modify each material to be double-sided
            geometry!.materials.forEach { material in
                material.lightingModel = .constant // Removes shading and shadows
                material.isDoubleSided = true
            }
            
            if let material = geometry!.firstMaterial, let texture = material.diffuse.contents as? MDLTexture {
                // Ensure the texture is treated in sRGB color space
                material.diffuse.contents = texture
                material.diffuse.mappingChannel = 0
                material.diffuse.contentsTransform = SCNMatrix4MakeScale(1, 1, 1)
                material.diffuse.intensity = 1.0
                material.diffuse.minificationFilter = .linear
                material.diffuse.magnificationFilter = .linear
                material.diffuse.mipFilter = .linear
                material.diffuse.wrapS = .repeat
                material.diffuse.wrapT = .repeat
                material.diffuse.textureComponents = .all
                material.lightingModel = .phong // or another lighting model as needed
            }
            
            ExternalData.verticesCount = object.vertexCount
            
            let objectNode = SCNNode(geometry: geometry)
            objectNode.position = SCNVector3(x: 0, y: 0, z: 0)
            objectNode.eulerAngles.z = .pi / 2
            objectNode.eulerAngles.y = .pi
            
            scene.rootNode.addChildNode(objectNode)
        }
        
        // If a centroids node is provided, add it to the scene and apply transformations
        if let nodeFirst = nodeFirst {
            applyTransformations(nodeFirst: nodeFirst, node: node!)
            scene.rootNode.addChildNode(nodeFirst)
        }
        
        if let node = node {
            scene.rootNode.addChildNode(node)
        }
        
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true
        scnView.backgroundColor = UIColor.black
        
        return scnView
    }
    
    func updateUIView(_ scnView: SCNView, context: Context) {
        // Ensure that the node remains updated and transformations are reapplied
        if let nodeFirst = nodeFirst {
            applyTransformations(nodeFirst: nodeFirst, node: node!)
            if scnView.scene?.rootNode.childNodes.contains(nodeFirst) == false {
                scnView.scene?.rootNode.addChildNode(nodeFirst)
            }
        }
        
        if let node = node, scnView.scene?.rootNode.childNodes.contains(node) == false {
            scnView.scene?.rootNode.addChildNode(node)
        }
    }
    
    private func applyTransformations(nodeFirst: SCNNode, node: SCNNode) {
        // Extract positions from nodeFirst and node for matrixA and matrixB
        // Assuming both nodes have the same number of identifiable points/child nodes
        
        // This example assumes that each node has a series of child nodes or identifiable key points
        let childNodesFirst = nodeFirst.childNodes // Get child nodes of nodeFirst
        let childNodesSecond = node.childNodes // Get child nodes of node
        
        guard childNodesFirst.count == childNodesSecond.count else {
            print("The nodes must have the same number of points for transformation.")
            return
        }
        
        var matrixA: [NSValue] = []
        var matrixB: [NSValue] = []
        
        for i in 0..<childNodesFirst.count {
            let pointA = childNodesFirst[i].position
            let pointB = childNodesSecond[i].position
            
            // Add positions to matrixA and matrixB as NSValue(SCNVector3)
            matrixA.append(NSValue(scnVector3: pointA))
            matrixB.append(NSValue(scnVector3: pointB))
        }

        var rotation = SCNMatrix4Identity
        var translation = SCNVector3Zero

        // Call the Objective-C method
        PointCloudProcessingBridge.rigidTransformSceneKit3D(withMatrixA: matrixA, matrixB: matrixB, rotation: &rotation, translation: &translation)

        // Apply the transformations to the nodes
        nodeFirst.transform = SCNMatrix4Mult(SCNMatrix4MakeTranslation(translation.x, translation.y, translation.z), rotation)
    }

}
