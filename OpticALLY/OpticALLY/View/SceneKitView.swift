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

let drawSphere = true // For visualizing landmark points

struct SceneKitView: UIViewRepresentable {
    @Binding var selectedNodeIndex: Int?
    @Binding var position: SCNVector3
    @Binding var rotation: SCNVector3
    @Binding var resetTrigger: Bool
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        let scene = SCNScene()
        scnView.scene = scene

        // Get the last three nodes from ExternalData.pointCloudNodes
        let lastThreeNodes = ExternalData.pointCloudNodes.suffix(3)
        let lastThreeMetadatas = ExternalData.pointCloudDataArray.suffix(3)
        
        for (index, node) in lastThreeNodes.enumerated() {
            // Set the position and orientation of the node
            node.position = SCNVector3(x: 0, y: 0, z: 0)
            node.eulerAngles.z = .pi / -2
            
            // Add the node to the scene
            scene.rootNode.addChildNode(node)

            // Add corresponding face geometry data, if available
            let actualIndex = ExternalData.pointCloudNodes.count - 3 + index
            if actualIndex < ExternalData.pointCloudDataArray.count {
                let faceNode = ExternalData.pointCloudDataArray[actualIndex].faceNode
                // Add faceNode to the scene or perform additional setup
            }
            
            // Add spheres for left and right eye positions
            for eyePosition in [lastThreeMetadatas[index].leftEyePosition3D, lastThreeMetadatas[index].rightEyePosition3D] {
                print("Eye Position: \(eyePosition)")
                
                // DEBUG: BELOW LINE DOES NOT WORK WHILE ABOVE ADDCHILDNODE IS ACTIVE... RESOLVE IT!
               let sphereNode = SCNNode(geometry: SCNSphere(radius: 0.01)) // Adjust radius as needed
               sphereNode.geometry?.firstMaterial?.diffuse.contents = UIColor.red
               sphereNode.position = eyePosition
               scene.rootNode.addChildNode(sphereNode)
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
            // Reconfigure the scene if needed
            resetTrigger = false // Reset the trigger
        }

        // Update the selected node's position and rotation
        if let index = selectedNodeIndex,
           let node = scnView.scene?.rootNode.childNodes[index] {
            node.position = position
            node.eulerAngles = rotation
        }
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
