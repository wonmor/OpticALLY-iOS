//
//  PostScanView.swift
//  OpticALLY
//
//  Created by John Seong on 11/10/23.
//

import SwiftUI
import SceneKit

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
            scene.rootNode.addChildNode(node)
        }

        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update the view if needed
    }
}

struct PostScanView: View {
    var body: some View {
        VStack {
            Text("model.ply")
                .font(.system(.title, design: .monospaced)) // Using monospaced font
                .padding()
            
            SceneKitView(geometry: ExternalData.pointCloudGeometry)
                .ignoresSafeArea()
        }
    }
}

struct PostScanView_Previews: PreviewProvider {
    static var previews: some View {
        PostScanView()
    }
}
