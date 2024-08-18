import SwiftUI
import ARKit

struct FaceIDScanView: View {
    @ObservedObject var cameraViewController: CameraViewController // Ensure this is an ObservableObject

    var body: some View {
        ZStack {
            // Always display the ARViewContainer for the live AR feed
            ARViewContainer(arSessionDelegate: cameraViewController)
                .clipShape(Circle())
                .frame(width: 200, height: 200)
        }
        .onAppear {
            // Initialize ARSCNView and set its session delegate
            cameraViewController.setupARView()
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var arSessionDelegate: CameraViewController

    func makeUIView(context: Context) -> ARSCNView {
        // Ensure ARSCNView is initialized and set its session delegate
        arSessionDelegate.setupARView()
        return arSessionDelegate.arSCNView!
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) { }
}

// Extend CameraViewController to include a setup method for ARSCNView
extension CameraViewController {
    func setupARView() {
        if arSCNView == nil {
            arSCNView = ARSCNView()
            arSCNView?.session.delegate = self
        }
    }
}
