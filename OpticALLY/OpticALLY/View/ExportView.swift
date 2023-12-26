//
//  ExportView.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import SwiftUI

enum CurrentState {
    case begin
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
    @State private var currentState: CurrentState = .begin
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
    @State private var stateChangeCount = 0
    @State private var previousYaw: Double = 0
    
    // Target states for scanning
    @State private var targetYaw: Double = 0
    @State private var targetPitch: Double = 0
    @State private var targetRoll: Double = 0

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
            Color(isFlashOn ? .white : .clear)
                .edgesIgnoringSafeArea(.all)
                .clipShape(RoundedRectangle(cornerRadius: 20)) // Clips the image as a rounded rectangle
            
            // Display a loading spinner when isLoading is true
            if exportViewModel.isLoading {
                VStack(spacing: 10) { // Adjust spacing as needed
                    ProgressView()
                        .scaleEffect(2.5, anchor: .center) // Adjust size as needed
                        .progressViewStyle(CircularProgressViewStyle(tint: isFlashOn ? .white : .black)) // Spinner color
                        .padding()
                    
                    Text("EXPORT IN PROGRESS")
                        .bold()
                        .monospaced()
                        .foregroundColor(isFlashOn ? .white : .black)
                    
                    if exportViewModel.estimatedExportTime != nil {
                        Text("Estimated:\n\(exportViewModel.estimatedExportTime!) sec.")
                            .monospaced()
                            .foregroundColor(isFlashOn ? .white :.black)
                    } else {
                        Text("Estimated:\nN/A")
                            .monospaced()
                            .foregroundColor(isFlashOn ? .white :.black)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30) // Adjust horizontal padding for wider background
                .padding(.vertical, 15) // Adjust vertical padding for background height
                .background(isFlashOn ? .black : .white) // Adjust background color and opacity
                .cornerRadius(25) // Gives the pill shape
                .zIndex(1) // Ensure the spinner and text are above other content
            }
            
            switch currentState {
            case .begin:
                VStack {
                    FlashButtonView(isFlashOn: $isFlashOn)
                    
                    Text("YAW \(Int(round(faceTrackingViewModel.faceYawAngle)))°\nPITCH \(Int(round(faceTrackingViewModel.facePitchAngle)))°")
                        .bold()
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .monospaced()
                    
                    if showConsoleOutput {
                        ScrollView {
                            if let lastLog = logManager.latestLog {
                                Text(lastLog)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .multilineTextAlignment(.center)
                                    .monospaced()
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
                            Text("PUPIL DISTANCE\n\(faceTrackingViewModel.pupilDistance) mm")
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .monospaced()
                        }
                    }
                    
                    if showArrow {
                        if headTurnState == .left {
                            // Display a large arrow pointing to the direction the user should turn their head
                            Image(systemName: "arrow.left")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 50, height: 50)
                                .foregroundColor(isFlashOn ? .black : .white)
                            
                        } else if headTurnState == .right {
                            // Display a large arrow pointing to the direction the user should turn their head
                            Image(systemName: "arrow.right")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 50, height: 50)
                                .foregroundColor(isFlashOn ? .black : .white)
                            
                        } else if headTurnState == .center {
                            HStack {
                                // Left Arrow
                                Image(systemName: "arrow.left")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 50, height: 50)
                                    .foregroundColor(isFlashOn ? .black : .white)

                                // Right Arrow
                                Image(systemName: "arrow.right")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 50, height: 50)
                                    .foregroundColor(isFlashOn ? .black : .white)
                            }
                        }
                    }
                    
                    Spacer()
                    // Progress indicator and head turn message
                    ZStack {
                        ARFaceTrackingView()
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
                            
                            if exportViewModel.hasTurnedRight && exportViewModel.hasTurnedLeft {
                                headTurnMessage = "SCAN COMPLETE"
                                HapticManager.playHapticFeedback(type: .success) // Play completion haptic
                                showConsoleOutput = true
                                showArrow = false
                                isRingAnimationStarted = false
                                isFlashOn = true
                                startButtonPressed = false
                            }
                        }
                    }

                    
                    Spacer()
                    
                    // Button to start/pause scanning
                    if !isRingAnimationStarted {
                        Button(action: {
                            HapticManager.playHapticFeedback(type: .success)
                            headTurnMessage = "TURN YOUR HEAD\nLEFT/RIGHT"
                            isRingAnimationStarted = true  // Start the ring animation
                            startButtonPressed = true
                            // captureFrame() -> for center scan...
                        }) {
                            if showConsoleOutput {
                                if let lastLog = logManager.latestLog {
                                    if lastLog.lowercased().contains("done") {
                                        VStack {
                                            Button(action: {
                                                // Toggle the dropdown
                                                showDropdown.toggle()
                                            }) {
                                                HStack {
                                                    Image(systemName: "square.and.arrow.down")
                                                    Text("Export")
                                                        .font(.body)
                                                        .bold()
                                                }
                                                .foregroundColor(.black)
                                                .padding()
                                                .background(Capsule().fill(Color.white))
                                            }
                                            
                                            // Dropdown list view
                                            if showDropdown {
                                                VStack {
                                                    HStack {
                                                        Button(action: {
                                                            // exportViewModel.exportPLY(showShareSheet: true)
                                                            exportViewModel.exportAV_PLY(showShareSheet: true)
                                                        }) {
                                                            Text(".PLY")
                                                                .padding()
                                                                .foregroundColor(.white)
                                                                .background(Capsule().fill(Color(.black)))
                                                        }
                                                        
                                                        // .OBJ Button
                                                        Button(action: {
                                                            if OpticALLYApp.isConnectedToNetwork() {
                                                                exportViewModel.exportOBJ()
                                                            } else {
                                                                showAlert = true
                                                            }
                                                        }) {
                                                            Text(".OBJ")
                                                                .padding()
                                                                .foregroundColor(.white)
                                                                .background(Capsule().fill(Color(.black)))
                                                        }
                                                        .alert(isPresented: $showAlert) {
                                                            Alert(
                                                                title: Text("No Internet Connection"),
                                                                message: Text("Please check your internet connection and try again."),
                                                                dismissButton: .default(Text("OK"))
                                                            )
                                                        }
                                                    }
                                                }
                                                .padding(.top, 5)
                                                .sheet(isPresented: $exportViewModel.showShareSheet, onDismiss: {
                                                    exportViewModel.showShareSheet = false
                                                }) {
                                                    // This will present the share sheet
                                                    if let fileURL = exportViewModel.fileURL {
                                                        ShareSheet(fileURL: fileURL)
                                                    }
                                                }
                                                
                                            } else {
                                                Button(action: {
                                                    globalState.currentView = .postScanning
                                                }) {
                                                    HStack {
                                                        Image(systemName: "checkmark.circle.fill")
                                                        Text("Continue")
                                                            .font(.body)
                                                            .bold()
                                                    }
                                                    .padding()
                                                    .foregroundColor(.white)
                                                    .background(Capsule().fill(Color.black).overlay(Capsule().stroke(Color.white, lineWidth: 2)))
                                                }
                                            }
                                            
                                        }
                                        .padding()
                                    } else {
                                        HStack {
                                            Image(systemName: "circle.dotted") // Different SF Symbols for start and pause
                                            Text("Reading")
                                                .font(.title3)
                                                .bold()
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

struct ExportView_Previews: PreviewProvider {
    static var previews: some View {
        ExportView(faceTrackingViewModel: faceTrackingViewModel)
            .environmentObject(GlobalState())
            .preferredColorScheme(.dark)
    }
}
