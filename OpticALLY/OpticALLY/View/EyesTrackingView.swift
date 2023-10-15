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
    
    @State private var buttonOpacity: Double = 0.0 // Add this state variable
    
    @State private var blurAmount: CGFloat = 20.0
    @State private var clickable: Bool = false
    
    @Binding var currentView: ViewState  // Add this binding
    
    var body: some View {
        ZStack {
            ARViewContainer(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
                .onChange(of: viewModel.shouldShowImage) { newValue in
                    if newValue {
                        print("It's good to move!")
                    } else {
                        print("It's not good to move!")
                    }
                }
            
            VStack {
                Text("Pupillary Distance")
                    .bold()
                
                Text(viewModel.distanceText.isEmpty ? "Measuring..." : viewModel.distanceText)
                    .font(.title)
                
                // Conditionally display the "Next" button when viewModel.distanceText is not empty
            }
            .padding(20)
            .foregroundStyle(.white)
            .background(
                Capsule()
                    .foregroundColor(Color.black.opacity(0.4))
                    .blur(radius: 5.0)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: 150)
            
            if !viewModel.distanceText.isEmpty {
                Button(action: {
                    // Action for when the "Next" button is pressed
                    if clickable {
                        currentView = .scanning
                    }
                }) {
                    HStack {
                        Text("3D Capture")
                            .bold()
                        
                        Image(systemName: "arrow.right")
                    }
                    .padding()
                    .foregroundColor(.white)
                    .background(
                        Capsule()
                            .foregroundStyle(.black)
                    )
                }
                .opacity(buttonOpacity)
                .blur(radius: blurAmount)  // Apply the blur effect
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: 250)
                .animation(.easeInOut(duration: 1.5), value: buttonOpacity)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5)) {
                        buttonOpacity = 1.0
                    }
                    
                    withAnimation(.easeInOut(duration: 2.5)) {
                        blurAmount = 0.0  // Gradually remove the blur effect
                    } // Gradually remove the blur effect
                }
            }
        }
        .onReceive(viewModel.$distanceText) { newText in
            if !newText.isEmpty {
                withAnimation(.easeInOut(duration: 1.5)) {
                    buttonOpacity = 1.0
                }
                
                withAnimation(.easeInOut(duration: 2.5)) {
                    blurAmount = 0.0  // Gradually remove the blur effect
                }
            }
        }
        .onAppear {
            randomX = CGFloat.random(in: 0..<UIScreen.main.bounds.width)
            randomY = CGFloat.random(in: 0..<UIScreen.main.bounds.height)
            
            // Delay of 2.5 seconds to make the button clickable
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                clickable = true
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

struct EyesTrackingViews_Previews: PreviewProvider {
    @State static var currentViewMock: ViewState = .tracking
    
    static var previews: some View {
        EyesTrackingView(currentView: $currentViewMock)
    }
}
