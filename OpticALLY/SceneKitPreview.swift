//
//  SceneKitPreview.swift
//  OpticALLY
//
//  Created by John Seong on 2/4/24.
//

import SwiftUI
import SceneKit

struct SceneKitPreview: UIViewRepresentable {
    var url: URL

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        let scene = SCNScene()

        if let object = MDLAsset(url: url).object(at: 0) as? MDLMesh,
           let geometry: SCNGeometry? = SCNGeometry(mdlMesh: object) {
            geometry!.materials.forEach { material in
                material.isDoubleSided = true
            }
            
            let node = SCNNode(geometry: geometry)
            
            // Create a rotation action
            let rotation = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 10) // Adjust duration for speed
            let repeatRotation = SCNAction.repeatForever(rotation)
            
            // Run the action on the node
            node.runAction(repeatRotation)
            
            scene.rootNode.addChildNode(node)
        }

        scnView.scene = scene
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true
        scnView.backgroundColor = UIColor.black

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
