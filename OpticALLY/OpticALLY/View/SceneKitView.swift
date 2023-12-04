//
//  SceneKitView.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import SwiftUI
import ARKit
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

struct SceneKitUSDZView: UIViewRepresentable {
    var usdzFileName: String
    private let faceTrackingConfiguration = ARFaceTrackingConfiguration()

    func makeUIView(context: Context) -> SCNView {
        let sceneView = ARSCNView()
        sceneView.delegate = context.coordinator

        // Set up AR face tracking
        sceneView.session.run(faceTrackingConfiguration, options: [.resetTracking, .removeExistingAnchors])

        if let scene = SCNScene(named: usdzFileName) {
            sceneView.scene = scene
        }

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update the view if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, ARSCNViewDelegate {
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let faceAnchor = anchor as? ARFaceAnchor else { return }
            DispatchQueue.main.async {
                // Apply the face anchor's transform to the node
                node.transform = SCNMatrix4(faceAnchor.transform)
            }
        }
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
