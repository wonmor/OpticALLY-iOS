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
