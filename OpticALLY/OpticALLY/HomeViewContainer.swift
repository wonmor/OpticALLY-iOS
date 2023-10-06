import SwiftUI

struct HomeViewContainer: UIViewControllerRepresentable {
    typealias UIViewControllerType = HomeViewController
    
    func makeUIViewController(context: Context) -> HomeViewController {
        return HomeViewController()
    }
    
    func updateUIViewController(_ uiViewController: HomeViewController, context: Context) {
        // You can add any additional logic or update code here if needed
    }
}
