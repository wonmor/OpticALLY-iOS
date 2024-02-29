//
//  ExportView.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import SwiftUI
import Lottie

enum CurrentState {
    case prescan
    case scan
    case postscan
}

struct ShareSheet: UIViewControllerRepresentable {
    var fileURL: URL
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct FlashButtonView: View {
    @Binding var isFlashOn: Bool
    
    var body: some View {
        Button(action: toggleFlash) {
            Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                .foregroundColor(isFlashOn ? .black : .gray)
                .font(.title)
        }
        .padding(.top)
    }
    
    private func toggleFlash() {
        HapticManager.playHapticFeedback(type: .error)
        isFlashOn.toggle()
        // Update camera flash setting here
    }
}

enum HeadTurnState {
    case left, center, right
}

struct ExportView: View {
    @State private var isViewLoaded: Bool = false
    @State private var fingerOffset: CGFloat = -30.0
    @State private var isAnimationActive: Bool = true
    @State private var currentState: CurrentState = .prescan
    @State private var showDropdown: Bool = false
    @State private var showConsoleOutput: Bool = false
    @State private var showAlert = false
    @State private var showArrow = true
    @State private var isFlashOn = false
    @State private var isLeftHalf = true
    @State private var headTurnState = HeadTurnState.center
    @State private var headTurnMessage = ""
    @State private var isRingAnimationStarted = false
    @State private var startButtonPressed = false
    @State private var showFaceTrackingView = true
    @State private var stateChangeCount = 0
    @State private var previousYaw: Double = 0
    @State private var isButtonDisabled: Bool = false
    
    // Target states for scanning
    @State private var targetYaw: Double = 0
    @State private var targetPitch: Double = 0
    @State private var targetRoll: Double = 0
    
    @State private var isScanComplete: Bool = false
    
    @State private var showFaceIdLoading = false
    @State private var showFaceIdSuccessful = false

    // Counter to keep track of the number of scans
    @State private var scanCount = 0
    
    @ObservedObject var logManager = LogManager.shared
    @EnvironmentObject var globalState: GlobalState
    @StateObject private var exportViewModel = ExportViewModel()
    
    @StateObject var faceTrackingViewModel: FaceTrackingViewModel
    
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
    
    let maxOffset: CGFloat = 30.0 // change this to control how much the finger moves
    
    private func captureFrame() {
        ExternalData.isSavingFileAsPLY = true
    }

    var body: some View {
        ZStack {
            if showFaceTrackingView {
                ZStack {
//                    ARFaceTrackingView()
//                        .opacity(0.5)
//                        .scaledToFit()
                }
                .padding()
                .onAppear {
                    previousYaw = faceTrackingViewModel.faceYawAngle
                }
                .onChange(of: faceTrackingViewModel.faceYawAngle) { yaw in
                    if startButtonPressed {
                        let pitch = faceTrackingViewModel.facePitchAngle
                        let roll = faceTrackingViewModel.faceRollAngle
                        
                        // Rotate the USDZ model
                        if yaw <= -30 {
                            // Rotate model to face right and trigger haptic feedback
                            captureFrame()
                            
                            HapticManager.playHapticFeedback(type: .success)
                            exportViewModel.hasTurnedRight = true
                            
                            showArrow = true
                            headTurnMessage = "TURN YOUR HEAD LEFT"
                            headTurnState = .left
                            
                        } else if yaw >= 30 {
                            // Rotate model to face left and trigger haptic feedback
                            captureFrame()
                            
                            HapticManager.playHapticFeedback(type: .success)
                            exportViewModel.hasTurnedLeft = true
                            
                            showArrow = true
                            headTurnMessage = "TURN YOUR HEAD RIGHT"
                            headTurnState = .right
                        }
                        
                        // User has turned face left and right but not towards the center
                        if exportViewModel.hasTurnedRight && exportViewModel.hasTurnedLeft && !exportViewModel.hasTurnedCenter {
                            if yaw >= -10 && yaw <= 10 {
                                // Rotate model to face center and trigger haptic feedback
                                captureFrame()
                                
                                HapticManager.playHapticFeedback(type: .success)
                                exportViewModel.hasTurnedCenter = true
                            } else {
                                showArrow = true
                                headTurnMessage = "TURN YOUR HEAD CENTER"
                                headTurnState = .center
                            }
                        }
                        
                        if exportViewModel.hasTurnedRight && exportViewModel.hasTurnedLeft && exportViewModel.hasTurnedCenter {
                            headTurnMessage = "SCAN COMPLETE"
                            HapticManager.playHapticFeedback(type: .success) // Play completion haptic
                            showConsoleOutput = true
                            showArrow = false
                            isRingAnimationStarted = false
                            isFlashOn = true
                            startButtonPressed = false
                            showFaceTrackingView = false
                            isScanComplete = true
                        }
                    }
                }
            }
            
            Color(isFlashOn ? .white : .clear)
                .edgesIgnoringSafeArea(.all)
                .clipShape(RoundedRectangle(cornerRadius: 20)) // Clips the image as a rounded rectangle
            
            switch currentState {
            case .postscan:
                EmptyView()
            case .scan:
                EmptyView()
            case .prescan:
                VStack {
                    if showFaceTrackingView {
                        FlashButtonView(isFlashOn: $isFlashOn)
                            .zIndex(20.0)
                    }
                    
                    if showConsoleOutput {
                        ScrollView {
                            if let lastLog = logManager.latestLog {
                                if showDropdown == false {
                                    Text(lastLog)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .multilineTextAlignment(.center)
                                        .monospaced()
                                    
                                    if lastLog.contains("Converting") {
                                        EmptyView()
                                            .onAppear() {
                                                print("showFaceIdLoading = true")
                                                self.showFaceIdLoading = true
                                            }
                                    }
                                    
                                    if lastLog.contains("Done") {
                                        EmptyView()
                                            .onAppear() {
                                                print("showFaceIdSuccessful = true")
                                                self.showFaceIdSuccessful = true
                                            }
                                    }
                                }
                            }
                        }
                        .onDisappear {
                            logManager.stopTimer()
                        }
                        
                    } else if headTurnMessage != "" {
                        ScrollView {
                            Text(headTurnMessage)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .monospaced()
                        }
                        
                    } else {
                        ScrollView {
                            Text("SCREEN DISTANCE\n\(cameraViewController.faceDistance ?? 0) cm")
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .monospaced()
                        }
                    }
                    
                    FaceIDScanView(isScanComplete: $isScanComplete, cameraViewController: cameraViewController, showFaceIdLoading: $showFaceIdLoading, showFaceIdSuccessful: $showFaceIdSuccessful)
                        .padding()
              
                    
                    if showArrow {
                        if headTurnState == .left {
                            // Display a large arrow pointing to the direction the user should turn their head
                            if isFlashOn {
                                LottieView(animationFileName: "left-arrow-2", loopMode: .loop)
                                    .frame(width: 60, height: 60)
                                    .scaleEffect(0.2)
                                    .opacity(0.5)
                                    .padding(.bottom)
                                
                            } else {
                                LottieView(animationFileName: "left-arrow-2", loopMode: .loop)
                                    .frame(width: 60, height: 60)
                                    .colorInvert()
                                    .scaleEffect(0.2)
                                    .opacity(0.5)
                                    .padding(.bottom)
                            }
                            
                        } else if headTurnState == .right {
                            // Display a large arrow pointing to the direction the user should turn their head
                            if isFlashOn {
                                LottieView(animationFileName: "right-arrow-2", loopMode: .loop)
                                    .frame(width: 60, height: 60)
                                    .scaleEffect(0.2)
                                    .opacity(0.5)
                                    .padding(.bottom)
                                
                            } else {
                                LottieView(animationFileName: "right-arrow-2", loopMode: .loop)
                                    .frame(width: 60, height: 60)
                                    .colorInvert()
                                    .scaleEffect(0.2)
                                    .opacity(0.5)
                                    .padding(.bottom)
                            }
                            
                        }
                    }

                    Spacer()
                    
                    // Button to start/pause scanning
                    if !isRingAnimationStarted {
                        Button(action: {
                            if !isButtonDisabled {
                                // Temporary addition to prevent previous scans from showinwg up...
                                OpticALLYApp.clearDocumentsFolder()
                                // REMOVE ABOVE LINE IN PRODUCTION!
                                
                                HapticManager.playHapticFeedback(type: .success)
                                headTurnMessage = "TURN YOUR HEAD\nLEFT/RIGHT"
                                isRingAnimationStarted = true  // Start the ring animation
                                startButtonPressed = true
                            }
                        }) {
                            if showConsoleOutput {
                                if let lastLog = logManager.latestLog {
                                    if lastLog.lowercased().contains("done") {
                                        VStack {
                                            Button(action: {
                                                globalState.currentView = .postScanning
                                            }) {
                                                VStack {
                                                    Image(systemName: "ruler")
                                                        .font(.title)
                                                    
                                                    Text("Measure")
                                                        .font(.body)
                                                        .bold()
                                                }
                                                .padding()
                                                .foregroundColor(.white)
                                                .background(Capsule().fill(Color.black).overlay(Capsule().stroke(Color.white, lineWidth: 2)))
                                            }
                                        }
                                        .padding()
                                    } else {
                                        HStack {
                                            Image(systemName: "circle.dotted") // Different SF Symbols for start and pause
                                            Text("Processing")
                                                .bold()
                                                .onAppear() {
                                                    isButtonDisabled = true
                                                }
                                        }
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Capsule().fill(Color.black).overlay(Capsule().stroke(Color.white, lineWidth: 2)))
                                    }
                                }
                            } else {
                                VStack(spacing: 5) {
                                    Text("Start")
                                        .font(.title3)
                                        .bold()
                                        .onAppear() {
                                            isButtonDisabled = false
                                        }
                                    
                                    Image(systemName: "arrow.up")
                                        .font(.largeTitle) // Adjust the size of the icon
                                }
                                .foregroundColor(.white) // Text and icon color
                                .padding() // Padding around VStack
                                .background(Capsule().fill(Color.black)) // Capsule shape filled with black color
                                .overlay(
                                    Capsule().stroke(Color.white, lineWidth: 2) // White border around the capsule
                                )
                            }
                        }
                        .padding(.bottom)
                    }
                }
            }
        }
        .padding()
        .foregroundColor(isFlashOn ? .black : .white)
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Setting the frame size to infinity
        .ignoresSafeArea()
    }
}
