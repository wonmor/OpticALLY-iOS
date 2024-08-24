import SwiftUI
import UIKit

var cameraViewController: CameraViewController!

struct CameraView: UIViewControllerRepresentable {
    @EnvironmentObject var globalState: GlobalState
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        cameraViewController = sb.instantiateViewController(identifier: "CameraViewController") as? CameraViewController
        
        return cameraViewController
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // Update logic if needed
    }
    
    func dismantleUIViewController(_ uiViewController: CameraViewController, coordinator: ()) {
        // Handle any cleanup if necessary when the view is removed
        // This can be used to pause the session or clear any data
    }
}
