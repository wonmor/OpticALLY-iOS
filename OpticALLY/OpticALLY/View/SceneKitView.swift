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

struct SceneKitView: UIViewRepresentable {
    var geometry: SCNGeometry?
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        
        // Configure the scene
        let scene = SCNScene()
        scnView.scene = scene
        
        // Check if geometry is provided
        if let geometry = geometry {
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(x: 0, y: 0, z: 0)
            
            node.eulerAngles.z = .pi / -2
            
            scene.rootNode.addChildNode(node)
        }
        
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true
        scnView.backgroundColor = UIColor.white
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {}
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
        guard let faceAnchor = ExternalData.faceAnchor else { return }

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
