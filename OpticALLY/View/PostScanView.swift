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
import LinkPython

let debugMode = false

struct ShareSheet: UIViewControllerRepresentable {
    var fileURL: URL
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct PostScanView: View {
    @EnvironmentObject var globalState: GlobalState
    
    @ObservedObject private var exportViewModel = ExportViewModel()
    @ObservedObject var logManager = LogManager.shared
    
    @State private var triggerUpdate: Bool = false
    @State private var showCompletionCheckmark = false
    @State private var showAlert = false
    @State private var isInteractionDisabled = false
    @State private var showTimeoutAlert = false
    @State private var resetSceneKitView: Bool = false
    @State private var tstate: UnsafeMutableRawPointer?
    
    @State private var selectedNodeIndex: Int?
    @State private var position = SCNVector3(0, 0, 0)
    @State private var rotation = SCNVector3(0, 0, 0)
    @State private var nodeCount = ExternalData.pointCloudGeometries.suffix(3).count
    
    @State private var uploadProgress: Double = 0.0
    @State private var isLoading: Bool = false
    
    @State private var scnNode: SCNNode?
    
    @State private var fileURLToShare: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var showDropdown: Bool = false
    
    @State private var isProcessing = false {
        didSet {
            // Prevent the device from sleeping when processing starts, and allow it to sleep again when processing ends
            UIApplication.shared.isIdleTimerDisabled = isProcessing
        }
    }
    
    let fileManager = FileManager.default
    
    func initialize() {
        isProcessing = true
        
        // Construct the paths for the calibration, image, and depth files
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy_MM_dd"
        let dateString = dateFormatter.string(from: Date())
        
        let baseFolder = ExternalData.getFaceScansFolder().path // Assuming ExternalData.getFaceScansFolder() gives the base directory for the files
        
        let calibrationFilePath = "\(baseFolder)/calibration.json"
        
        // Read the content of the JSON file
        var calibrationFileContent = ""
        do {
            calibrationFileContent = try String(contentsOfFile: calibrationFilePath, encoding: .utf8)
        } catch {
            print("Failed to read calibration file: \(error)")
        }
        
        let videoZipPath = "\(baseFolder)/videos.zip"
        let depthZipPath = "\(baseFolder)/depths.zip"
        
        let videoFiles = fileManager.getFilePathsWithPrefix(baseFolder: baseFolder, prefix: "video")
        let depthFiles = fileManager.getFilePathsWithPrefix(baseFolder: baseFolder, prefix: "depth")
        
        SSZipArchive.createZipFile(atPath: videoZipPath, withFilesAtPaths: videoFiles)
        SSZipArchive.createZipFile(atPath: depthZipPath, withFilesAtPaths: depthFiles)
    
        let outputFilePath = URL(fileURLWithPath: baseFolder).appendingPathComponent("output.obj")
        
        // Delete if already exists...
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputFilePath.path) {
            try? fileManager.removeItem(at: outputFilePath)
        }

      // ON-DEVICE MESHING... (CURRENTLY FACING ISSUES REGARDING BASE64 UIIMAGE TRANSFER BETWEEN PYTHON AND SWIFT! NEEDS FIX!
        DispatchQueue.global(qos: .userInitiated).async {
            let gstate = PyGILState_Ensure()
            
          defer {
              DispatchQueue.main.async {
                  guard let tstate = self.tstate else { fatalError() }
                  PyEval_RestoreThread(tstate)
                  self.tstate = nil
              }
              
              PyGILState_Release(gstate)
          }
            var pointClouds: [PythonObject] = []
    
            for (index, videoFile) in videoFiles.enumerated() {
                do {
                    let objFileURL = try OpticALLYApp.poissonReconstruction_PLYtoOBJ(json_string: calibrationFileContent, image_file: videoFile, depth_file: depthFiles[index])
                    
                    pointClouds.append(objFileURL)
                    
                } catch {
                    print(error.localizedDescription)
                }
            }
            
            let process3D = Python.import("Process3D")
            let meshOutput = process3D.process3D(pointClouds)
            
            o3d!.io.write_triangle_mesh(outputFilePath.path, meshOutput)
           
            // Update the state to indicate that there's a file to share
            DispatchQueue.main.async {
                // self.fileURL = zipFileURL
                exportViewModel.fileURLForViewer = outputFilePath  // Store the file URL for sharing
                ExternalData.isMeshView = true
                self.isProcessing = false
            }
        }
        
        tstate = PyEval_SaveThread()
        
        // Using cloud services... (server)
//        uploadFiles(calibrationFileURL: URL(fileURLWithPath: calibrationFilePath), imageFilesZipURL: URL(fileURLWithPath: videoZipPath), depthFilesZipURL: URL(fileURLWithPath: depthZipPath)) { success, objURLs in
//            if success, let objURLs = objURLs {
//                DispatchQueue.main.async {
//                    exportViewModel.objURLs = objURLs
//                    ExternalData.isMeshView = true
//                    self.isProcessing = false
//                }
//                
//            } else {
//                // Handle errors
//                DispatchQueue.main.async {
//                    self.showAlert = true
//                }
//            }
//        }
    }
    
    func reset() {
        position = SCNVector3(0, 0, 0)
        rotation = SCNVector3(0, 0, 0)
        
        selectedNodeIndex = nil
    }
    
    func createZipArchive(from folderURL: URL, to zipFileURL: URL) {
        SSZipArchive.createZipFile(atPath: zipFileURL.path, withContentsOfDirectory: folderURL.path)
    }
    
    func shareExportedData() {
        let folderURL = ExternalData.getFaceScansFolder() // The folder containing your JSON and bins
        let zipFileURL = folderURL.appendingPathComponent("exportedData.zip") // Destination zip file
        
        // Create the zip archive
        createZipArchive(from: folderURL, to: zipFileURL)
        
        // Find the current window scene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        guard let rootViewController = windowScene.windows.first?.rootViewController else { return }
        
        // Present the share sheet with the zip file
        let activityViewController = UIActivityViewController(activityItems: [zipFileURL], applicationActivities: nil)
        
        // For iPads, configure the presentation controller
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceView = rootViewController.view
            popoverController.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        rootViewController.present(activityViewController, animated: true, completion: nil)
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
    
    func uploadFiles(calibrationFileURL: URL, imageFilesZipURL: URL, depthFilesZipURL: URL, completion: @escaping (Bool, [URL]?) -> Void) {
        let endpoint = "https://harolden-server.apps.johnseong.com/process3d-to-multiple-obj/"
        guard let url = URL(string: endpoint) else {
            print("Invalid URL")
            completion(false, [])
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
                    let tempDir = FileManager.default.temporaryDirectory
                    let zipFileURL = tempDir.appendingPathComponent("output_objs.zip")
                    
                    do {
                        try data.write(to: zipFileURL)
                        var objURLs: [URL] = []
                        let fileManager = FileManager.default
                        let unzipDirectory = tempDir.appendingPathComponent("unzipped_objs", isDirectory: true)
                        try fileManager.createDirectory(at: unzipDirectory, withIntermediateDirectories: true, attributes: nil)
                        SSZipArchive.unzipFile(atPath: zipFileURL.path, toDestination: unzipDirectory.path)
                        
                        let objFiles = try fileManager.contentsOfDirectory(at: unzipDirectory, includingPropertiesForKeys: nil)
                        objURLs = objFiles.filter { $0.pathExtension == "obj" }
                        
                        completion(true, objURLs)  // Pass the array of URLs to the completion handler
                    } catch {
                        print("Failed to handle ZIP file: \(error.localizedDescription)")
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
                        // Only allow action if processing is not happening
                        if !isProcessing {
                            ExternalData.reset() {
                                exportViewModel.reset() {
                                    reset()  // Reset position and rotation to default values
                                    resetSceneKitView = true
                                    logManager.clearLogs()
                                    globalState.currentView = .scanning
                                }
                            }
                        }
                    }) {
                        Image(systemName: "arrow.left") // Customize with your own back button image
                            .foregroundStyle(.white)
                            .font(.title)
                            .padding()
                    }
                    .disabled(isProcessing)  // Disable the button when processing

                    Text("Your Scan")
                        .font(.system(.title))  // Using monospaced font
                    Spacer()
                }
                .padding(.top)
                .onAppear() {
                    // onViewAppear...
                    self.initialize()
                    
                    print("안녕")
                }

                TabView {
                    ForEach(exportViewModel.objURLs, id: \.self) { url in
                        SceneKitMDLView(url: url)
                            .tabItem {
                                Label("Model \(exportViewModel.objURLs.firstIndex(of: url)! + 1)", systemImage: "\(exportViewModel.objURLs.firstIndex(of: url)! + 1).circle")
                            }
                    }
                }
                
                Spacer()
                
                if ExternalData.isMeshView {
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
                        .padding(.top)
                        
                        // Dropdown list view
                        if showDropdown {
                            VStack {
                                Button(action: {
                                    self.showShareSheet = true  // Trigger the share sheet to open
                                }) {
                                    Text("FULL HEAD .OBJ")
                                        .font(.caption)
                                        .bold()
                                        .padding()
                                        .foregroundColor(.white)
                                        .background(Capsule().fill(Color(.black)))
                                }
                                .padding(.top)
                                .padding(.horizontal)
                                
                                Button(action: {
                                    exportViewModel.exportFaceNodes(showShareSheet: true)
                                }) {
                                    Text("LANDMARK 3DMM")
                                        .font(.caption)
                                        .bold()
                                        .padding()
                                        .foregroundColor(.white)
                                        .background(Capsule().fill(Color(.black)))
                                }
                                .padding(.horizontal)
                                
                                Text("FOR DEVELOPERS")
                                    .bold()
                                    .monospaced()
                                    .font(.caption)
                                    .padding(.top)
                                    .padding(.horizontal)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.black)
                                
                                Button(action: {
                                    shareExportedData()
                                }) {
                                    Text("RGB-D\n.BIN\n\nCALIBRATION\n.JSON")
                                        .font(.caption)
                                        .bold()
                                        .padding()
                                        .foregroundColor(.white)
                                        .fixedSize(horizontal: false, vertical: true) // Allow height to adjust based on content
                                        .background(Capsule().fill(Color.black))
                                }
                                .padding() // Adjust padding as needed
                            }
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 20)) // Clips the image as a rounded rectangle
                            .padding(.top, 5)
                            .sheet(isPresented: $exportViewModel.showShareSheet, onDismiss: {
                                exportViewModel.showShareSheet = false
                            }) {
                                // This will present the share sheet
                                if let fileURL = exportViewModel.fileURL {
                                    ShareSheet(fileURL: fileURL)
                                }
                            }
                        }
                    }
                    if !exportViewModel.isLoading {
                        Text("PUPIL DISTANCE\n\(String(format: "%.1f", cameraViewController.pupilDistance)) mm")
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                            .monospaced()
                    }
                }
                
                if isLoading {
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
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30) // Adjust horizontal padding for wider background
                    .padding(.vertical, 15) // Adjust vertical padding for background height
                    .zIndex(1) // Ensure the spinner and text are above other content
                    
                    Spacer()
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
            .sheet(isPresented: $showShareSheet, onDismiss: {
                showShareSheet = false
            }) {
                // This will present the share sheet
                
                if let fileURL = fileURLToShare {
                    ShareSheet(fileURL: fileURL)
                        .onAppear() {
                            print("Shared: \(fileURL)")
                        }
                }
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
