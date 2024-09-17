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
    
    @Binding var uniqueId: UUID
    @Binding var triggerReinit: Bool
    
    @ObservedObject private var exportViewModel = ExportViewModel()
    @ObservedObject var logManager = LogManager.shared
    
    @State private var currentDirection: ScanDirection = .left
    
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
    
    @State private var centroidsFirst: [SCNVector3] = []
    @State private var centroidsNodeFirst: SCNNode? = nil
    
        @State private var centroids: [SCNVector3] = []
        @State private var centroidsNode: SCNNode? = nil
    
    // Retrieve all the output OBJ files
    @State private var objFiles: [String] = []
    
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
        
        // Sort renamed video files by their new names
        videoFiles = videoFiles.sorted()

        print("Renamed Video Files: \(videoFiles)")
        print("Swift-side Depth Files Count: \(depthFiles.count)")
        
        // Take the smaller count to ensure arrays have matching lengths
        let minCount = min(videoFiles.count, depthFiles.count)
        
        // Trim both arrays to the minimum count
        videoFiles = Array(videoFiles.prefix(minCount))
        depthFiles = Array(depthFiles.prefix(minCount))
        
        print("Trimmed Video Files Count: \(videoFiles.count)")
        print("Trimmed Depth Files Count: \(depthFiles.count)")

        // Generate output paths for the OBJ files
        var outputPaths: [String] = []
        for index in 0..<minCount {
            let objFileName = "output_\(index).obj"
            let objPath = folderURL.appendingPathComponent(objFileName).path
            outputPaths.append(objPath)
        }
        
        // Prepare the arrays of CGPoint for each facial landmark
        let noseTipArray = ExternalData.pointCloudDataArray.map { NSValue(cgPoint: $0.noseTip) }
        let chinArray = ExternalData.pointCloudDataArray.map { NSValue(cgPoint: $0.chin) }
        let leftEyeLeftCornerArray = ExternalData.pointCloudDataArray.map { NSValue(cgPoint: $0.leftEyeLeftCorner) }
        let rightEyeRightCornerArray = ExternalData.pointCloudDataArray.map { NSValue(cgPoint: $0.rightEyeRightCorner) }
        let leftMouthCornerArray = ExternalData.pointCloudDataArray.map { NSValue(cgPoint: $0.leftMouthCorner) }
        let rightMouthCornerArray = ExternalData.pointCloudDataArray.map { NSValue(cgPoint: $0.rightMouthCorner) }

        // Process point clouds for the matching pairs
        PointCloudProcessingBridge.processPointClouds(
            withCalibrationFile: calibrationFileURL.path,
            imageFiles: videoFiles,
            depthFiles: depthFiles,
            outputPaths: outputPaths,
            noseTip: noseTipArray,
            chinArray: chinArray,
            leftEyeLeftCornerArray: leftEyeLeftCornerArray,
            rightEyeRightCornerArray: rightEyeRightCornerArray,
            leftMouthCornerArray: leftMouthCornerArray,
            rightMouthCornerArray: rightMouthCornerArray
        )


        for path in outputPaths {
            let objURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: objURL.path) {
                objFiles.append(objURL.path)
                print("objURL Path: \(objURL.path)")
            } else {
                NSLog("Failed to generate OBJ file for path: \(path) (Swift-side error catch)")
            }
        }
        
        if objFiles.isEmpty {
            self.showAlert = true
            self.isProcessing = false
            return
        }
        
        // Store the OBJ URLs in the export view model
        exportViewModel.objURLs = objFiles.map { $0 }
        
        self.isProcessing = false
        ExternalData.isMeshView = true  // Processing is complete, allow viewing of the mesh
        
        loadCentroids()
        loadCentroidsFirst()
    }
    
    func loadCentroidsFirst() {
          if let centroidValues = PointCloudProcessingBridge.getCentroids2DArray(at: 0) {
              print("Number of centroids retrieved: \(centroidValues.count)")
              centroidsFirst = centroidValues.map { $0.scnVector3Value }
              for (index, centroid) in centroidsFirst.enumerated() {
                  print("Centroid \(index): x = \(centroid.x), y = \(centroid.y), z = \(centroid.z)")
              }
              
              // Create node from centroids and store it in centroidsNode
              centroidsNodeFirst = createNodeFromCentroidsFirst()
          } else {
              print("Failed to retrieve centroids at index 1.")
          }
      }
    
    func loadCentroids() {
          if let centroidValues = PointCloudProcessingBridge.getCentroids2DArray(at: 1) {
              print("Number of centroids retrieved: \(centroidValues.count)")
              centroids = centroidValues.map { $0.scnVector3Value }
              for (index, centroid) in centroids.enumerated() {
                  print("Centroid \(index): x = \(centroid.x), y = \(centroid.y), z = \(centroid.z)")
              }
              
              // Create node from centroids and store it in centroidsNode
              centroidsNode = createNodeFromCentroids()
          } else {
              print("Failed to retrieve centroids at index 1.")
          }
      }
       
    
 func createNodeFromCentroidsFirst() -> SCNNode? {
     guard !centroids.isEmpty else { return nil }
     
     let node = SCNNode()
     let sphereGeometry = SCNSphere(radius: 0.005) // Small sphere to represent each centroid
     
     // Create a material with an orange color
     let orangeMaterial = SCNMaterial()
     orangeMaterial.diffuse.contents = UIColor.green
     
     // Apply the material to the sphere geometry
     sphereGeometry.materials = [orangeMaterial]
     
     for centroid in centroidsFirst {
         let centroidNode = SCNNode(geometry: sphereGeometry)
         centroidNode.position = centroid
         node.addChildNode(centroidNode)
     }
     
     return node
 }
    
    func createNodeFromCentroids() -> SCNNode? {
        guard !centroids.isEmpty else { return nil }
        
        let node = SCNNode()
        let sphereGeometry = SCNSphere(radius: 0.005) // Small sphere to represent each centroid
        
        // Create a material with an orange color
        let orangeMaterial = SCNMaterial()
        orangeMaterial.diffuse.contents = UIColor.orange
        
        // Apply the material to the sphere geometry
        sphereGeometry.materials = [orangeMaterial]
        
        for centroid in centroids {
            let centroidNode = SCNNode(geometry: sphereGeometry)
            centroidNode.position = centroid
            node.addChildNode(centroidNode)
        }
        
        return node
    }
    
    func initialize() {
        isProcessing = true
        uploadIndex = 0
        processUploads()
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
    
    private var currentDirectionString: String {
        switch currentDirection {
        case .left:
            return "LEFT"
            
        case .right:
            return "RIGHT"
        }
    }
    
    private var currentDirectionIndex: Int {
        switch currentDirection {
        case .left:
            return 0
            
        case .right:
            return 1
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
//                    Button(action: {
//                        // Only allow action if processing is not happening
//                        if !isProcessing {
//                            ExternalData.resetCompletely() {
//                                exportViewModel.reset() {
//                                    reset()  // Reset position and rotation to default values
//                                    resetSceneKitView = true
//                                    logManager.clearLogs()
//                                    
//                                    // Refresh CameraViewController
//                                    uniqueId = UUID()
//                                    triggerReinit.toggle()
//                                    
//                                    globalState.currentView = .scanning
//                                    
//                                    // VERY IMPORTANT! CURRENTLY THERE'S A BUG WHERE UNLESS YOU COMPLETELY QUIT THE APP AND RESTART, THE POINT CLOUD ALIGNMENT PROCESS WILL BE MESSED UP WHEN YOU RE-RUN IT AGAIN AFTER CLICKING THE BACK BUTTON! BUG FIX NEEDED!
//                                }
//                            }
//                        }
//                    }) {
//                        Image(systemName: "arrow.left") // Customize with your own back button image
//                            .foregroundStyle(.white)
//                            .font(.title)
//                            .padding()
//                    }
//                    .disabled(isProcessing)  // Disable the button when processing

                    Text("YOUR SCAN")
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
                }

                if let urls = exportViewModel.objURLs {
                    SceneKitMDLView(snapshot: $snapshot, url: URL(string: urls[0])!, nodeFirst: centroidsNodeFirst, node: centroidsNode)
                                       .padding()
                               }
                
                Spacer()
                
                if ExternalData.isMeshView {
                    if !exportViewModel.isLoading {
                        VStack {
                            Text("Pupil Distance\n\(String(format: "%.1f", cameraViewController.pupilDistance)) mm")
                                .padding()
                                .font(.system(size: 24.0, weight: .bold, design: .rounded))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    VStack {
                        Button(action: {
                            // Toggle the dropdown
                            showDropdown.toggle()
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("EXPORT")
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
                                    if let urls = exportViewModel.objURLs {
                                        self.fileURLToShare = URL(fileURLWithPath: urls[0])
                                        self.showShareSheet = true
                                    }
                                }) {
                                    Text("FULL HEAD .OBJ")
                                        .font(.caption)
                                        .bold()
                                        .padding()
                                        .foregroundColor(.white)
                                        .background(Capsule().fill(Color(.black)))
                                }
                                .padding()
                            }
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 20)) // Clips the image as a rounded rectangle
                            .padding(.top, 5)
                          
                        }
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
            .sheet(isPresented: $showShareSheet, onDismiss: {
                showShareSheet = false
            }) {
                if let fileURL = fileURLToShare {
                    ShareSheet(fileURL: fileURL)
                        .onAppear() {
                            print("Shared: \(fileURL.path)")
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
