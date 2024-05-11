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
import UIKit
import Vision
import Combine

let debugMode = false

import CoreGraphics

struct PointWrapper: Hashable {
    let point: CGPoint

    func hash(into hasher: inout Hasher) {
        hasher.combine(point.x)
        hasher.combine(point.y)
    }

    static func ==(lhs: PointWrapper, rhs: PointWrapper) -> Bool {
        return lhs.point == rhs.point
    }
}


struct EyeOverlayView: View {
    var observations: [VNFaceObservation]

    var body: some View {
        GeometryReader { geometry in
            ForEach(observations, id: \.self) { observation in
                // Convert each CGPoint to PointWrapper before using it in ForEach
                ForEach(observation.landmarks?.allPoints?.pointsInImage(imageSize: geometry.size).map { PointWrapper(point: $0) } ?? [], id: \.self) { pointWrapper in
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .position(x: pointWrapper.point.x, y: pointWrapper.point.y)
                }
            }
        }
    }
}



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
    
    @State private var currentDirection: ScanDirection = .front
    
    @State private var frameNeedsUpdate = false
    @State private var scnView: SCNView?
    @State private var observations: [VNFaceObservation] = []
    
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

    @State private var isLoading: Bool = false
    
    @State private var scnNode: SCNNode?
    
    @State private var fileURLToShare: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var showDropdown: Bool = false
    
    @State private var snapshot: UIImage?
    
    @State private var uploadProgress = [Double](repeating: 0.0, count: 3)
    @State private var uploadResults = [Bool](repeating: false, count: 3)
    
    @State private var uploadIndex = 0  // Track the current index of uploads
    
    @State private var isProcessing = false {
        didSet {
            // Prevent the device from sleeping when processing starts, and allow it to sleep again when processing ends
            UIApplication.shared.isIdleTimerDisabled = isProcessing
        }
    }
    
    let fileManager = FileManager.default
    
    private func processUploads() {
        let baseFolderName = "bin_json"
        let documentsDirectory = ExternalData.getDocumentsDirectory()
        let folderURL = documentsDirectory.appendingPathComponent(baseFolderName)
        let calibrationFileURL = folderURL.appendingPathComponent("calibration.json")
        
        // Retrieve all video and depth files
        var videoFiles = fileManager.getFilePathsWithPrefix(baseFolder: folderURL.path, prefix: "video")
        var depthFiles = fileManager.getFilePathsWithPrefix(baseFolder: folderURL.path, prefix: "depth")
        
        print("Swift-side Video Files Count: \(videoFiles.count)")
        print("Swift-side Depth Files Count: \(depthFiles.count)")
        
        // Take the smaller count to ensure arrays have matching lengths
        let minCount = min(videoFiles.count, depthFiles.count)
        
        // Trim both arrays to the minimum count
        videoFiles = Array(videoFiles.prefix(minCount))
        depthFiles = Array(depthFiles.prefix(minCount))
        
        print("Trimmed Video Files Count: \(videoFiles.count)")
        print("Trimmed Depth Files Count: \(depthFiles.count)")

        // Process point clouds for the matching pairs
        PointCloudProcessingBridge.processPointClouds(withCalibrationFile: calibrationFileURL.path, imageFiles: videoFiles, depthFiles: depthFiles, outputPath: folderURL.path)

        let objFileName = "output.obj"
        let objURL = folderURL.appendingPathComponent(objFileName)
        
        if FileManager.default.fileExists(atPath: objURL.path) {
            print("objURL Path: \(objURL.path)")
            exportViewModel.objURL = objURL
            
        } else {
            NSLog("Failed to generate OBJ file (Swift-side error catch)")
            self.showAlert = true
            self.isProcessing = false
            return
        }
        
        self.isProcessing = false
        ExternalData.isMeshView = true  // Processing is complete, allow viewing of the mesh
    }
    
    func initialize() {
        isProcessing = true
        uploadIndex = 0
        processUploads()
    }

//      ON-DEVICE MESHING... (CURRENTLY FACING ISSUES REGARDING BASE64 UIIMAGE TRANSFER BETWEEN PYTHON AND SWIFT! NEEDS FIX!
//        DispatchQueue.global(qos: .userInitiated).async {
//            let gstate = PyGILState_Ensure()
//            
//          defer {
//              DispatchQueue.main.async {
//                  guard let tstate = self.tstate else { fatalError() }
//                  PyEval_RestoreThread(tstate)
//                  self.tstate = nil
//              }
//              
//              PyGILState_Release(gstate)
//          }
//            var pointClouds: [PythonObject] = []
//    
//            for (index, videoFile) in videoFiles.enumerated() {
//                do {
//                    let objFileURL = try OpticALLYApp.poissonReconstruction_PLYtoOBJ(json_string: calibrationFileContent, image_file: videoFile, depth_file: depthFiles[index])
//                    
//                    pointClouds.append(objFileURL)
//                    
//                } catch {
//                    print(error.localizedDescription)
//                }
//            }
//            
//            let process3D = Python.import("Process3D")
//            let meshOutput = process3D.process3D(pointClouds)
//            
//            o3d!.io.write_triangle_mesh(outputFilePath.path, meshOutput)
//           
//            // Update the state to indicate that there's a file to share
//            DispatchQueue.main.async {
//                // self.fileURL = zipFileURL
//                exportViewModel.fileURLForViewer = outputFilePath  // Store the file URL for sharing
//                ExternalData.isMeshView = true
//                self.isProcessing = false
//            }
//        }
//        
//        tstate = PyEval_SaveThread()
        
        // Using cloud services... (server)
//        uploadFiles(calibrationFileURL: URL(fileURLWithPath: calibrationFilePath), imageFilesZipURL: URL(fileURLWithPath: videoZipPath), depthFilesZipURL: URL(fileURLWithPath: depthZipPath)) { success, objURLs in
//            if success, let objURLs = objURLs {
//                DispatchQueue.main.async {
//                    exportViewModel.objURLs = objURLs
//                    
//                    print("objURLs: \(objURLs)")
//                    
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
//    }
    
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
    

    func detectEyes(in image: UIImage, completion: @escaping ([VNFaceObservation]?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        // Correct way to handle conversion of orientation
        let orientation = CGImagePropertyOrientation(rawValue: UInt32(image.imageOrientation.rawValue))!

        let request = VNDetectFaceLandmarksRequest { request, error in
            guard error == nil else {
                print("Face detection error: \(error!.localizedDescription)")
                completion(nil)
                return
            }

            completion(request.results as? [VNFaceObservation])
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
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
           let endpoint = "https://harolden-server.apps.johnseong.com/process3d-to-obj/"
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
                       let fileURL =  ExternalData.getDocumentsDirectory().appendingPathComponent("output_from_server.obj")
                       do {
                           exportViewModel.objURLs!.append(fileURL.path)
                           
                           try data.write(to: fileURL)
                           print("OBJ file saved to: \(fileURL.path)")
                           // self.fileURLToShare = fileURL --> VVIP
                           // self.triggerUpdate = true
                           // ExternalData.isMeshView = true
                           // self.isProcessing = false

                           print("objURLs: \(exportViewModel.objURLs!)")
                           
                           self.uploadIndex += 1
                           self.processUploads()  // Recursively process the next upload
                           
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
                   // self.uploadProgress = progress
               }
           }
           
           self.isLoading = true  // Start loading indicator
           task.resume()
       }
    
    private var currentDirectionString: String {
        switch currentDirection {
        case .left:
            return "LEFT"
        case .front:
            return "YOUR SCAN"
        case .right:
            return "RIGHT"
        }
    }
    
    func captureSnapshot(from scnView: SCNView) -> UIImage? {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scnView.scene
        renderer.pointOfView = scnView.pointOfView
        let image = renderer.snapshot(atTime: 0, with: scnView.bounds.size, antialiasingMode: .none)
        return image
    }
    
    private func currentScanIndex() -> Int {
           uploadResults.firstIndex(where: { !$0 }) ?? uploadResults.count
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

                    Text(currentDirectionString)
                        .monospaced()
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .cornerRadius(12)
                    
                    Spacer()
                }
                .padding(.top)
                .onAppear() {
                    // onViewAppear...
                    self.initialize()
                    
                    print("안녕")
                }
                
                if let url = exportViewModel.objURL {
                    SceneKitMDLView(snapshot: $snapshot, url: url)
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
                                
//                                Button(action: {
//                                    exportViewModel.exportFaceNodes(showShareSheet: true)
//                                }) {
//                                    Text("LANDMARK 3DMM")
//                                        .font(.caption)
//                                        .bold()
//                                        .padding()
//                                        .foregroundColor(.white)
//                                        .background(Capsule().fill(Color(.black)))
//                                }
//                                .padding(.horizontal)
                                
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
                
                // TO DO: ADD BACKGROUND PROCESSING - https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background/using_background_tasks_to_update_your_app
                if isLoading {
                    VStack(spacing: 10) { // Adjust spacing as needed
                        LottieView(animationFileName: "cargo-loading", loopMode: .loop)
                            .frame(width: 60, height: 60)
                            .scaleEffect(0.1)
                            .padding()
                            .colorInvert()
                        
                        Text("PROCESSING SCANS (\(uploadIndex + 1)/\(uploadResults.count))")
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
