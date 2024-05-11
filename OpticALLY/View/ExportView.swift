import SwiftUI
import Lottie
import ARKit

enum ScanState {
    case ready, scanning, completed
}

enum ScanDirection {
    case left, front, right
}

struct CompassView: View {
    @ObservedObject var viewModel: CameraViewController
    
    @Binding var scanState: ScanState
    @Binding var scanDirection: ScanDirection
    
    @State private var previousYawAngle: Int = 0
    @State private var barColor = Color.white.opacity(0.2)
    
    // screenWidth represents the total width available for the compass view
    let screenWidth = UIScreen.main.bounds.width - 40 // assuming 20 points padding on each side

    private var compassIndicatorPosition: CGFloat {
        // Mapping yawAngle to screen width
        let position = ((-viewModel.faceYawAngle + 90) / 360) * screenWidth
        
        return position
    }
    
    private func getIndexForStick() -> Int {
        switch scanDirection {
        case .left:
            return 2
        case .front:
            return 3
        case .right:
            return 4
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(barColor)
                    .frame(height: 30)
 
                // Text displaying the degree
                HStack {
                    Text("\(Int(viewModel.faceYawAngle))º")
                        .font(.system(size: 16))
                        .monospaced()
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(5)
                        .padding(.leading, compassIndicatorPosition - 30)
                        .onChange(of: Int(viewModel.faceYawAngle)) { newFaceYawAngle in
                            guard scanState == .scanning else { return }
                            
                            switch scanDirection {
                            case .left where newFaceYawAngle > 20:
                                let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
                                impactGenerator.impactOccurred(intensity: 1.00)
                                
                                barColor = .green.opacity(0.5)
                                
                            case .front where abs(newFaceYawAngle) < 10:
                                let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
                                impactGenerator.impactOccurred(intensity: 1.00)
                                
                                barColor = .green.opacity(0.5)
                                
                            case .right where newFaceYawAngle < -20:
                                let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
                                impactGenerator.impactOccurred(intensity: 1.00)
                                
                                barColor = .green.opacity(0.5)
                                
                            default:
                                let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
                                impactGenerator.impactOccurred(intensity: 0.25)
                                previousYawAngle = newFaceYawAngle
                                
                                barColor = .white.opacity(0.2)
                                
                                break
                            }
                        }

                    Spacer()
                }
                
                // Multiple vertical lines for the compass indicator
               let numberOfLines = 10 // Number of lines you want
               let lineSpacing = geometry.size.width / CGFloat(numberOfLines + 1)

               ForEach(0..<numberOfLines, id: \.self) { index in
                   if getIndexForStick() == index {
                       Rectangle()
                           .fill(Color.green)
                           .frame(width: 2, height: 30)
                           .offset(x: lineSpacing * CGFloat(index + 1) - 1, y: 0)
                   } else {
                       Rectangle()
                           .fill(Color.black)
                           .frame(width: 2, height: 30)
                           .offset(x: lineSpacing * CGFloat(index + 1) - 1, y: 0)
                   }
               }

               // The active indicator line
               Rectangle()
                    .fill(Color.white.opacity(0.5)) // Use a distinct color to highlight the active indicator
                   .frame(width: 2, height: 30)
                   .offset(x: compassIndicatorPosition - 1, y: 0)
            }

        }
    }
}

struct ExportView: View {
    @EnvironmentObject var globalState: GlobalState
    
    @StateObject private var exportViewModel = ExportViewModel()
    
    @ObservedObject var logManager = LogManager.shared
    
    @State private var scanState: ScanState = .ready
    @State private var scanDirection: ScanDirection = .front
    @State private var showScanCompleteView: Bool = false
    
    @State private var showLog: Bool = false
    @State private var hideMoveOnButton: Bool = false
    
    @State private var lastHapticTime: Date? = nil
    @State private var lastFeedbackAngle: Double? = nil
    
    private let hapticInterval: TimeInterval = 0.1 // 100 milliseconds interval between haptic feedbacks
    
    private func captureFrame() {
        ExternalData.isSavingFileAsPLY = true
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Spacer()
                
                DistanceIndicator(cameraViewController: cameraViewController)
                
                if showLog {
                    if let lastLog = logManager.latestLog {
                        Text(lastLog.uppercased())
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                            .monospaced()
                            .onAppear {
                                hideMoveOnButton = true
                            }
                        
                        if lastLog.contains("Capturing") {
                            LottieView(animationFileName: "face-id-2", loopMode: .loop)
                                .frame(width: 60, height: 60)
                                .opacity(0.5)
                                .scaleEffect(0.5)
                                .padding(.vertical)
                                .colorInvert()
                        }
                        
                        
                        if lastLog.contains("Complete") {
                            VStack(spacing: 10) { // Adjust spacing as needed
                                LottieView(animationFileName: "cargo-loading", loopMode: .loop)
                                    .frame(width: 60, height: 60)
                                    .scaleEffect(0.1)
                                    .padding()
                                    .colorInvert()
                                
                                Text("PROCESSING SCANS")
                                    .bold()
                                    .monospaced()
                                    .foregroundColor(.white)
                            }
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30) // Adjust horizontal padding for wider background
                            .padding(.vertical, 15) // Adjust vertical padding for background height
                            .zIndex(1) // Ensure the spinner and text are above other content
                            .onAppear() {
                                // Only do this for the LAST iteration of the 3 scans... (3rd scan) -> Because UI will be hidden until then, it's fine for now when it comes to logic
                                exportViewModel.hasTurnedLeft = true
                                exportViewModel.hasTurnedRight = true
                                exportViewModel.hasTurnedCenter = true
                                
                                hideMoveOnButton = false
                                
                                // Important part!
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { // Assuming animation duration is 2 seconds
                                    viewResults()
                                }
                            }
                        }
                    }
                } else {
                    VStack {
                        if !scanInstruction.contains("Align") {
                            Text(scanInstruction)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .cornerRadius(12)
                        }
                        
                        Text(scanInstruction2)
                            .monospaced()
                            .font(.title)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .cornerRadius(12)
                    }
                }
                
                ZStack {
                    SignalStrengthView(scanState: $scanState, scanDirection: $scanDirection, cameraViewController: cameraViewController)
                        .frame(width: 300, height: 300)
                        .blur(radius: 5.0)
                    
                    // Segmented circle behind the FaceIDScanView
                    DirectionIndicatorView(scanDirection: $scanDirection, cameraViewController: cameraViewController)
                        .frame(width: 220, height: 220) // Adjust the size as needed
                    
                    // FaceIDScanView in the front
                    FaceIDScanView(cameraViewController: cameraViewController)
                        .frame(width: 200, height: 200)
                        .clipShape(Circle())
                        .padding()
                }
                .onChange(of: cameraViewController.faceYawAngle) { newValue in
                    handleFaceDirectionChange(yawAngle: newValue)
                }
                
                Spacer()
                
                if scanState != .scanning {
                    if let lastLog = logManager.latestLog {
                        if lastLog.lowercased().contains("complete") {
                            // Empty...
                        }
                        
                    } else {
                        if determineStatus().text.contains("OPTIMAL") {
                            Button(action: startScanning) {
                                Text("Start Scanning")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Capsule().fill(Color.gray.opacity(0.4)))
                            }
                            .padding(.horizontal)
                            
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white, lineWidth: 2) // Create a white border
                                    .frame(height: 50) // Adjust this to fit your text size
                                    .padding(.horizontal)

                                Text("MOVE WITHIN RANGE")
                                    .monospaced()
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .opacity(0.7)
                        }
                    }
                }
                
                if scanState == .scanning {
                    Spacer()
                    
                    CompassView(viewModel: cameraViewController, scanState: $scanState, scanDirection: $scanDirection)
                        .frame(height: 20)
                        .padding()
                }
            }
            .padding()
        }
        .navigationBarHidden(true)
        .statusBar(hidden: true)
    }
    
    private var scanInstruction: String {
        switch scanState {
        case .ready:
            if determineStatus().text.contains("OPTIMAL") {
                return "Let's do this!"
            } else {
                return "Align your face within the frame."
            }
        case .scanning:
            switch scanDirection {
            case .left:
                return "Turn your head"
            case .front:
                return "Now, face the"
            case .right:
                return "Turn your head"
            }
        case .completed:
            return "Scanning"
        }
    }
    
    private var scanInstruction2: String {
        switch scanState {
        case .ready:
            return ""
        case .scanning:
            switch scanDirection {
            case .left:
                return "LEFT"
            case .front:
                return "FRONT"
            case .right:
                return "RIGHT"
            }
        case .completed:
            return "COMPLETE"
        }
    }
    
    private func startScanning() {
        // Temporary addition to prevent previous scans from showinwg up...
        OpticALLYApp.clearDocumentsFolder()
        
        withAnimation {
            scanState = .scanning
        }
    }
    
    private func viewResults() {
        withAnimation {
            globalState.currentView = .postScanning
        }
    }
    
    private func handleFaceDirectionChange(yawAngle: Double) {
        guard scanState == .scanning else { return }
        
        switch scanDirection {
        case .front where abs(yawAngle) < 10:
            captureFrame()
            
            withAnimation {
                scanDirection = .left
            }
        case .left where yawAngle > 20:
            captureFrame()
            
            withAnimation {
                scanDirection = .right
            }
        case .right where yawAngle < -20:
            captureFrame()
            
            withAnimation {
                scanState = .completed
                showLog = true
            }
        default:
            break
        }
    }
}

struct DistanceIndicator: View {
    @ObservedObject var cameraViewController: CameraViewController
    
    var body: some View {
        let status = determineStatus()
        
        return (
            VStack {
                Text("\(status.text)\(!status.text.contains("POSITION") ? " \(cameraViewController.faceDistance ?? 0) CM" : "")")
                    .bold()
                    .monospaced()
                    .padding()
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
                .background(status.color)
                .cornerRadius(20)
        )
    }
}

func determineStatus() -> (text: String, color: Color) {
    guard let distance = cameraViewController.faceDistance else { return ("POSITION YOURSELF", Color(.white).opacity(0.2)) }
    
    switch distance {
    case ..<30: // Assuming distance is measured in some unit where 30 is too close
        return ("TOO CLOSE", .red.opacity(0.3))
    case 30..<40: // Assuming 30 to 40 is the optimal range
        return ("OPTIMAL", .green.opacity(0.3))
    case 40...: // Assuming distance more than 40 is too far
        return ("TOO FAR", .yellow.opacity(0.3))
    default:
        return ("POSITION YOURSELF", Color(.white).opacity(0.2))
    }
}

struct DirectionIndicatorView: View {
    @Binding var scanDirection: ScanDirection
    
    @ObservedObject var cameraViewController: CameraViewController
    
    var body: some View {
        ZStack {
            // Left half
            Path { path in
                path.addArc(center: CGPoint(x: 110, y: 110), radius: 110, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 270), clockwise: true)
                path.addLine(to: CGPoint(x: 110, y: 110))
                path.closeSubpath()
            }
            .fill(self.scanDirection == .right && cameraViewController.faceYawAngle < -20 ? Color.green : Color.gray.opacity(0.5))
            
            // Right half
            Path { path in
                path.addArc(center: CGPoint(x: 110, y: 110), radius: 110, startAngle: Angle(degrees: 270), endAngle: Angle(degrees: 90), clockwise: true)
                path.addLine(to: CGPoint(x: 110, y: 110))
                path.closeSubpath()
            }
            .fill(self.scanDirection == .left && cameraViewController.faceYawAngle > 20 ? Color.green : Color.gray.opacity(0.5))
            
            // Center indication - entire circle
            if scanDirection == .front && abs(cameraViewController.faceYawAngle) < 10 {
                Circle()
                    .fill(Color.green.opacity(0.5))
                    .frame(width: 220, height: 220)
            }
        }
    }
}
