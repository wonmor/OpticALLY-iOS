import SwiftUI
import ARKit

struct FaceIDScanView: View {
    @ObservedObject var cameraViewController: CameraViewController // Ensure this is an ObservableObject

    var body: some View {
        ZStack {
            // Always display the ARViewContainer for the live AR feed
//            ARViewContainer(arSessionDelegate: cameraViewController)
//                .clipShape(Circle())
//                .frame(width: 200, height: 200)
        }
        .onAppear {
            
        }
    }
}
