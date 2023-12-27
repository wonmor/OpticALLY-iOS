//
//  CameraViewController.swift
//  OpticALLY
//
//  Created by John Seong on 9/10/23.
//

import SwiftUI
import UIKit
import ARKit
import AVFoundation
import Vision

/// CameraViewController manages the camera and AR functionalities within the OpticALLY app.
/// It utilizes ARKit for face tracking and AVFoundation for depth data processing.
/// This controller is responsible for synchronizing and processing depth data
/// and video frames from the device's camera.
///
/// - Properties:
///   - viewModel: ViewModel for managing face tracking data.
///   - sharedViewModel: Shared ViewModel for observing and triggering UI changes.
///   - session: ARSession for AR functionalities.
///   - avCaptureSession: AVCaptureSession for capturing video and depth data.
///   - outputSynchronizer: Synchronizes video and depth data outputs.
///   - videoDataOutput: Output for video data from camera.
///   - depthDataOutput: Output for depth data from camera.
///   - cancellables: Set of AnyCancellable for managing Combine subscriptions.
///   - sessionQueue: DispatchQueue for handling ARSession-related tasks.
///   - dataOutputQueue: DispatchQueue for handling data output tasks.
///   - isUsingARSession: Flag to switch between ARSession and AVCaptureSession.
///   - synchronizedDepthData: Holds synchronized depth data.
///   - synchronizedVideoPixelBuffer: Holds synchronized video pixel buffer.
///   - faceDetectionRequest: Vision request for detecting facial landmarks.
///   - faceDetectionHandler: Handler for processing face detection requests.
///   - leftEyePosition, rightEyePosition, chin: SCNVector3 positions for facial features.
///
/// - Methods:
///   - loadInit(): Initializes the controller with necessary setups.
///   - setupViewModelObserver(): Sets up observers for shared view model properties.
///   - configureCloudView(), configureGestureRecognizers(), configureARSession(),
///     configureAVCaptureSession(): Configuration methods for UI and sessions.
///   - switchSession(toARSession:): Switches between ARSession and AVCaptureSession.
///   - startARSession(), pauseARSession(), startAVCaptureSession(), pauseAVCaptureSession():
///     Methods to start and pause AR and AV sessions.
///   - dataOutputSynchronizer(didOutput:): Processes synchronized video and depth data.
///
/// This controller is central to the 3D face tracking and point cloud generation capabilities of the app.
/// It integrates ARKit and AVFoundation frameworks for advanced data processing and rendering.

class CameraViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate, AVCaptureDataOutputSynchronizerDelegate {
    // MARK: - Class Parameters
    var viewModel: FaceTrackingViewModel?
    
    // MARK: - Properties
    private var session: ARSession = ARSession()
    private var avCaptureSession: AVCaptureSession = AVCaptureSession()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private var videoDataOutput = AVCaptureVideoDataOutput()
    private var depthDataOutput = AVCaptureDepthDataOutput()
    
    private var sessionQueue = DispatchQueue(label: "session queue")
    private var dataOutputQueue = DispatchQueue(label: "data output queue")
    
    private var isUsingARSession: Bool = true
    
    private var synchronizedDepthData: AVDepthData?
    private var synchronizedVideoPixelBuffer: CVPixelBuffer?
    
    private let faceDetectionRequest = VNDetectFaceLandmarksRequest()
    private let faceDetectionHandler = VNSequenceRequestHandler()
    
    private var leftEyePosition = CGPoint(x: 0, y: 0)
    private var rightEyePosition = CGPoint(x: 0, y: 0)
    private var chinPosition = CGPoint(x: 0, y: 0)
    
    // MARK: - New Properties for 3D facial feature tracking
    private var leftEyePosition3D: SCNVector3?
    private var rightEyePosition3D: SCNVector3?
    private var chinPosition3D: SCNVector3?
    
    // MARK: - UI Bindings
    @IBOutlet weak private var cameraUnavailableLabel: UILabel!
    @IBOutlet weak private var depthSmoothingSwitch: UISwitch!
    @IBOutlet weak private var mixFactorSlider: UISlider!
    @IBOutlet weak private var touchDepth: UILabel!
    @IBOutlet weak private var smoothDepthLabel: UILabel!
    
    @IBOutlet weak private var cloudView: PointCloudMetalView!
    
    private func resizePixelBuffer(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> CVPixelBuffer? {
        // Use kCVPixelFormatType_32BGRA for BGRA format (equivalent to MTLPixelFormatBGRA8Unorm)
        let pixelFormatType = kCVPixelFormatType_32BGRA
        var newPixelBuffer: CVPixelBuffer?
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         pixelFormatType,
                                         nil,
                                         &newPixelBuffer)
        
        guard status == kCVReturnSuccess, let resizedPixelBuffer = newPixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(resizedPixelBuffer, [])
        
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(resizedPixelBuffer, [])
        }
        
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(resizedPixelBuffer),
                                   width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(resizedPixelBuffer),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   // Update bitmapInfo for BGRA format
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
           let quartzImage = CIContext().createCGImage(CIImage(cvPixelBuffer: pixelBuffer), from: CIImage(cvPixelBuffer: pixelBuffer).extent) {
            
            context.draw(quartzImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        
        return resizedPixelBuffer
    }
    
    private func processFrameAV(depthData: AVDepthData, imageData: CVImageBuffer) {
        let depthPixelBuffer = depthData.depthDataMap
        
        let depthWidth = CVPixelBufferGetWidth(depthPixelBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthPixelBuffer)
        
        let colorPixelBuffer = resizePixelBuffer(imageData, width: depthWidth, height: depthHeight)
        
        CVPixelBufferLockBaseAddress(depthPixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(colorPixelBuffer!, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthPixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(colorPixelBuffer!, .readOnly)
        }
        
        let colorWidth = CVPixelBufferGetWidth(colorPixelBuffer!)
        let colorHeight = CVPixelBufferGetHeight(colorPixelBuffer!)
        
        print("Image Width: \(colorWidth) | Image Height: \(colorHeight)")
        print("Depth Data Width: \(depthWidth) | Depth Data Height: \(depthHeight)")
        
        let colorBytesPerRow = CVPixelBufferGetBytesPerRow(colorPixelBuffer!)
        
        let depthPixelFormatType = CVPixelBufferGetPixelFormatType(depthPixelBuffer)
        var depthBytesPerPixel: Int = 0 // Initialize with zero
        
        switch depthPixelFormatType {
        case kCVPixelFormatType_DepthFloat32:
            depthBytesPerPixel = 4
        case kCVPixelFormatType_DepthFloat16:
            depthBytesPerPixel = 2
            // Add more cases as necessary for different formats
        default:
            print("Unsupported depth pixel format type")
            return
        }
        
        // Ensure that you're iterating within the bounds of both buffers
        let commonWidth = min(colorWidth, depthWidth)
        let commonHeight = min(colorHeight, depthHeight)
        
        // Assuming colorData is the base address for the BGRA image buffer
        let colorBaseAddress = CVPixelBufferGetBaseAddress(colorPixelBuffer!)!.assumingMemoryBound(to: UInt8.self)
        
        // Call the point cloud creation function
        ExternalData.createAVPointCloudGeometry(
            depthData: depthData,
            colorData: colorBaseAddress,
            width: commonWidth,
            height: commonHeight,
            bytesPerRow: colorBytesPerRow // Use the correct bytes per row for color data
        )
    }
    
    // MARK: - Detect Face Landmarks and Convert to 3D Coordinates
    private func detectFaceLandmarks(in pixelBuffer: CVPixelBuffer, frame: ARFrame) {
        try? faceDetectionHandler.perform([faceDetectionRequest], on: pixelBuffer, orientation: .right)
        guard let observations = faceDetectionRequest.results as? [VNFaceObservation] else {
            return
        }
        
        for observation in observations {
            updateFeaturePositions(for: observation, in: frame)
        }
    }
    
    private func performRaycastTest(in frame: ARFrame) {
        // Example points - you can choose other points or generate them randomly
        let testPoints: [CGPoint] = [
            CGPoint(x: 0.25, y: 0.25), // Top-left quarter
            CGPoint(x: 0.75, y: 0.25), // Top-right quarter
            CGPoint(x: 0.50, y: 0.50), // Center
            CGPoint(x: 0.25, y: 0.75), // Bottom-left quarter
            CGPoint(x: 0.75, y: 0.75)  // Bottom-right quarter
        ]

        for testPoint in testPoints {
            if let raycastQuery: ARRaycastQuery? = frame.raycastQuery(from: testPoint, allowing: .estimatedPlane, alignment: .any),
               let raycastResult = session.raycast(raycastQuery!).first {
                let position = SCNVector3(raycastResult.worldTransform.columns.3.x, raycastResult.worldTransform.columns.3.y, raycastResult.worldTransform.columns.3.z)
                print("Raycast at \(testPoint): \(position)")
            } else {
                print("Raycast failed at \(testPoint)")
            }
        }
    }
    
    private func randomPointInViewBounds(viewSize: CGSize) -> CGPoint {
        let randomX = CGFloat.random(in: 0..<viewSize.width)
        let randomY = CGFloat.random(in: 0..<viewSize.height)
        return CGPoint(x: randomX, y: randomY)
    }

    private func performRandomRaycastTest(in frame: ARFrame, viewSize: CGSize, numberOfTests: Int = 10) {
        for _ in 1...numberOfTests {
            let randomPoint = randomPointInViewBounds(viewSize: viewSize)
            if let raycastQuery: ARRaycastQuery? = frame.raycastQuery(from: randomPoint, allowing: .estimatedPlane, alignment: .any),
               let raycastResult = session.raycast(raycastQuery!).first {
                let position = SCNVector3(raycastResult.worldTransform.columns.3.x, raycastResult.worldTransform.columns.3.y, raycastResult.worldTransform.columns.3.z)
                print("Raycast at \(randomPoint): \(position)")
            } else {
                print("Raycast failed at \(randomPoint)")
            }
        }
    }
    
    // New Method: Update feature positions
    private func updateFeaturePositions(for observation: VNFaceObservation, in frame: ARFrame) {
        if let leftEye = observation.landmarks?.leftEye {
            let leftEyePoints = leftEye.normalizedPoints
            update3DPosition(for: leftEyePoints, in: observation, frame: frame) { position in
                self.leftEyePosition3D = position
                print("leftEyePosition3D: \(position)")
            }
        }
        
        if let rightEye = observation.landmarks?.rightEye {
            let rightEyePoints = rightEye.normalizedPoints
            update3DPosition(for: rightEyePoints, in: observation, frame: frame) { position in
                self.rightEyePosition3D = position
            }
        }
        
        if let faceContour = observation.landmarks?.faceContour, let lowestPoint = faceContour.normalizedPoints.min(by: { $0.y < $1.y }) {
            update3DPosition(for: [lowestPoint], in: observation, frame: frame) { position in
                self.chinPosition3D = position
            }
        }
    }
    
    // New Method: Convert 2D points to 3D using ARKit Raycasting
    private func update3DPosition(for points: [CGPoint], in observation: VNFaceObservation, frame: ARFrame, completion: @escaping (SCNVector3?) -> Void) {
        let averagePoint = averagePoint(from: points, in: observation.boundingBox, pixelBuffer: frame.capturedImage)
        guard let raycastQuery: ARRaycastQuery? = frame.raycastQuery(from: averagePoint, allowing: .estimatedPlane, alignment: .any),
              let raycastResult = session.raycast(raycastQuery!).first else {
            completion(nil)
            return
        }
        
        let position = SCNVector3(raycastResult.worldTransform.columns.3.x, raycastResult.worldTransform.columns.3.y, raycastResult.worldTransform.columns.3.z)
        completion(position)
    }
    
    private func averagePoint(from normalizedPoints: [CGPoint], in boundingBox: CGRect, pixelBuffer: CVPixelBuffer) -> CGPoint {
        // Calculate the average point in normalized Vision coordinates
        let viewSize = UIScreen.main.bounds.size
        
        print("viewSize: \(viewSize)")
        
        let sum = normalizedPoints.reduce(CGPoint.zero, { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) })
        let count = CGFloat(normalizedPoints.count)
        let averageNormalized = CGPoint(x: sum.x / count, y: sum.y / count)
        
        // Convert normalized point to UIKit coordinates
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let originX = boundingBox.origin.x * width
        let originY = boundingBox.origin.y * height
        
        let averageUIKit = CGPoint(x: averageNormalized.x * boundingBox.width * width + originX,
                                   y: averageNormalized.y * boundingBox.height * height + originY)
        
        // Transform to the coordinate system of the view (screen in this case)
        // Vision's Y-coordinate is flipped compared to UIKit's
        let transformedY = height - averageUIKit.y
        
        // Scale the point from the pixel buffer size to the view size
        let scaleX = viewSize.width / width
        let scaleY = viewSize.height / height
        let finalPoint = CGPoint(x: averageUIKit.x * scaleX, y: transformedY * scaleY)
        
        print("finalPoint: \(finalPoint)")
        
        return finalPoint
    }
    
    func loadInit() {
        session.delegate = self
        configureGestureRecognizers()
        configureARSession()
        configureAVCaptureSession()
        switchSession(toARSession: true)
        configureCloudView()
        addAndConfigureSwiftUIView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadInit()
    }
    
    private func configureCloudView() {
        cloudView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cloudView)
        NSLayoutConstraint.activate([
            cloudView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cloudView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cloudView.topAnchor.constraint(equalTo: view.topAnchor),
            cloudView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func addAndConfigureSwiftUIView() {
        let hostingController = UIHostingController(rootView: ExportView(faceTrackingViewModel: faceTrackingViewModel))
        addChild(hostingController)
        hostingController.didMove(toParent: self)
        
        let swiftUIView = hostingController.view!
        swiftUIView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(swiftUIView)
        
        let maxWidth = view.bounds.width * 0.8 // 80% of parent view's width
        let maxHeight = view.bounds.height * 0.8 // 80% of parent view's height
        
        NSLayoutConstraint.activate([
            swiftUIView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            swiftUIView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            swiftUIView.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            swiftUIView.heightAnchor.constraint(lessThanOrEqualToConstant: maxHeight)
        ])
    }
    
    // MARK: - ARSessionDelegate Methods
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if ExternalData.isSavingFileAsPLY && isUsingARSession {
            switchSession(toARSession: false)
        }
        // Store frame data for processing
        do {
            let imageSampler = try CapturedImageSampler(arSession: session, viewController: self)
            
            guard let faceAnchor = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
            
            DispatchQueue.main.async { [self] in
                self.synchronizedDepthData = frame.capturedDepthData
                self.synchronizedVideoPixelBuffer = frame.capturedImage
                
                self.viewModel!.faceAnchor = faceAnchor
                
                // Extract the Euler angles from the faceAnchor's transform
                let transform = faceAnchor.transform
                let pitchRadians = atan2(transform.columns.1.z, transform.columns.1.y)
                let yawRadians = atan2(transform.columns.0.z, sqrt(pow(transform.columns.1.z, 2) + pow(transform.columns.1.y, 2)))
                let rollRadians = atan2(-transform.columns.2.x, transform.columns.2.z)
                
                // Convert radians to degrees
                let pitchDegrees = pitchRadians * 180 / .pi
                let yawDegrees = yawRadians * 180 / .pi
                let rollDegrees = rollRadians * 180 / .pi
                
                viewModel!.faceYawAngle = Double(yawDegrees)
                viewModel!.facePitchAngle = Double(pitchDegrees)
                viewModel!.faceRollAngle = Double(rollDegrees)
                
                if self.synchronizedVideoPixelBuffer != nil {
                    // Perform processing if both depth and video data are available
                    if let depthData = self.synchronizedDepthData,
                       let videoPixelBuffer = self.synchronizedVideoPixelBuffer {
                        self.detectFaceLandmarks(in: videoPixelBuffer, frame: frame)
                        // cloudView.setDepthFrame(depthData, withTexture: videoPixelBuffer)
                        let viewSize = self.view.bounds.size
                        performRandomRaycastTest(in: frame, viewSize: viewSize)
                    }
                }
            }
        } catch {
            print("Error creating CapturedImageSampler: \(error)")
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        DispatchQueue.main.async {
            self.viewModel!.faceAnchor = faceAnchor
        }
    }
    
    private func configureGestureRecognizers() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        view.addGestureRecognizer(tapGesture)
    }
    
    private func configureARSession() {
        // Setup ARSession configuration
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        // Additional ARSession configuration
    }
    
    private func configureAVCaptureSession() {
        // Setup AVCaptureSession but don't start it yet
        guard let videoDevice = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) else {
            print("TrueDepth camera is not available.")
            return
        }
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            if avCaptureSession.canAddInput(videoDeviceInput) {
                avCaptureSession.addInput(videoDeviceInput)
            }
            
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            if avCaptureSession.canAddOutput(videoDataOutput) {
                avCaptureSession.addOutput(videoDataOutput)
            }
            
            if avCaptureSession.canAddOutput(depthDataOutput) {
                avCaptureSession.addOutput(depthDataOutput)
            }
            
            // Additional AVCaptureSession configuration
        } catch {
            print("Error configuring AVCaptureSession: \(error)")
        }
    }
    
    @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        // Handle tap gesture
    }
    
    // MARK: - ARSession and AVCaptureSession Management
    
    private func switchSession(toARSession useARSession: Bool) {
        if useARSession {
            pauseAVCaptureSession()
            startARSession()
        } else {
            pauseARSession()
            startAVCaptureSession()
        }
        isUsingARSession = useARSession
    }
    
    private func startARSession() {
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        print("ARSession Running")
    }
    
    private func pauseARSession() {
        session.pause()
        print("ARSession Paused")
    }
    
    private func startAVCaptureSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.avCaptureSession.startRunning()
        }
        
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
        outputSynchronizer?.setDelegate(self, queue: dataOutputQueue)
        print("AVCaptureSession Running")
    }
    
    private func pauseAVCaptureSession() {
        avCaptureSession.stopRunning()
        outputSynchronizer?.setDelegate(nil, queue: nil)
        print("AVCaptureSession Paused")
    }
    
    // MARK: - Video + Depth Frame Processing (AVCaptureSession)
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        // Read all outputs
        guard ExternalData.renderingEnabled,
              let syncedDepthData: AVCaptureSynchronizedDepthData =
                synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
              let syncedVideoData: AVCaptureSynchronizedSampleBufferData =
                synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else {
            // only work on synced pairs
            return
        }
        
        if syncedDepthData.depthDataWasDropped || syncedVideoData.sampleBufferWasDropped {
            return
        }
        
        let depthData = syncedDepthData.depthData
        let sampleBuffer = syncedVideoData.sampleBuffer
        guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        print("ExternalData.isSavingFileAsPLY: \(ExternalData.isSavingFileAsPLY)")
        
        processFrameAV(depthData: depthData, imageData: videoPixelBuffer)
        
        // Set cloudView to empty depth data and texture
        cloudView?.setDepthFrame(nil, withTexture: nil)
        cloudView?.setDepthFrame(depthData, withTexture: videoPixelBuffer)
        
        ExternalData.isSavingFileAsPLY = false
        
        if !ExternalData.isSavingFileAsPLY && !isUsingARSession {
            switchSession(toARSession: true)
        }
    }
}
