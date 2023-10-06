import SwiftUI
import RealityKit

struct HomeView : View {
    var body: some View {
        ZStack {
            // Fullscreen camera ARView
            HomeViewContainer().edgesIgnoringSafeArea(.all)
        }
    }
}
