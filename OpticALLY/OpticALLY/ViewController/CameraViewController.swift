import SwiftUI
import UIKit
import ARKit
import AVFoundation
import Vision

class CameraViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate, AVCaptureDataOutputSynchronizerDelegate {
    // MARK: - Properties
    private var session: ARSession = ARSession()
    private var avCaptureSession: AVCaptureSession = AVCaptureSession()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private var videoDataOutput = AVCaptureVideoDataOutput()
    private var depthDataOutput = AVCaptureDepthDataOutput()
    private var sessionQueue = DispatchQueue(label: "session queue")
    private var dataOutputQueue = DispatchQueue(label: "data output queue")
    private var isUsingARSession: Bool = true
    private var toggleButton: UIButton!
    
    var viewModel: FaceTrackingViewModel?
    
    private var synchronizedDepthData: AVDepthData?
    private var synchronizedVideoPixelBuffer: CVPixelBuffer?
    
    private let faceDetectionRequest = VNDetectFaceLandmarksRequest()
    private let faceDetectionHandler = VNSequenceRequestHandler()
    
    private var leftEyePosition = SCNVector3(0, 0, 0)
    private var rightEyePosition = SCNVector3(0, 0, 0)
    private var chin = SCNVector3(0, 0, 0)
    
    // MARK: - Properties
    @IBOutlet weak private var cameraUnavailableLabel: UILabel!
    @IBOutlet weak private var depthSmoothingSwitch: UISwitch!
    @IBOutlet weak private var mixFactorSlider: UISlider!
    @IBOutlet weak private var touchDepth: UILabel!
    @IBOutlet weak private var smoothDepthLabel: UILabel!
    
    @IBOutlet weak private var cloudView: PointCloudMetalView!
    
    private func processFrameAV(depthData: AVDepthData, imageData: CVImageBuffer) {
        let depthPixelBuffer = depthData.depthDataMap
        let colorPixelBuffer = imageData
        
        CVPixelBufferLockBaseAddress(depthPixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(colorPixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthPixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(colorPixelBuffer, .readOnly)
        }
        
        let colorWidth = CVPixelBufferGetWidth(colorPixelBuffer)
        let colorHeight = CVPixelBufferGetHeight(colorPixelBuffer)
        let depthWidth = CVPixelBufferGetWidth(depthPixelBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthPixelBuffer)
        
        print("Image Width: \(colorWidth) | Image Height: \(colorHeight)")
        print("Depth Data Width: \(depthWidth) | Depth Data Height: \(depthHeight)")
        
        guard let colorData = CVPixelBufferGetBaseAddress(colorPixelBuffer) else {
            print("Unable to get image buffer base address.")
            return
        }
        
        let colorBytesPerRow = CVPixelBufferGetBytesPerRow(colorPixelBuffer)
        let colorBytesPerPixel = 4 // BGRA format
        
        guard let depthDataAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer) else {
            print("Unable to get depth buffer base address.")
            return
        }
        
        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthPixelBuffer)
        // Determine the bytes per pixel based on the depth format type
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
        let colorBaseAddress = CVPixelBufferGetBaseAddress(colorPixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        
        // Call the point cloud creation function
        ExternalData.createAVPointCloudGeometry(
            depthData: depthData,
            colorData: colorBaseAddress,
            width: commonWidth,
            height: commonHeight,
            bytesPerRow: colorBytesPerRow // Use the correct bytes per row for color data
        )
    }
    
    private func detectFaceLandmarks(in pixelBuffer: CVPixelBuffer, frame: ARFrame) {
        try? faceDetectionHandler.perform([faceDetectionRequest], on: pixelBuffer, orientation: .right)
        guard let observations = faceDetectionRequest.results else {
            return
        }
        
        for observation in observations {
            if let leftEye = observation.landmarks?.leftEye, let rightEye = observation.landmarks?.rightEye {
                let leftEyePosition = averagePoint(from: leftEye.normalizedPoints, in: observation.boundingBox, pixelBuffer: pixelBuffer)
                let rightEyePosition = averagePoint(from: rightEye.normalizedPoints, in: observation.boundingBox, pixelBuffer: pixelBuffer)
                
                // Perform raycasting for each eye position
                if let leftEyeRaycastQuery: ARRaycastQuery? = frame.raycastQuery(from: leftEyePosition, allowing: .estimatedPlane, alignment: .any),
                   let rightEyeRaycastQuery: ARRaycastQuery? = frame.raycastQuery(from: rightEyePosition, allowing: .estimatedPlane, alignment: .any) {
                    let leftEyeResults = session.raycast(leftEyeRaycastQuery!)
                    let rightEyeResults = session.raycast(rightEyeRaycastQuery!)
                    
                    print("FUCK: \(leftEyeResults)")
                    
                    // Process the results
                    if let leftEyeHit = leftEyeResults.first, let rightEyeHit = rightEyeResults.first {
                        DispatchQueue.main.async {
                            self.leftEyePosition = SCNVector3(leftEyeHit.worldTransform.columns.3.x,
                                                              leftEyeHit.worldTransform.columns.3.y,
                                                              leftEyeHit.worldTransform.columns.3.z)
                            
                            print("LEFT: \(self.leftEyePosition)")
                            
                            self.rightEyePosition = SCNVector3(rightEyeHit.worldTransform.columns.3.x,
                                                               rightEyeHit.worldTransform.columns.3.y,
                                                               rightEyeHit.worldTransform.columns.3.z)
                            
                            print("RIGHT: \(self.rightEyePosition)")
                        }
                    }
                }
            }
            
            if let faceContour = observation.landmarks?.faceContour {
                let points = faceContour.normalizedPoints
                if let lowestPoint = points.min(by: { $0.y < $1.y }) {
                    let chinPosition = averagePoint(from: [lowestPoint], in: observation.boundingBox, pixelBuffer: pixelBuffer)
                    
                    // Perform raycasting for the chin position
                    if let chinRaycastQuery: ARRaycastQuery? = frame.raycastQuery(from: chinPosition, allowing: .estimatedPlane, alignment: .any) {
                        let chinResults = session.raycast(chinRaycastQuery!)
                        
                        // Process the results
                        if let chinHit = chinResults.first {
                            DispatchQueue.main.async {
                                self.chin = SCNVector3(chinHit.worldTransform.columns.3.x,
                                                       chinHit.worldTransform.columns.3.y,
                                                       chinHit.worldTransform.columns.3.z)
                                // Update any UI elements or AR nodes here for the chin
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func averagePoint(from normalizedPoints: [CGPoint], in boundingBox: CGRect, pixelBuffer: CVPixelBuffer) -> CGPoint {
        let sum = normalizedPoints.reduce(CGPoint.zero, { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) })
        let count = CGFloat(normalizedPoints.count)
        let average = CGPoint(x: sum.x / count, y: sum.y / count)
        
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let originX = boundingBox.origin.x * width
        let originY = boundingBox.origin.y * height
        
        return CGPoint(x: average.x * boundingBox.width * width + originX,
                       y: average.y * boundingBox.height * height + originY)
    }
    
    
    // UI Properties
    private var statusLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        session.delegate = self
        configureUI()
        configureGestureRecognizers()
        configureARSession()
        configureAVCaptureSession()
        switchSession(toARSession: true)
        
        configureToggleButton()
    }
    
    private func configureToggleButton() {
           toggleButton = UIButton(type: .system)
           toggleButton.translatesAutoresizingMaskIntoConstraints = false
           toggleButton.setTitle("Toggle Saving", for: .normal)
           toggleButton.addTarget(self, action: #selector(toggleSavingAction), for: .touchUpInside)

           view.addSubview(toggleButton)

           NSLayoutConstraint.activate([
               toggleButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
               toggleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
           ])
       }

       @objc private func toggleSavingAction() {
           ExternalData.isSavingFileAsPLY.toggle() // Assuming ExternalData.isSavingFileAsPLY is a static property
           updateStatusLabel(withText: ExternalData.isSavingFileAsPLY ? "Saving Enabled" : "Saving Disabled")

           // Optionally, manually switch session if needed
           switchSession(toARSession: !ExternalData.isSavingFileAsPLY)
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
            
            DispatchQueue.main.async {
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
                
                ExternalData.faceYawAngle = Double(yawDegrees)
                ExternalData.facePitchAngle = Double(pitchDegrees)
                ExternalData.faceRollAngle = Double(rollDegrees)
                
                if self.synchronizedVideoPixelBuffer != nil {
                    // Perform processing if both depth and video data are available
                    if let depthData = self.synchronizedDepthData,
                       let videoPixelBuffer = self.synchronizedVideoPixelBuffer {
                        self.detectFaceLandmarks(in: videoPixelBuffer, frame: frame)
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
    
    @IBSegueAction func embedSwiftUIView(_ coder: NSCoder) -> UIViewController? {
            // Upon Scan Completion...
            let hostingController = UIHostingController(coder: coder, rootView: ExportView())!
            hostingController.view.backgroundColor = .clear
            return hostingController
        }
    
    private func configureUI() {
        statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Initializing..."
        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)
        
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
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
        updateStatusLabel(withText: "ARSession Running")
    }
    
    private func pauseARSession() {
        session.pause()
        updateStatusLabel(withText: "ARSession Paused")
    }
    
    private func startAVCaptureSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.avCaptureSession.startRunning()
        }
        
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
        outputSynchronizer?.setDelegate(self, queue: dataOutputQueue)
        updateStatusLabel(withText: "AVCaptureSession Running")
    }
    
    private func pauseAVCaptureSession() {
        avCaptureSession.stopRunning()
        outputSynchronizer?.setDelegate(nil, queue: nil)
        updateStatusLabel(withText: "AVCaptureSession Paused")
    }
    
    private func updateStatusLabel(withText text: String) {
        DispatchQueue.main.async {
            self.statusLabel.text = text
        }
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
        let depthPixelBuffer = depthData.depthDataMap
        let sampleBuffer = syncedVideoData.sampleBuffer
        guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
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
