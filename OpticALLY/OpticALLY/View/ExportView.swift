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
    @State private var isScanComplete: Bool = false
    @State private var showDropdown: Bool = false
    @State private var showConsoleOutput: Bool = false
    @State private var showAlert = false
    @State private var isFlashOn = false
    @State private var isLeftHalf = true
    @State private var headTurnState = HeadTurnState.center
    @State private var headTurnMessage = "Turn your head center"
    @State private var isRingAnimationStarted = false
    @State private var stateChangeCount = 0
    
    @ObservedObject var logManager = LogManager.shared
    @EnvironmentObject var globalState: GlobalState
    @StateObject private var exportViewModel = ExportViewModel()
    
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
    
    let maxOffset: CGFloat = 30.0 // change this to control how much the finger moves
    
    private func progressView(for state: HeadTurnState) -> some View {
        Group {
            switch state {
            case .left:
                Circle()
                    .trim(from: 0.66, to: 1)
                    .stroke(.blue, lineWidth: 5)
                    .rotationEffect(Angle(degrees: -90))
            case .center:
                Circle()
                    .trim(from: 0.33, to: 0.66)
                    .stroke(.yellow, lineWidth: 5)
                    .rotationEffect(Angle(degrees: -90))
            case .right:
                Circle()
                    .trim(from: 0, to: 0.33)
                    .stroke(.green, lineWidth: 5)
                    .rotationEffect(Angle(degrees: -90))
            }
        }
        .frame(width: 200, height: 200)
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
                        .scaleEffect(1.5, anchor: .center) // Adjust size as needed
                        .progressViewStyle(CircularProgressViewStyle(tint: .black)) // Spinner color
                        .padding()
                    
                    Text("EXPORT IN PROGRESS")
                        .bold()
                        .monospaced()
                        .foregroundColor(.black)
                    
                    if exportViewModel.estimatedExportTime != nil {
                        Text("Estimated:\n\(exportViewModel.estimatedExportTime!) sec.")
                            .monospaced()
                            .foregroundColor(.black)
                    } else {
                        Text("Estimated:\nN/A")
                            .monospaced()
                            .foregroundColor(.black)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30) // Adjust horizontal padding for wider background
                .padding(.vertical, 15) // Adjust vertical padding for background height
                .background(Color.white) // Adjust background color and opacity
                .cornerRadius(25) // Gives the pill shape
                .zIndex(1) // Ensure the spinner and text are above other content
            }
            
            switch currentState {
            case .begin:
                VStack {
                    FlashButtonView(isFlashOn: $isFlashOn)
                    
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
                        
                    } else {
                        ScrollView {
                            Text("HAROLDEN\n3D CAPTURE")
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .monospaced()
                        }
                    }
                    
                    Spacer()
                    // Progress indicator and head turn message
                    ZStack {
                        Text(headTurnMessage)
                            .font(.title2)
                            .bold()
                            .multilineTextAlignment(.center)
                            .foregroundColor(isFlashOn ? .black : .white)
                            .padding()
                        
                        Circle()
                            .stroke(Color(.gray), lineWidth: 5)
                            .frame(width: 200, height: 200)
                        
                        progressView(for: headTurnState)
                    }
                    .padding()
                    .onReceive(timer) { _ in
                        if isRingAnimationStarted && stateChangeCount < 3 { // Check if the animation is started and the count is less than 4
                            withAnimation {
                                // Update head turn state and increment the count
                                switch headTurnState {
                                case .left:
                                    headTurnState = .center
                                    headTurnMessage = "Turn your head center"
                                case .center:
                                    headTurnState = .right
                                    headTurnMessage = "Turn your head right"
                                case .right:
                                    headTurnState = .left
                                    headTurnMessage = "Turn your head left"
                                }
                                stateChangeCount += 1 // Increment the state change counter
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Button to start/pause scanning
                    Button(action: {
                       isRingAnimationStarted = true  // Start the ring animation
                       showConsoleOutput = true
                       ExternalData.isSavingFileAsPLY = true
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
                                                        exportViewModel.exportPLY(showShareSheet: true)
                                                    }) {
                                                        Text(".PLY")
                                                            .padding()
                                                            .foregroundColor(.white)
                                                            .background(Capsule().fill(Color(.darkGray)))
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
                                                            .background(Capsule().fill(Color(.darkGray)))
                                                    }
                                                    .alert(isPresented: $showAlert) {
                                                        Alert(
                                                            title: Text("No Internet Connection"),
                                                            message: Text("Please check your internet connection and try again."),
                                                            dismissButton: .default(Text("OK"))
                                                        )
                                                    }
                                                }
                                                
                                                //                                                Button(action: {
                                                //                                                    exportViewModel.exportUSDZ()
                                                //                                                }) {
                                                //                                                    Text(".USDZ")
                                                //                                                        .padding()
                                                //                                                        .foregroundColor(.white)
                                                //                                                        .background(Capsule().fill(Color(.darkGray)))
                                                //                                                }
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
                                
                                Image(systemName: "faceid")
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
        .padding()
        .foregroundColor(isFlashOn ? .black : .white)
    }
}
