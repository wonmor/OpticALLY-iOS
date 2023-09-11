import SwiftUI
import ARKit

/// A `View` representing the interface for AR-based eye tracking.
///
/// When this view appears on screen, the AR session starts, tracking the user's eyes. When the view disappears, the AR session pauses.
///
/// ```
/// EyesTrackingView() // This will instantiate and display the eye tracking interface
/// ```
///
/// - Note: This view utilizes `ARViewContainer` to incorporate `ARSCNView` into the SwiftUI view hierarchy.
///
/// - Properties:
///     - `viewModel`: The observed object responsible for managing and processing AR face tracking data.

struct EyesTrackingView: View {
    @ObservedObject var viewModel = EyesTrackingViewModel()

    var body: some View {
        ZStack {
            ARViewContainer(viewModel: viewModel)
                // Design elements go here, like cornerRadius, etc.
            VStack {
                // Other SwiftUI elements based on your design can be placed here
            }
        }
        .onAppear {
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.pauseSession()
        }
    }
}

/// A SwiftUI-compatible representation of `ARSCNView`.
///
/// This container allows you to use ARSCNView, a UIKit-based component, inside a SwiftUI view hierarchy.
///
/// ```
/// ARViewContainer(viewModel: someViewModel) // Represents the AR scene view within SwiftUI
/// ```
///
/// - Note: This container links the ARSCNView's delegate to the provided `EyesTrackingViewModel`.
///
/// - Properties:
///     - `viewModel`: The observed object responsible for managing and processing AR face tracking data.

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: EyesTrackingViewModel

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView()
        sceneView.delegate = viewModel
        sceneView.session.delegate = viewModel
        // Other ARSCNView configuration goes here
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // This method will get called whenever SwiftUI updates this view.
    }
}

struct EyesTrackingView_Previews: PreviewProvider {
    static var previews: some View {
        EyesTrackingView()
    }
}
