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
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()

        // Configure the scene
        let scene = SCNScene()
        scnView.scene = scene

        // Iterate through geometries and add each to the scene
        for (index, geometry) in ExternalData.pointCloudGeometries.enumerated() {
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(x: 0, y: 0, z: 0)
            node.eulerAngles.z = .pi / -2
            
            // scene.rootNode.addChildNode(node)

            // Check if there's corresponding face geometry data
            if index < ExternalData.pointCloudDataArray.count {
                let faceGeometryData = ExternalData.pointCloudDataArray[index].faceGeometry
                let faceNode = SCNNode(geometry: faceGeometryData)
                // Position and orient the face geometry
                faceNode.position = faceGeometryData.boundingSphere.center
                
                scene.rootNode.addChildNode(faceNode)
            }
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
