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
                .edgesIgnoringSafeArea(.all) // Ensuring AR view covers entire screen

            VStack {
                Spacer()
                // Displaying eye distance and cosine angle
                Text("Pupillary Distance")
                    .bold()
                
                Text("\(viewModel.distanceText)")
                    .font(.title)
            }
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
        
        // Set ARSCNView settings
        sceneView.backgroundColor = UIColor.clear
        // sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
        
        // Ensure autoenablesDefaultLighting is set for basic lighting
        sceneView.autoenablesDefaultLighting = true
        
        guard ARFaceTrackingConfiguration.isSupported else { return sceneView }
        let configuration = ARFaceTrackingConfiguration()
        if #available(iOS 13.0, *) {
            configuration.maximumNumberOfTrackedFaces = ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces
        }
        configuration.isLightEstimationEnabled = true
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
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
