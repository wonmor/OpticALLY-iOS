import SwiftUI
import UIKit

struct CameraView: UIViewControllerRepresentable {
    typealias UIViewControllerType = CameraViewController

        func makeUIViewController(context: Context) -> CameraViewController {
            let sb = UIStoryboard(name: "Main", bundle: nil)
            let viewController = sb.instantiateViewController(identifier: "CameraViewController") as! CameraViewController
            return viewController
        }
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // No need for any updates in this case
    }
}
