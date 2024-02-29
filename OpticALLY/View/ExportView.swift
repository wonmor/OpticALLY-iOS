import SwiftUI
import Lottie
import ARKit

struct ExportView: View {
    @EnvironmentObject var globalState: GlobalState
    @StateObject var faceTrackingViewModel: FaceTrackingViewModel
    
    @State private var scanState: ScanState = .ready
    @State private var scanDirection: ScanDirection = .left
    @State private var showScanCompleteView: Bool = false
    
    enum ScanState {
        case ready, scanning, completed
    }
    
    enum ScanDirection {
        case left, front, right
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Spacer()
                
                DistanceIndicator(cameraViewController: cameraViewController)
                
                Text(scanInstruction)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                
                FaceIDScanView(cameraViewController: cameraViewController)
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())
                    .padding()
                    .onChange(of: faceTrackingViewModel.faceYawAngle) { newValue in
                        handleFaceDirectionChange(yawAngle: newValue)
                    }
                
                Spacer()
                
                if scanState != .scanning {
                    Button(action: startScanning) {
                        Text(scanState == .ready ? "Start Scanning" : "Scan Completed")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Capsule().fill(Color.blue))
                    }
                    .padding(.horizontal)
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
        withAnimation {
            scanState = .scanning
        }
    }
    
    private func handleFaceDirectionChange(yawAngle: Double) {
        guard scanState == .scanning else { return }
        
        switch scanDirection {
        case .left where yawAngle < -20:
            withAnimation {
                scanDirection = .front
            }
        case .front where abs(yawAngle) < 10:
            withAnimation {
                scanDirection = .right
            }
        case .right where yawAngle > 20:
            withAnimation {
                scanState = .completed
                globalState.currentView = .postScanning
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
        
        return Text(status.text)
            .bold()
            .padding()
            .foregroundColor(.white)
            .background(status.color)
            .cornerRadius(20)
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

