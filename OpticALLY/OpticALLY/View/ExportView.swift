//
//  ExportView.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import SwiftUI

enum CurrentState {
    case begin, start
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
    
    @ObservedObject var logManager = LogManager.shared
    @EnvironmentObject var globalState: GlobalState
    @StateObject private var exportViewModel = ExportViewModel()
    
    let maxOffset: CGFloat = 30.0 // change this to control how much the finger moves
    
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
                    
                    // Button to start/pause scanning
                    Button(action: {
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
                            VStack {
                                Image(systemName: "sunglasses.fill")
                                    .font(.largeTitle) // Adjust the size of the icon
                                
                                Text("Scan")
                                    .font(.title3)
                                    .bold()
                            }
                            .padding() // Even padding around VStack contents
                            .foregroundColor(.white) // Text and icon color
                            .background(Circle().fill(Color.black)) // Circle shape filled with black color
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: 2) // White border around the circle
                            )
                        }
                    }
                    .padding(.bottom)
                }
                
            case .start:
                VStack {
                    Button(action: {
                        ExternalData.renderingEnabled.toggle()
                        currentState = .begin
                        isScanComplete = false
                    }) {
                        HStack {
                            Image(systemName: "arrow.left") // Using system arrow left image for back
                            Text("Back")
                        }
                        .padding()
                        .foregroundColor(.primary) // Adjust color as needed
                    }
                    .navigationBarItems(leading:
                                            Button(action: {
                        // Handle your back action here
                    }) {
                        Image(systemName: "arrow.left")
                    }
                    )
                    
                    Image("1024")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 20)) // Clips the image as a rounded rectangle
                        .overlay(
                            RoundedRectangle(cornerRadius: 20) // Applies a border on top of the rounded rectangle image
                                .stroke(Color.primary, lineWidth: 2) // Adjust the color and line width as needed
                        )
                        .accessibility(hidden: true)
                    
                    Text("HAROLDEN")
                        .bold()
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .padding(.bottom)
                    
                    FaceIDScanView(isScanComplete: $isScanComplete, showDropdown: $showDropdown)
                        .background(Color.black.opacity(0.8).blur(radius: 40.0))
                    
                    if isScanComplete {
                        VStack {
                            Button(action: {
                                // Toggle the dropdown
                                showDropdown.toggle()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.down.circle")
                                    Text("DOWNLOAD")
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
                                    Button(action: {
                                        
                                    }) {
                                        Text(".PLY")
                                            .padding()
                                            .foregroundColor(.white)
                                            .background(Capsule().fill(Color.gray.opacity(0.4)))
                                    }
                                }
                                .padding(.top, 5)
                                
                            } else {
                                Button(action: {
                                    ExternalData.renderingEnabled.toggle()
                                    currentState = .begin
                                    isScanComplete = false
                                }) {
                                    Text("RESCAN")
                                        .font(.body)
                                        .bold()
                                        .foregroundColor(.white)
                                        .padding()
                                }
                                .background(Color.black.opacity(0.8).blur(radius: 40.0))
                            }
                            
                        }
                        .padding()
                        
                    } else {
                        Text("For an accurate scan, ensure you pan around the sides, top, and bottom of your face.")
                            .font(.caption)
                            .bold()
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                            .foregroundColor(.white)
                    }
                    
                }
                .background(isScanComplete ? Color.clear.blur(radius: 40.0) : Color.black.opacity(0.8).blur(radius: 40.0))
            }
        }
        .padding()
        .onAppear {
            // Make it pause due to thermal concerns...
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                ExternalData.renderingEnabled = false
            }
        }
        .foregroundColor(isFlashOn ? .black : .white)
    }
}
