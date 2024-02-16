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
import PythonKit
import ZipArchive

let debugMode = false

struct PostScanView: View {
    @EnvironmentObject var globalState: GlobalState
    
    @ObservedObject private var exportViewModel = ExportViewModel()
    
    @State private var triggerUpdate: Bool = false
    @State private var showCompletionCheckmark = false
    @State private var showAlert = false
    @State private var isInteractionDisabled = false
    @State private var showTimeoutAlert = false
    @State private var resetSceneKitView: Bool = false
    
    @State private var selectedNodeIndex: Int?
    @State private var position = SCNVector3(0, 0, 0)
    @State private var rotation = SCNVector3(0, 0, 0)
    @State private var nodeCount = ExternalData.pointCloudGeometries.suffix(3).count
    
    @State private var uploadProgress: Double = 0.0
    @State private var isLoading: Bool = false
    
    @State private var scnNode: SCNNode?
    
    let fileManager = FileManager.default
    
    func reset() {
        position = SCNVector3(0, 0, 0)
        rotation = SCNVector3(0, 0, 0)
        
        selectedNodeIndex = nil
    }
    
    func convertFileData(fieldName: String,
                         fileName: String,
                         mimeType: String,
                         fileURL: URL,
                         using boundary: String) -> Data {
        var data = Data()

        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)

        if let fileData = try? Data(contentsOf: fileURL) {
            data.append(fileData)
        } else {
            print("Could not read file data")
        }

        data.append("\r\n".data(using: .utf8)!)

        return data
    }
    
    func uploadFiles(calibrationFileURL: URL, imageFilesZipURL: URL, depthFilesZipURL: URL, completion: @escaping (Bool, URL?) -> Void) {
        let endpoint = "https://harolden-server.apps.johnseong.com/process3d/"
        guard let url = URL(string: endpoint) else {
            print("Invalid URL")
            completion(false, URL(string: ""))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var data = Data()

        // Append Calibration File
        data.append(convertFileData(fieldName: "calibration_file",
                                    fileName: calibrationFileURL.lastPathComponent,
                                    mimeType: "application/json",
                                    fileURL: calibrationFileURL,
                                    using: boundary))

        // Append Image Files Zip
        data.append(convertFileData(fieldName: "image_files_zip",
                                    fileName: imageFilesZipURL.lastPathComponent,
                                    mimeType: "application/zip",
                                    fileURL: imageFilesZipURL,
                                    using: boundary))

        // Append Depth Files Zip
        data.append(convertFileData(fieldName: "depth_files_zip",
                                    fileName: depthFilesZipURL.lastPathComponent,
                                    mimeType: "application/zip",
                                    fileURL: depthFilesZipURL,
                                    using: boundary))

        data.append("--\(boundary)--".data(using: .utf8)!)

        request.httpBody = data

        // Create URLSessionUploadTask
        let task = URLSession.shared.uploadTask(with: request, from: data) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false  // Stop loading indicator
                if let data = data, error == nil {
                    // Save the PLY file
                    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("output_from_server.ply")
                    do {
                        try data.write(to: fileURL)
                        print("PLY file saved to: \(fileURL.path)")
                        completion(true, fileURL)  // Pass the file URL to the completion handler
                    } catch {
                        print("Failed to save PLY file: \(error.localizedDescription)")
                        completion(false, nil)
                    }
                } else {
                    print("Network error: \(error?.localizedDescription ?? "Unknown error")")
                    completion(false, nil)
                }
            }
        }

        // Handle upload progress
        task.observe(\.countOfBytesSent) { task, _ in
            DispatchQueue.main.async {
                let progress = Double(task.countOfBytesSent) / Double(task.countOfBytesExpectedToSend)
                self.uploadProgress = progress
            }
        }

        self.isLoading = true  // Start loading indicator
        task.resume()
    }
    
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
                        ExternalData.reset() {
                            exportViewModel.reset() {
                                // Reset position and rotation to default values
                                reset()
                                resetSceneKitView = true
                                globalState.currentView = .scanning
                            }
                        }
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
//                        SceneKitMDLView(mdlAsset: MDLAsset(url: exportViewModel.fileURL!))
//                            .onAppear(perform: {
//                                print("File URL: \(exportViewModel.fileURL!)")
//                            })
                        
                        if let node = scnNode {
                            SceneKitSingleView(node: node)
                                .frame(width: 300, height: 300)  // Adjust the size as needed
                        }
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
                    VStack {
                        SceneKitView(nodes: ExternalData.pointCloudNodes, resetTrigger: $resetSceneKitView)
                            .frame(height: 300)
                        
                        if debugMode {
                            // Node selection
                            HStack {
                                ForEach(0..<nodeCount, id: \.self) { index in
                                    Button("Node \(index)") {
                                        selectedNodeIndex = index
                                    }
                                }
                            }
                            
                            // Position controls
                            Text("Position")
                            Slider(value: Binding(
                                get: { Double(self.position.x) },
                                set: { self.position.x = Float($0) }
                            ), in: -1000...1000)
                            Slider(value: Binding(
                                get: { Double(self.position.y) },
                                set: { self.position.y = Float($0) }
                            ), in: -1000...1000)
                            Slider(value: Binding(
                                get: { Double(self.position.z) },
                                set: { self.position.z = Float($0) }
                            ), in: -1000...1000)
                            
                            // Rotation controls
                            Text("Rotation")
                            Slider(value: Binding(
                                get: { Double(self.rotation.x) },
                                set: { self.rotation.x = Float($0) }
                            ), in: -10...10)
                            Slider(value: Binding(
                                get: { Double(self.rotation.y) },
                                set: { self.rotation.y = Float($0) }
                            ), in: -10...10)
                            Slider(value: Binding(
                                get: { Double(self.rotation.z) },
                                set: { self.rotation.z = Float($0) }
                            ), in: -10...10)
                        }
                    }
                }
                
                Text("Perspective-n-Point & ICP\nWork in Progress")
                    .padding()
                    .monospaced()
                    .font(.title3)
                    .multilineTextAlignment(.center)
                
//                ZStack {
//                   RoundedRectangle(cornerRadius: 10) // Rounded rectangle shape
//                       .stroke(lineWidth: 2) // White border with a specified width
//                       .foregroundColor(.white) // Sets the color of the border
//                       .background(RoundedRectangle(cornerRadius: 10).fill(Color.white)) // Background color of the rectangle
//                       .shadow(radius: 5) // Optional: Adds a shadow for a 3D effect
//
//                   VStack(alignment: .center, spacing: 10) { // Vertical stack for your text
//                       Text("NOT APPLIED YET")
//                           .bold() // Makes the text bold
//                           .foregroundColor(.black) // Optional: Sets the color of the "NOT APPLIED YET" text
//                   }
//                   .padding() // Adds padding around the text inside the box
//               }
                
                Spacer()
                
                if !ExternalData.isMeshView {
                    Button(action: {
                        // Construct the paths for the calibration, image, and depth files
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy_MM_dd"
                        let dateString = dateFormatter.string(from: Date())
                        
                        let baseFolder = ExternalData.getFaceScansFolder().path // Assuming ExternalData.getFaceScansFolder() gives the base directory for the files
                        
                        let calibrationFilePath = "\(baseFolder)/calibration.json" // Assuming calibration file is named 'calibration.json'

                        let videoZipPath = "\(baseFolder)/videos.zip"
                        let depthZipPath = "\(baseFolder)/depths.zip"

                        let videoFiles = fileManager.getFilePathsWithPrefix(baseFolder: baseFolder, prefix: "video")
                        let depthFiles = fileManager.getFilePathsWithPrefix(baseFolder: baseFolder, prefix: "depth")

                        SSZipArchive.createZipFile(atPath: videoZipPath, withFilesAtPaths: videoFiles)
                        SSZipArchive.createZipFile(atPath: depthZipPath, withFilesAtPaths: depthFiles)

                        
                        uploadFiles(calibrationFileURL: URL(fileURLWithPath: calibrationFilePath), imageFilesZipURL: URL(fileURLWithPath: videoZipPath), depthFilesZipURL: URL(fileURLWithPath: depthZipPath)) { success, fileURL in
                               if success, let fileURL = fileURL {
                                   // Use the file URL, e.g., update the state, UI, etc.
                                   print("PLY file processed successfully. File URL: \(fileURL.path)")
                                   
                                   // Convert PLY to SceneKit model
                                   DispatchQueue.global(qos: .userInitiated).async {
                                       if let node = createSceneKitModel(fromPLYFile: fileURL.path) {
                                           DispatchQueue.main.async {
                                               self.scnNode = node  // Assign the converted SceneKit node
                                               self.triggerUpdate = true  // Trigger UI update
                                               // Update the state with the new PLY file URL
                                               self.exportViewModel.fileURL = fileURL
                                               // Indicate that the file is ready to be viewed or shared
                                               self.exportViewModel.showShareSheet = true
                                               // Mark the export process as completed
                                               self.exportViewModel.isLoading = false
                                               
                                               ExternalData.isMeshView = true
                                           }
                                       }
                                   }
                               } else {
                                   // Handle errors
                                   DispatchQueue.main.async {
                                       self.showAlert = true
                                   }
                               }
                           }
                
                        // let imageDepthInstance = imageDepth!.ImageDepth(calibrationFilePath, imageFilePath, depthFilePath)
                        
                        // Existing methods...
                        // exportViewModel.exportOBJ()
                        // ExternalData.isMeshView = true
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
                
                if isLoading {
                    VStack {
                        ProgressView("Uploading...", value: uploadProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                        Text("Please wait...")
                    }
                    .frame(width: 200, height: 100)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(10)
                    .shadow(radius: 10)
                }
                
                // Display a loading spinner when isLoading is true
                if exportViewModel.isLoading {
                    VStack(spacing: 10) { // Adjust spacing as needed
                        LottieView(animationFileName: "cargo-loading", loopMode: .loop)
                            .frame(width: 60, height: 60)
                            .scaleEffect(0.1)
                            .padding()
                            .colorInvert()
                        
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
