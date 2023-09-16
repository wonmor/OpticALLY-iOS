import SwiftUI
import AVFoundation

struct CameraView: UIViewControllerRepresentable {
    
    func makeUIViewController(context: Context) -> CameraViewController {
        return CameraViewController()
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // Update the controller if needed. Typically this function remains empty for this use case.
    }
}
