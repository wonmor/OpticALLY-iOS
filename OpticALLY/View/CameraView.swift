import SwiftUI
import UIKit

var cameraViewController: CameraViewController!

struct CameraView: UIViewControllerRepresentable {
    @EnvironmentObject var globalState: GlobalState
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        cameraViewController = sb.instantiateViewController(identifier: "CameraViewController") as? CameraViewController
        
        cameraViewController.viewModel = faceTrackingViewModel  // Pass the ViewModel to the UIViewController
        
        return cameraViewController
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // Update logic if needed
    }
}
