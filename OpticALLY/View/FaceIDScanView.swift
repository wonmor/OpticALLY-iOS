import SwiftUI
import ARKit

struct FaceIDScanView: View {
    @Binding var isScanComplete: Bool
    @ObservedObject var cameraViewController: CameraViewController // Ensure this is an ObservableObject
    
    @Binding var showFaceIdLoading: Bool
    @Binding var showFaceIdSuccessful: Bool

    var body: some View {
        ZStack {
            // Always display the ARViewContainer for the live AR feed
            ARViewContainer(arSessionDelegate: cameraViewController)
                .clipShape(Circle())
                .frame(width: 200, height: 200)
                // Conditionally apply blur if needed, or adjust as per requirements
                .blur(radius: showFaceIdLoading || showFaceIdSuccessful ? 20 : 0)

            // Conditionally display animations for loading or success
            if showFaceIdLoading {
                LottieView(animationFileName: "face-id-2", loopMode: .loop)
                    .frame(width: 60, height: 60)
                    .opacity(0.5)
                    .scaleEffect(0.5)
                    .padding(.top)
            } else if showFaceIdSuccessful {
                LottieView(animationFileName: "face-found-successfully", loopMode: .playOnce)
                    .frame(width: 60, height: 60)
                    .scaleEffect(0.5)
                    .opacity(0.5)
            }
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
