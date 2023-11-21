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

            node.eulerAngles.z = .pi / -2

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
    @EnvironmentObject var globalState: GlobalState

    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    ExternalData.reset()
                    globalState.currentView = .scanning
                }) {
                    Image(systemName: "arrow.left") // You can customize this with your own back button image
                        .foregroundStyle(.white)
                        .font(.title)
                        .padding()
                }
                
                Text("Preview")
                    .font(.system(.title, design: .monospaced)) // Using monospaced font
                Spacer()
            }
            .padding(.top)

            SceneKitView(geometry: ExternalData.pointCloudGeometry)
                .ignoresSafeArea(edges: .bottom)

            Spacer()

            // Dummy facial feature description
            Text("Facial Feature Analysis\n[Data not available]")
                .font(.title3)
                .multilineTextAlignment(.center)
                .monospaced()
                .padding()
        }
    }
}


struct PostScanView_Previews: PreviewProvider {
    static var previews: some View {
        PostScanView()
            .preferredColorScheme(.dark)
    }
}
