import SwiftUI

struct ScanViewControllerWrapper: UIViewControllerRepresentable {
    typealias UIViewControllerType = ScanViewController
    
    func makeUIViewController(context: Context) -> ScanViewController {
        return ScanViewController()
    }
    
    func updateUIViewController(_ uiViewController: ScanViewController, context: Context) {
        // You can update the view controller here if needed
    }
}
