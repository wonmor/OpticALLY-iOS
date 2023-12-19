//
//  CameraViewController.swift
//  OpticALLY
//
//  Created by John Seong on 11/26/23.
//

import SwiftUI
import UIKit
import ARKit
import Vision
import Accelerate
import AVFoundation
import CoreImage
import CoreVideo

/// CameraViewController manages and handles the ARKit-based camera session for depth and facial landmark detection, as well as the visualization of point clouds. This class utilizes ARKit, Vision, and AVFoundation frameworks to process and display 3D depth data and facial landmarks in real-time.

/// Utilize CameraViewController for applications involving augmented reality, 3D modeling, or advanced image processing. The class provides functionality to start and pause AR sessions, process frame data, and manage gesture interactions with the point cloud view.

/// Example Usage:
/// /// let cameraViewController = CameraViewController() /// cameraViewController.startARSession() // Begins AR session with face tracking /// cameraViewController.pauseARSession() // Pauses the ongoing AR session ///

/// > Warning: Ensure the device supports ARKit's face tracking capabilities before initiating the session.

/// - Properties:
/// - cameraUnavailableLabel: UILabel to indicate when the camera is unavailable.
/// - depthSmoothingSwitch: UISwitch to toggle depth smoothing.
/// - mixFactorSlider: UISlider to adjust the mix factor for depth and color data.
/// - touchDepth: UILabel to display the depth value at the touch point.
/// - cloudView: A custom view for rendering the point cloud.

/// - Methods:
/// - startARSession(): Initializes and begins the AR session with face tracking and depth data processing.
/// - pauseARSession(): Pauses the ongoing AR session.
/// - processFrame(depthData:videoPixelBuffer:): Processes each frame of depth and video data, updating the point cloud view.
/// - Gesture handling methods (pinch, pan, double tap, rotate) for interacting with the point cloud view.

/// - Conformances:
/// - ARSessionDelegate: Allows the class to respond to AR session updates and errors.
/// - ARSCNViewDelegate: Enables custom rendering and interaction with the AR scene view.

/// This class serves as a comprehensive solution for applications requiring real-time 3D depth processing and visualization, combining ARKit's capabilities with advanced image processing techniques.

class CameraViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate, AVCaptureDataOutputSynchronizerDelegate {
    // MARK: - Properties
    @IBOutlet weak private var cameraUnavailableLabel: UILabel!
    @IBOutlet weak private var depthSmoothingSwitch: UISwitch!
    @IBOutlet weak private var mixFactorSlider: UISlider!
    @IBOutlet weak private var touchDepth: UILabel!
    @IBOutlet weak private var smoothDepthLabel: UILabel!
    
    @IBOutlet weak private var cloudView: PointCloudMetalView!
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private var setupResult: SessionSetupResult = .success
    
    var session: ARSession = ARSession()
    var avCaptureSession: AVCaptureSession = AVCaptureSession()
    
    private var isSessionRunning = false
        
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], autoreleaseFrequency: .workItem)
    private let dataOutputQueue = DispatchQueue(label: "video data queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private var videoDeviceInput: AVCaptureDeviceInput!
    
    private let videoDepthMixer = VideoMixer()
    
    func handleSessionSwitch() {
        self.configureSession()
        
        if ExternalData.isSavingFileAsPLY {
            // Switch to AVCaptureSession
            session.pause()
            self.sessionQueue.resume()
            
            self.configureAVCaptureSession()
            
            sessionQueue.async {
                self.depthDataOutput.isFilteringEnabled = true
            }
            
        } else {
            // Switch back to ARSession
            avCaptureSession.stopRunning()
            
            let configuration = ARFaceTrackingConfiguration()
            configuration.isLightEstimationEnabled = true
            
            self.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
    }
    
    func handleSessionSwitchInLoop() {
        if ExternalData.isSavingFileAsPLY {
            // Switch to AVCaptureSession
            session.pause()
            
            sessionQueue.async {
                self.depthDataOutput.isFilteringEnabled = true
            }
            
        } else {
            // Switch back to ARSession
            avCaptureSession.stopRunning()
        }
    }
    
    private var synchronizedDepthData: AVDepthData?
    private var synchronizedVideoPixelBuffer: CVPixelBuffer?
    
    private var globalDepthData: AVDepthData!
    private var globalVideoPixelBuffer: CVImageBuffer!
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera],
                                                                               mediaType: .video,
                                                                               position: .front)
    
    private var statusBarOrientation: UIInterfaceOrientation = .portrait
    
    private var touchDetected = false
    private var touchCoordinates = CGPoint(x: 0, y: 0)
    
    private var lastScale = Float(1.0)
    private var lastScaleDiff = Float(0.0)
    private var lastZoom = Float(0.0)
    private var lastXY = CGPoint(x: 0, y: 0)
    
    private var leftEyePosition = SCNVector3(0, 0, 0)
    private var rightEyePosition = SCNVector3(0, 0, 0)
    private var chin = SCNVector3(0, 0, 0)
    
    private var viewFrameSize = CGSize()
    private var autoPanningIndex = Int(-1) // start with auto-panning off
    
    private let faceDetectionRequest = VNDetectFaceLandmarksRequest()
    private let faceDetectionHandler = VNSequenceRequestHandler()
    
    var viewModel: FaceTrackingViewModel?
    
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
        guard let observations = faceDetectionRequest.results as? [VNFaceObservation] else {
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
    
    
    // MARK: - View Controller Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        session.delegate = self
        
        // Bring other views to the front if they are already added in the storyboard
        view.bringSubviewToFront(cameraUnavailableLabel)
        view.bringSubviewToFront(cloudView)
        
        viewFrameSize = self.view.frame.size
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        cloudView.addGestureRecognizer(pinchGesture)
        
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.numberOfTouchesRequired = 1
        cloudView.addGestureRecognizer(doubleTapGesture)
        
        let rotateGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
        cloudView.addGestureRecognizer(rotateGesture)
        
        let panOneFingerGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanOneFinger))
        panOneFingerGesture.maximumNumberOfTouches = 1
        panOneFingerGesture.minimumNumberOfTouches = 1
        cloudView.addGestureRecognizer(panOneFingerGesture)
        
        // Default position...
        cloudView.yawAroundCenter(30)
        cloudView.moveTowardCenter(-250.0)
        
        // Check video authorization status, video access is required
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant video access
             We suspend the session queue to delay session setup until the access request has completed
             */
            
            if ExternalData.isSavingFileAsPLY {
                // Switch to AVCaptureSession
                sessionQueue.suspend()
                
            } else {
                // Switch to ARKit
                session.pause()
            }
            
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                
                self.handleSessionSwitch()
            })
            
        default:
            // The user has previously denied access
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general it is not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Why not do all of this on the main queue?
         Because AVCaptureSession.startRunning() is a blocking call which can
         take a long time. We dispatch session setup to the sessionQueue so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        
        // Check if ExternalData.isSavingFileAsPLY is TRUE...
        self.handleSessionSwitch()
    }
    
    // MARK: - AVCaptureSession Management
    
    // Call this on the session queue
    private func configureAVCaptureSession() {
        if setupResult != .success {
            return
        }
        
        let defaultVideoDevice: AVCaptureDevice? = videoDeviceDiscoverySession.devices.first
        
        guard let videoDevice = defaultVideoDevice else {
            print("Could not find any video device")
            setupResult = .configurationFailed
            return
        }
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            return
        }
        
        avCaptureSession.beginConfiguration()
        
        avCaptureSession.sessionPreset = AVCaptureSession.Preset.vga640x480
        
        // Add a video input
        guard avCaptureSession.canAddInput(videoDeviceInput) else {
            print("Could not add video device input to the session")
            setupResult = .configurationFailed
            avCaptureSession.commitConfiguration()
            return
        }
        avCaptureSession.addInput(videoDeviceInput)
        
        // Add a video data output
        if avCaptureSession.canAddOutput(videoDataOutput) {
            avCaptureSession.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        } else {
            print("Could not add video data output to the session")
            setupResult = .configurationFailed
            avCaptureSession.commitConfiguration()
            return
        }
        
        // Add a depth data output
        if avCaptureSession.canAddOutput(depthDataOutput) {
            avCaptureSession.addOutput(depthDataOutput)
            depthDataOutput.isFilteringEnabled = true
            if let connection = depthDataOutput.connection(with: .depthData) {
                connection.isEnabled = true
            } else {
                print("No AVCaptureConnection")
            }
        } else {
            print("Could not add depth data output to the session")
            setupResult = .configurationFailed
            avCaptureSession.commitConfiguration()
            return
        }
        
        // Search for highest resolution with half-point depth values
        let depthFormats = videoDevice.activeFormat.supportedDepthDataFormats
        let filtered = depthFormats.filter({
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat16
        })
        let selectedFormat = filtered.max(by: {
            first, second in CMVideoFormatDescriptionGetDimensions(first.formatDescription).width < CMVideoFormatDescriptionGetDimensions(second.formatDescription).width
        })
        
        do {
            try videoDevice.lockForConfiguration()
            videoDevice.activeDepthDataFormat = selectedFormat
            videoDevice.unlockForConfiguration()
        } catch {
            print("Could not lock device for configuration: \(error)")
            setupResult = .configurationFailed
            avCaptureSession.commitConfiguration()
            return
        }
        
        // Use an AVCaptureDataOutputSynchronizer to synchronize the video data and depth data outputs.
        // The first output in the dataOutputs array, in this case the AVCaptureVideoDataOutput, is the "master" output.
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
        outputSynchronizer!.setDelegate(self, queue: dataOutputQueue)
        avCaptureSession.commitConfiguration()
    }
    
    // MARK: - Video + Depth Frame Processing (AVCaptureSession)
       
       func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                   didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
           // Check if ExternalData.isSavingFileAsPLY is TRUE...
           self.handleSessionSwitchInLoop()
           
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
           
           if ExternalData.isSavingFileAsPLY {
               processFrameAV(depthData: depthData, imageData: videoPixelBuffer)
               
               // Set cloudView to empty depth data and texture
               cloudView?.setDepthFrame(nil, withTexture: nil)
               
               ExternalData.isSavingFileAsPLY = false
           }
           
           globalDepthData = depthData
           globalVideoPixelBuffer = videoPixelBuffer
           
           cloudView?.setDepthFrame(depthData, withTexture: videoPixelBuffer)
       }
    
    // MARK: - ARSessionDelegate Methods
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Check if ExternalData.isSavingFileAsPLY is TRUE...
        self.handleSessionSwitchInLoop()
        
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
                ExternalData.pupilDistance = Double(self.calculatePupillaryDistance(faceAnchor: faceAnchor))
                
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
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Handle session errors
        print("ARSession failed: \(error.localizedDescription)")
    }
    
    func calculatePupillaryDistance(faceAnchor: ARFaceAnchor) -> Float {
        let distance = sqrt(
            pow(leftEyePosition.x - rightEyePosition.x, 2) +
            pow(leftEyePosition.y - rightEyePosition.y, 2) +
            pow(leftEyePosition.z - rightEyePosition.z, 2)
        )
        
        // Convert to millimeters or another unit if required
        // ARKit's default unit is meters
        let distanceInMillimeters = distance * 1000
        return distanceInMillimeters
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let faceAnchor = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        DispatchQueue.main.async {
            self.viewModel!.faceAnchor = faceAnchor
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Handle session interruption
        print("ARSession was interrupted")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Handle session interruption end
        print("ARSession interruption ended")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create and run a session
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        session.run(configuration)
        
        let interfaceOrientation = UIApplication.shared.statusBarOrientation
        statusBarOrientation = interfaceOrientation
        
        let initialThermalState = ProcessInfo.processInfo.thermalState
        
        if initialThermalState == .serious || initialThermalState == .critical {
            showThermalState(state: initialThermalState)
        }
        
        if ExternalData.isSavingFileAsPLY {
            sessionQueue.async {
                      switch self.setupResult {
                      case .success:
                          // Only setup observers and start the session running if setup succeeded
                          self.addObservers()
                          let videoOrientation = self.videoDataOutput.connection(with: .video)!.videoOrientation
                          let videoDevicePosition = self.videoDeviceInput.device.position
                          let rotation = PreviewMetalView.Rotation(with: interfaceOrientation,
                                                                   videoOrientation: videoOrientation,
                                                                   cameraPosition: videoDevicePosition)
                          
                          self.dataOutputQueue.async {
                              ExternalData.renderingEnabled = true
                          }
                          
                          self.avCaptureSession.startRunning()
                          self.isSessionRunning = self.avCaptureSession.isRunning
                          
                      case .notAuthorized:
                          DispatchQueue.main.async {
                              let message = NSLocalizedString("TrueDepthStreamer doesn't have permission to use the camera, please change privacy settings",
                                                              comment: "Alert message when the user has denied access to the camera")
                              let alertController = UIAlertController(title: "Harolden 3D Capture", message: message, preferredStyle: .alert)
                              alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                                      style: .cancel,
                                                                      handler: nil))
                              alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                                      style: .`default`,
                                                                      handler: { _ in
                                  UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                            options: [:],
                                                            completionHandler: nil)
                              }))
                              
                              self.present(alertController, animated: true, completion: nil)
                          }
                          
                      case .configurationFailed:
                          DispatchQueue.main.async {
                              self.cameraUnavailableLabel.isHidden = false
                              self.cameraUnavailableLabel.alpha = 0.0
                              UIView.animate(withDuration: 0.25) {
                                  self.cameraUnavailableLabel.alpha = 1.0
                              }
                          }
                      }
                  }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        ExternalData.renderingEnabled = false
        
        dataOutputQueue.async {
                    ExternalData.renderingEnabled = false
                }
        
        if ExternalData.isSavingFileAsPLY {
            sessionQueue.async {
                if self.setupResult == .success {
                    self.avCaptureSession.stopRunning()
                    self.isSessionRunning = self.avCaptureSession.isRunning
                }
            }
        }
        
        super.viewWillDisappear(animated)
        
        // Pause the AR session
        session.pause()
    }
    
    @objc
    func didEnterBackground(notification: NSNotification) {
        // Free up resources
        ExternalData.renderingEnabled = false
        
        self.videoDepthMixer.reset()
    }
    
    @objc
    func willEnterForground(notification: NSNotification) {
        ExternalData.renderingEnabled = true
    }
    
    // You can use this opportunity to take corrective action to help cool the system down.
    @objc
    func thermalStateChanged(notification: NSNotification) {
        if let processInfo = notification.object as? ProcessInfo {
            showThermalState(state: processInfo.thermalState)
        }
    }
    
    func showThermalState(state: ProcessInfo.ThermalState) {
        DispatchQueue.main.async {
            var thermalStateString = "UNKNOWN"
            if state == .nominal {
                thermalStateString = "NOMINAL"
            } else if state == .fair {
                thermalStateString = "FAIR"
            } else if state == .serious {
                thermalStateString = "SERIOUS"
            } else if state == .critical {
                thermalStateString = "CRITICAL"
            }
            
            let message = NSLocalizedString("iPhone Temperature: \(thermalStateString)", comment: "Alert message when thermal state has changed")
            let alertController = UIAlertController(title: "Harolden 3D Capture", message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
            self.present(alertController, animated: true, completion: nil)
        }
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(alongsideTransition: { _ in
            let interfaceOrientation = UIApplication.shared.statusBarOrientation
            self.statusBarOrientation = interfaceOrientation
            
            if ExternalData.isSavingFileAsPLY {
                self.sessionQueue.async {
                    /*
                     The photo orientation is based on the interface orientation. You could also set the orientation of the photo connection based
                     on the device orientation by observing UIDeviceOrientationDidChangeNotification.
                     */
                    let videoOrientation = self.videoDataOutput.connection(with: .video)!.videoOrientation
                }
            }
        }, completion: nil)
    }
    
    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification,    object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError),
                                               name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Session Management
    
    // Call this on the session queue
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        let defaultVideoDevice: AVCaptureDevice? = videoDeviceDiscoverySession.devices.first
        
        guard let videoDevice = defaultVideoDevice else {
            print("Could not find any video device")
            setupResult = .configurationFailed
            return
        }
        
        let depthFormats = videoDevice.activeFormat.supportedDepthDataFormats
        let highestResolutionFormat = depthFormats.filter { CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32 }
            .max { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }
        
        if let selectedFormat = highestResolutionFormat {
            do {
                try videoDevice.lockForConfiguration()
                videoDevice.activeDepthDataFormat = selectedFormat
                videoDevice.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
        if ExternalData.isSavingFileAsPLY {
            sessionQueue.async {
                 let videoDevice = self.videoDeviceInput.device
                 
                 do {
                     try videoDevice.lockForConfiguration()
                     if videoDevice.isFocusPointOfInterestSupported && videoDevice.isFocusModeSupported(focusMode) {
                         videoDevice.focusPointOfInterest = devicePoint
                         videoDevice.focusMode = focusMode
                     }
                     
                     if videoDevice.isExposurePointOfInterestSupported && videoDevice.isExposureModeSupported(exposureMode) {
                         videoDevice.exposurePointOfInterest = devicePoint
                         videoDevice.exposureMode = exposureMode
                     }
                     
                     videoDevice.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                     videoDevice.unlockForConfiguration()
                 } catch {
                     print("Could not lock device for configuration: \(error)")
                 }
             }
        }
    }
    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
           let reasonIntegerValue = userInfoValue.integerValue,
           let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
            
            if reason == .videoDeviceInUseByAnotherClient {
                // Simply fade-in a button to enable the user to try to resume the session running.
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                // Simply fade-in a label to inform the user that the camera is unavailable.
                cameraUnavailableLabel.isHidden = false
                cameraUnavailableLabel.alpha = 0.0
                UIView.animate(withDuration: 0.25) {
                    self.cameraUnavailableLabel.alpha = 1.0
                }
            }
        }
    }
    
    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        if !cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                self.cameraUnavailableLabel.alpha = 0
            }, completion: { _ in
                self.cameraUnavailableLabel.isHidden = true
            }
            )
        }
    }
    
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }
        
        let error = AVError(_nsError: errorValue)
        print("Capture session runtime error: \(error)")
        
        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
    }
    
    
    // MARK: - Point cloud view gestures
    
    @IBAction private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.numberOfTouches != 2 {
            return
        }
        if gesture.state == .began {
            lastScale = 1
        } else if gesture.state == .changed {
            let scale = Float(gesture.scale)
            let diff: Float = scale - lastScale
            let factor: Float = 1e3
            if scale < lastScale {
                lastZoom = diff * factor
            } else {
                lastZoom = diff * factor
            }
            DispatchQueue.main.async {
                self.autoPanningIndex = -1
            }
            cloudView.moveTowardCenter(lastZoom)
            lastScale = scale
        } else if gesture.state == .ended {
        } else {
        }
    }
    
    @IBAction private func handlePanOneFinger(gesture: UIPanGestureRecognizer) {
        if gesture.numberOfTouches != 1 {
            return
        }
        
        if gesture.state == .began {
            let pnt: CGPoint = gesture.translation(in: cloudView)
            lastXY = pnt
        } else if (.failed != gesture.state) && (.cancelled != gesture.state) {
            let pnt: CGPoint = gesture.translation(in: cloudView)
            DispatchQueue.main.async {
                self.autoPanningIndex = -1
            }
            cloudView.yawAroundCenter(Float((pnt.x - lastXY.x) * 0.1))
            cloudView.pitchAroundCenter(Float((pnt.y - lastXY.y) * 0.1))
            lastXY = pnt
        }
    }
    
    @IBAction private func handleDoubleTap(gesture: UITapGestureRecognizer) {
        DispatchQueue.main.async {
            self.autoPanningIndex = -1
        }
    }
    
    @IBAction private func handleRotate(gesture: UIRotationGestureRecognizer) {
        if gesture.numberOfTouches != 2 {
            return
        }
        
        if gesture.state == .changed {
            let rot = Float(gesture.rotation)
            DispatchQueue.main.async {
                self.autoPanningIndex = -1
            }
            cloudView.rollAroundCenter(rot * 60)
            gesture.rotation = 0
        }
    }
    
    func extractDepthData(depthData: AVDepthData, imageSampler: CapturedImageSampler) {
        let depthPixelBuffer = depthData.depthDataMap
        
        CVPixelBufferLockBaseAddress(depthPixelBuffer, .readOnly)
        
        defer {
            CVPixelBufferUnlockBaseAddress(depthPixelBuffer, .readOnly)
        }
        
        ExternalData.depthWidth = CVPixelBufferGetWidth(depthPixelBuffer)
        ExternalData.depthHeight = CVPixelBufferGetHeight(depthPixelBuffer)
        
        // Prepare transformation based on yaw, pitch, and roll
        let yaw = ExternalData.faceYawAngle
        let pitch = ExternalData.facePitchAngle
        let roll = ExternalData.faceRollAngle
        let transform = makeTransformationMatrix(yaw: yaw, pitch: pitch, roll: roll)
        
        if ExternalData.isSavingFileAsPLY {
            let pointCloudMetadata = PointCloudMetadata(
                yaw: ExternalData.faceYawAngle,
                pitch: ExternalData.facePitchAngle,
                roll: ExternalData.faceRollAngle,
                leftEyePosition: leftEyePosition,
                rightEyePosition: rightEyePosition,
                chin: chin
            )
            
            ExternalData.pointCloudDataArray.append(pointCloudMetadata)
            ExternalData.isSavingFileAsPLY = false
        }
        
        // Existing point cloud creation function, modified to include transformation
        ExternalData.createPointCloudGeometry(
            depthData: depthData,
            imageSampler: imageSampler,
            width: ExternalData.depthWidth,
            height: ExternalData.depthHeight,
            calibrationData: depthData.cameraCalibrationData!,
            transform: transform // pass the transform here
        )
        
        // Synchronize access to the shared resource
        DispatchQueue.main.async {
            ExternalData.renderingEnabled = true
        }
    }
    
    // Function to create a transformation matrix from Euler angles
    func makeTransformationMatrix(yaw: Double, pitch: Double, roll: Double) -> SCNMatrix4 {
        let yawMatrix = SCNMatrix4MakeRotation(Float(yaw), 0, 1, 0)
        let pitchMatrix = SCNMatrix4MakeRotation(Float(pitch), 1, 0, 0)
        let rollMatrix = SCNMatrix4MakeRotation(Float(roll), 0, 0, 1)
        
        let combinedMatrix = SCNMatrix4Mult(SCNMatrix4Mult(yawMatrix, pitchMatrix), rollMatrix)
        return combinedMatrix
    }
    
    @IBSegueAction func embedSwiftUIView(_ coder: NSCoder) -> UIViewController? {
        // Upon Scan Completion...
        let hostingController = UIHostingController(coder: coder, rootView: ExportView())!
        hostingController.view.backgroundColor = .clear
        return hostingController
    }
}

extension AVCaptureVideoOrientation {
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

extension PreviewMetalView.Rotation {
    init?(with interfaceOrientation: UIInterfaceOrientation, videoOrientation: AVCaptureVideoOrientation, cameraPosition: AVCaptureDevice.Position) {
        /*
         Calculate the rotation between the videoOrientation and the interfaceOrientation.
         The direction of the rotation depends upon the camera position.
         */
        switch videoOrientation {
            
        case .portrait:
            switch interfaceOrientation {
            case .landscapeRight:
                self = cameraPosition == .front ? .rotate90Degrees : .rotate270Degrees
                
            case .landscapeLeft:
                self = cameraPosition == .front ? .rotate270Degrees : .rotate90Degrees
                
            case .portrait:
                self = .rotate0Degrees
                
            case .portraitUpsideDown:
                self = .rotate180Degrees
                
            default: return nil
            }
            
        case .portraitUpsideDown:
            switch interfaceOrientation {
            case .landscapeRight:
                self = cameraPosition == .front ? .rotate270Degrees : .rotate90Degrees
                
            case .landscapeLeft:
                self = cameraPosition == .front ? .rotate90Degrees : .rotate270Degrees
                
            case .portrait:
                self = .rotate180Degrees
                
            case .portraitUpsideDown:
                self = .rotate0Degrees
                
            default: return nil
            }
            
        case .landscapeRight:
            switch interfaceOrientation {
            case .landscapeRight:
                self = .rotate0Degrees
                
            case .landscapeLeft:
                self = .rotate180Degrees
                
            case .portrait:
                self = cameraPosition == .front ? .rotate270Degrees : .rotate90Degrees
                
            case .portraitUpsideDown:
                self = cameraPosition == .front ? .rotate90Degrees : .rotate270Degrees
                
            default: return nil
            }
            
        case .landscapeLeft:
            switch interfaceOrientation {
            case .landscapeLeft:
                self = .rotate0Degrees
                
            case .landscapeRight:
                self = .rotate180Degrees
                
            case .portrait:
                self = cameraPosition == .front ? .rotate90Degrees : .rotate270Degrees
                
            case .portraitUpsideDown:
                self = cameraPosition == .front ? .rotate270Degrees : .rotate90Degrees
                
            default: return nil
            }
        @unknown default:
            fatalError("Unknown orientation. Can't continue.")
        }
    }
}
