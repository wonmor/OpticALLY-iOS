import SwiftUI
import Lottie
import ARKit

struct ExportView: View {
    @EnvironmentObject var globalState: GlobalState
    
    @StateObject private var exportViewModel = ExportViewModel()
    
    @ObservedObject var logManager = LogManager.shared
    
    @State private var scanState: ScanState = .ready
    @State private var scanDirection: ScanDirection = .left
    @State private var showScanCompleteView: Bool = false
    
    @State private var showLog: Bool = false
    @State private var hideMoveOnButton: Bool = false
    
    enum ScanState {
        case ready, scanning, completed
    }
    
    enum ScanDirection {
        case left, front, right
    }
    
    private func captureFrame() {
        ExternalData.isSavingFileAsPLY = true
        HapticManager.playHapticFeedback(type: .warning)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Spacer()
                
                DistanceIndicator(cameraViewController: cameraViewController)
                
                if showLog {
                    if let lastLog = logManager.latestLog {
                        Text(lastLog)
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
                            LottieView(animationFileName: "face-found-successfully", loopMode: .playOnce)
                                .frame(width: 60, height: 60)
                                .scaleEffect(0.5)
                                .opacity(0.5)
                                .padding(.vertical)
                                .colorInvert()
                                .onAppear() {
                                    // Only do this for the LAST iteration of the 3 scans... (3rd scan) -> Because UI will be hidden until then, it's fine for now when it comes to logic
                                    exportViewModel.hasTurnedLeft = true
                                    exportViewModel.hasTurnedRight = true
                                    exportViewModel.hasTurnedCenter = true
                                    
                                    hideMoveOnButton = false
                                    
                                    print("시험 전날")
                                }
                        }
                    }
                } else {
                    Text(scanInstruction)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                }
                
                ZStack {
                    // Segmented circle behind the FaceIDScanView
                    DirectionIndicatorView(scanDirection: $scanDirection, faceYawAngle: cameraViewController.faceYawAngle)
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
                            Button(action: viewResults) {
                                Text("View Results")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Capsule().fill(Color.gray.opacity(0.4)))
                            }
                            .padding(.horizontal)
                        }
                        
                    } else {
                        Button(action: startScanning) {
                            Text("Start Scanning")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Capsule().fill(Color.gray.opacity(0.4)))
                        }
                        .padding(.horizontal)
                    }
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
            return "Align your face within the frame and ensure good lighting."
        case .scanning:
            switch scanDirection {
            case .left:
                return "Turn your head to the left."
            case .front:
                return "Now, face the front."
            case .right:
                return "Turn your head to the right."
            }
        case .completed:
            return "Scanning complete!"
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
        globalState.currentView = .postScanning
    }
    
    private func handleFaceDirectionChange(yawAngle: Double) {
        guard scanState == .scanning else { return }
        
        switch scanDirection {
        case .left where yawAngle > 20:
            captureFrame()
            
            withAnimation {
                scanDirection = .front
            }
        case .front where abs(yawAngle) < 10:
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
                Text("\(status.text)\(status.text.contains("FAR") || status.text.contains("CLOSE") ? "\n\(cameraViewController.faceDistance ?? 0) cm" : "")")
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
    
    private func determineStatus() -> (text: String, color: Color) {
        guard let distance = cameraViewController.faceDistance else { return ("Position Yourself", Color(.white).opacity(0.2)) }
        
        switch distance {
        case ..<30: // Assuming distance is measured in some unit where 30 is too close
            return ("TOO CLOSE", .red.opacity(0.3))
        case 30..<40: // Assuming 30 to 40 is the optimal range
            return ("OPTIMAL", .green.opacity(0.3))
        case 40...: // Assuming distance more than 40 is too far
            return ("TOO FAR", .yellow.opacity(0.3))
        default:
            return ("Position Yourself", Color(.white).opacity(0.2))
        }
    }
}

struct DirectionIndicatorView: View {
    @Binding var scanDirection: ExportView.ScanDirection
    var faceYawAngle: Double
    
    var body: some View {
        ZStack {
            // Left half
            Path { path in
                path.addArc(center: CGPoint(x: 110, y: 110), radius: 110, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 270), clockwise: true)
                path.addLine(to: CGPoint(x: 110, y: 110))
                path.closeSubpath()
            }
            .fill(self.scanDirection == .right && faceYawAngle < -20 ? Color.green : Color.gray.opacity(0.5))
            
            // Right half
            Path { path in
                path.addArc(center: CGPoint(x: 110, y: 110), radius: 110, startAngle: Angle(degrees: 270), endAngle: Angle(degrees: 90), clockwise: true)
                path.addLine(to: CGPoint(x: 110, y: 110))
                path.closeSubpath()
            }
            .fill(self.scanDirection == .left && faceYawAngle > 20 ? Color.green : Color.gray.opacity(0.5))
            
            // Center indication - entire circle
            if scanDirection == .front && abs(faceYawAngle) < 10 {
                Circle()
                    .fill(Color.green.opacity(0.5))
                    .frame(width: 220, height: 220)
            }
        }
    }
}
