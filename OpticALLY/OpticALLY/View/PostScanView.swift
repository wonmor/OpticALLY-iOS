//
//  PostScanView.swift
//  OpticALLY
//
//  Created by John Seong on 11/10/23.
//

import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO

struct PostScanView: View {
    @EnvironmentObject var globalState: GlobalState
    
    @ObservedObject private var exportViewModel = ExportViewModel()
    
    @State private var triggerUpdate: Bool = false
    @State private var showCompletionCheckmark = false
    @State private var showAlert = false
    @State private var isInteractionDisabled = false
    @State private var showTimeoutAlert = false
    
    var body: some View {
        ZStack {
            if showCompletionCheckmark {
                CheckmarkView(isVisible: $showCompletionCheckmark, isInteractionDisabled: $isInteractionDisabled)
                    .zIndex(20.0)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            withAnimation {
                                showCompletionCheckmark = false
                            }
                        }
                    }
            }
            
            VStack {
                HStack {
                    Button(action: {
                        ExternalData.reset()
                        exportViewModel.reset()
                        globalState.currentView = .scanning
                    }) {
                        Image(systemName: "arrow.left") // You can customize this with your own back button image
                            .foregroundStyle(.white)
                            .font(.title)
                            .padding()
                    }
                    
                    Text("Your Scan")
                        .font(.system(.title)) // Using monospaced font
                    Spacer()
                }
                .padding(.top)
                
                if triggerUpdate {
                    if exportViewModel.fileURL != nil {
                        SceneKitMDLView(mdlAsset: MDLAsset(url: exportViewModel.fileURL!))
                            .onAppear(perform: {
                                print("File URL: \(exportViewModel.fileURL!)")
                            })
                    } else {
                        EmptyView()
                            .onAppear() {
                                self.showTimeoutAlert = true
                                
                            }
                            .alert(isPresented: $showTimeoutAlert) {
                                Alert(
                                    title: Text("Network Timeout"),
                                    message: Text("Unable to connect to the server. Please check your internet connection and try again."),
                                    dismissButton: .default(Text("OK"))
                                )
                            }
                    }
                    
                } else if !ExternalData.pointCloudGeometries.isEmpty {
                    SceneKitView()
                        .ignoresSafeArea(edges: .bottom)
                }
                
                Spacer()
                
                if !ExternalData.isMeshView {
                    Button(action: {
                        if OpticALLYApp.isConnectedToNetwork() {
                            exportViewModel.exportOBJ()
                            ExternalData.isMeshView = true
                        } else {
                            showAlert = true
                        }
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.forward.dottedline.fill")
                            
                            Text("Convert to Mesh")
                                .bold()
                                .font(.title3)
                        }
                        .padding()
                        .foregroundColor(.white)
                        .background(Capsule().fill(Color.clear)) // Transparent background
                        .overlay(
                            Capsule().stroke(Color.white, lineWidth: 2) // White border
                        )
                    }
                    .padding()
                    
                } else if !exportViewModel.isLoading {
                    Text("**\(ExternalData.verticesCount)** VERTICES")
                        .monospaced()
                        .padding()
                        .multilineTextAlignment(.center)
                }
                
                // Display a loading spinner when isLoading is true
                if exportViewModel.isLoading {
                    VStack(spacing: 10) { // Adjust spacing as needed
                        ProgressView()
                            .scaleEffect(1.5, anchor: .center) // Adjust size as needed
                            .progressViewStyle(CircularProgressViewStyle(tint: .white)) // Spinner color
                            .padding()
                        
                        Text("PROCESSING POINT CLOUD")
                            .bold()
                            .monospaced()
                            .foregroundColor(.white)
                        
                        if exportViewModel.estimatedExportTime != nil {
                            Text("Estimated:\n\(exportViewModel.estimatedExportTime!) sec.")
                                .monospaced()
                                .foregroundColor(.white)
                        } else {
                            Text("Estimated:\nN/A")
                                .monospaced()
                                .foregroundColor(.white)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30) // Adjust horizontal padding for wider background
                    .padding(.vertical, 15) // Adjust vertical padding for background height
                    .zIndex(1) // Ensure the spinner and text are above other content
                    .onDisappear {
                        triggerUpdate = true
                        showCompletionCheckmark = true
                        
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                }
            }
            .allowsHitTesting(!(exportViewModel.isLoading || isInteractionDisabled)) // Disabling hit testing when loading or interaction is disabled
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("No Internet Connection"),
                    message: Text("Please check your internet connection and try again."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

struct CheckmarkView: View {
    @Binding var isVisible: Bool
    @Binding var isInteractionDisabled: Bool
    
    var body: some View {
        VStack(spacing: 10) { // Adjust the spacing as needed
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 60, height: 60) // Adjust the size as needed
                .foregroundColor(.black)
            
            Text("Done")
                .font(.headline) // Adjust the font style as needed
                .bold()
                .foregroundColor(.black)
        }
        .padding() // Adjust the padding to change the size of the background
        .background(Color.white) // Black background
        .cornerRadius(20) // Rounded corners, adjust radius as needed
        .onAppear {
            isInteractionDisabled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isInteractionDisabled = false
            }
        }
    }
}
