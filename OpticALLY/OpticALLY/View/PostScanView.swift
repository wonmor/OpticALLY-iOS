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
    
    @State private var isMesh: Bool = false
    @State private var triggerUpdate: Bool = false
    
    var body: some View {
        VStack {
            HStack {
                Button(action: {
                    ExternalData.reset()
                    globalState.currentView = .scanning
                }) {
                    Image(systemName: "arrow.left") // You can customize this with your own back button image
                        .foregroundStyle(.white)
                        .font(.title)
                        .padding()
                }
                
                Text("Your Scan")
                    .font(.system(.title)) // Using monospaced font
                    .monospaced()
                Spacer()
            }
            .padding(.top)
            
            if triggerUpdate {
                SceneKitMDLView(mdlAsset: MDLAsset(url: exportViewModel.fileURL!))
                    .onAppear(perform: {
                        print("File URL: \(exportViewModel.fileURL!)")
                    })
                
            } else {
                SceneKitView(geometry: ExternalData.pointCloudGeometry)
                    .ignoresSafeArea(edges: .bottom)
            }
            
            Spacer()
            
            if !isMesh {
                Button(action: {
                    exportViewModel.exportOBJ()
                    isMesh = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.forward.dottedline.fill")
                        
                        Text("Convert to Mesh")
                            .bold()
                            .font(.title3)
                    }
                    .padding()
                    .foregroundColor(.white)
                    .background(Capsule().fill(Color(.darkGray)))
                }
                .padding()
                
            } else if !exportViewModel.isLoading && triggerUpdate {
                Text("Surface Reconstruct\nComplete!")
                    .monospaced()
                    .padding()
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
                .onDisappear() {
                    // Upon .OBJ conversion completion, refresh SceneKitView
                    triggerUpdate = true
                }
            }
        }
    }
}


struct PostScanView_Previews: PreviewProvider {
    static var previews: some View {
        PostScanView()
            .preferredColorScheme(.dark)
    }
}
