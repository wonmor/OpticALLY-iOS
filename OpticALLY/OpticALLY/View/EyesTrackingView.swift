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
    
    @State private var randomX: CGFloat = CGFloat.random(in: 0..<UIScreen.main.bounds.width)
    @State private var randomY: CGFloat = CGFloat.random(in: 0..<UIScreen.main.bounds.height)
    
    @Binding var currentView: ViewState  // Add this binding
    
    var body: some View {
        ZStack {
            ARViewContainer(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all) // Ensuring AR view covers entire screen
                .onChange(of: viewModel.shouldShowImage) { newValue in
                    // Your logic when isGoodToMove changes
                    if newValue {
                        print("It's good to move!")
                    } else {
                        print("It's not good to move!")
                    }
                }
            
//            if viewModel.shouldShowImage {
//               Image("BLINK") // Assume the name of the image is "BLINK"
//                   .resizable()
//                   .scaledToFit()
//                   .frame(width: 200, height: 200)
//                   .position(x: randomX, y: randomY)
//                   .onAppear {
//                       // This block will be called when the image appears.
//                       DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                           // After a delay of 2 seconds, shouldShowImage is set to false
//                           viewModel.shouldShowImage = false
//                       }
//                   }
//           }
            
            VStack {
                Text("Pupillary Distance")
                    .bold()
                
                Text(viewModel.distanceText.isEmpty ? "Measuring..." : viewModel.distanceText)
                    .font(.title)
                
                Text("Face Width")
                    .bold()
                    .padding(.top)
                
                Text(viewModel.faceWidthText.isEmpty ? "Measuring..." : viewModel.faceWidthText)
                    .font(.title)
            }
            .padding(20) // Add some padding to make it look nicer
            .foregroundStyle(.white)
            .background(
                Capsule() // Pill-shaped background
                    .foregroundColor(Color.black.opacity(0.4))
                    .blur(radius: 5.0) // Blur the background
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: 250) // Shift content slightly below the center
        }
        .onAppear {
            // Generate new random positions each time the view appears
            randomX = CGFloat.random(in: 0..<UIScreen.main.bounds.width)
            randomY = CGFloat.random(in: 0..<UIScreen.main.bounds.height)
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
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
        
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
