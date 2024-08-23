//
//  CameraViewController.swift
//  OpticALLY
//
//  Created by John Seong on 9/10/23.
//

import SwiftUI
import UIKit
import SceneKit
import AVFoundation
import CoreImage
import CoreVideo

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

/// Size of the generated face texture
private let faceTextureSize = 1024 //px

/// Should the face mesh be filled in? (i.e. fill in the eye and mouth holes with geometry)
private let fillMesh = true

class CameraViewController: UIViewController, AVCaptureDataOutputSynchronizerDelegate, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureMetadataOutputObjectsDelegate {
    var contentNode: SCNNode?
    
    // MARK: - Properties
    @Published var currentImage: UIImage!
    @Published var faceDistance: Int?
    
    @Published var faceYawAngle: Double = 0.0
    @Published var facePitchAngle: Double = 0.0
    @Published var faceRollAngle: Double = 0.0
    @Published var pupilDistance: Double = 0.0
    
    @Published var noseTip: CGPoint = CGPoint(x: 0, y: 0)
    @Published var chin: CGPoint = CGPoint(x: 0, y: 0)
    @Published var leftEyeLeftCorner: CGPoint = CGPoint(x: 0, y: 0)
    @Published var rightEyeRightCorner: CGPoint = CGPoint(x: 0, y: 0)
    @Published var leftMouthCorner: CGPoint = CGPoint(x: 0, y: 0)
    @Published var rightMouthCorner: CGPoint = CGPoint(x: 0, y: 0)
    
    @ObservedObject var videoFrameData = VideoFrameData()
    
    var leftEye = SCNNode()
    var rightEye = SCNNode()
    
    let layer = AVSampleBufferDisplayLayer()
    let sampleQueue = DispatchQueue(label: "com.zweigraf.DisplayLiveSamples.sampleQueue", attributes: [])
    let faceQueue = DispatchQueue(label: "com.zweigraf.DisplayLiveSamples.faceQueue", attributes: [])
    
    var currentMetadata: [AnyObject] = []
    
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private var output = AVCaptureVideoDataOutput()
    private var depthDataOutput = AVCaptureDepthDataOutput()
    
    private var previewYaws: [Float] = []
    private var previewPitches: [Float] = []
    private var previewRolls: [Float] = []
    
    private var sessionQueue = DispatchQueue(label: "session queue")
    private var dataOutputQueue = DispatchQueue(label: "data output queue")
    
    private var synchronizedDepthData: AVDepthData?
    private var synchronizedVideoPixelBuffer: CVPixelBuffer?
    
    private var input: AVCaptureDeviceInput? = nil
    
    private let videoDepthMixer = VideoMixer()
    
    private var scaleX: Float = 1.0
    private var scaleY: Float = 1.0
    private var scaleZ: Float = 1.0
    
    private var lastScale = Float(1.0)
    private var lastScaleDiff = Float(0.0)
    private var lastZoom = Float(0.0)
    private var lastXY = CGPoint(x: 0, y: 0)
    
    private var viewFrameSize = CGSize()
    private var autoPanningIndex = Int(-1) // start with auto-panning off
    
    // MARK: - UI Bindings
    @IBOutlet weak private var preview: UIView!
    @IBOutlet weak private var cameraUnavailableLabel: UILabel!
    @IBOutlet weak private var depthSmoothingSwitch: UISwitch!
    @IBOutlet weak private var mixFactorSlider: UISlider!
    @IBOutlet weak private var touchDepth: UILabel!
    @IBOutlet weak private var smoothDepthLabel: UILabel!
    @IBOutlet weak private var cloudView: PointCloudMetalView!
    
    var wrapper: DlibWrapper!
    
    var imageView: UIImageView!
    var session = AVCaptureSession()
    
    func openSession() {
        // Use AVCaptureDeviceDiscoverySession to find the front camera
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera], mediaType: .video, position: .front)
        
        guard let device = discoverySession.devices.first else {
            print("No front camera found.")
            return
        }
        
        do {
            input = try AVCaptureDeviceInput(device: device)
            
            output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: sampleQueue)
            
            let metaOutput = AVCaptureMetadataOutput()
            metaOutput.setMetadataObjectsDelegate(self, queue: faceQueue)
            
            session.beginConfiguration()
            session.sessionPreset = AVCaptureSession.Preset.vga640x480
            
            if session.canAddInput(input!) {
                session.addInput(input!)
            }
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            if session.canAddOutput(metaOutput) {
                session.addOutput(metaOutput)
            }
            
            if session.canAddOutput(depthDataOutput) {
                session.addOutput(depthDataOutput)
            }
            
            session.commitConfiguration()
            
            let settings: [AnyHashable: Any] = [kCVPixelBufferPixelFormatTypeKey as AnyHashable: Int(kCVPixelFormatType_32BGRA)]
            output.videoSettings = settings as? [String : Any]
            
            depthDataOutput.isFilteringEnabled = true
            
            if let connection = depthDataOutput.connection(with: .depthData) {
                connection.isEnabled = true
            } else {
                print("No AVCaptureConnection")
            }
            
            // availableMetadataObjectTypes change when output is added to session.
            // before it is added, availableMetadataObjectTypes is empty
            metaOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.face]
            
            wrapper.prepare()
            session.sessionPreset = AVCaptureSession.Preset.vga640x480
            
            print("Session configured!")
            
//            // Search for highest resolution with half-point depth values
//            let depthFormats = device.activeFormat.supportedDepthDataFormats
//            let filtered = depthFormats.filter({
//                CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat16
//            })
//            let selectedFormat = filtered.max(by: {
//                first, second in CMVideoFormatDescriptionGetDimensions(first.formatDescription).width < CMVideoFormatDescriptionGetDimensions(second.formatDescription).width
//            })
//            
//            do {
//                try device.lockForConfiguration()
//                device.activeDepthDataFormat = selectedFormat
//                device.unlockForConfiguration()
//            } catch {
//                print("Could not lock device for configuration: \(error)")
//              
//                session.commitConfiguration()
//                return
//            }
            
            // Start the session on a background thread
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        } catch {
            print("Error configuring AVCaptureSession: \(error)")
        }
    }
    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    /*
     func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
     connection.videoOrientation = AVCaptureVideoOrientation.portrait
     
     if !currentMetadata.isEmpty {
     let boundsArray = currentMetadata
     .compactMap { $0 as? AVMetadataFaceObject }
     .map { NSValue(cgRect: $0.bounds) }
     
     wrapper?.doWork(on: sampleBuffer, inRects: boundsArray)
     }
     
     layer.enqueue(sampleBuffer)
     }
     
     func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
     print("DidDropSampleBuffer")
     }
     */
    
     // MARK: AVCaptureMetadataOutputObjectsDelegate
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        currentMetadata = metadataObjects // Update metadata
    }
    
    func horizontallyMirroredPixelBuffer(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let transform = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -ciImage.extent.width, y: 0)
        let mirroredImage = ciImage.transformed(by: transform)
        
        let context = CIContext()
        var mirroredPixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(mirroredImage.extent.width), Int(mirroredImage.extent.height),
                            CVPixelBufferGetPixelFormatType(pixelBuffer), nil, &mirroredPixelBuffer)
        
        context.render(mirroredImage, to: mirroredPixelBuffer!)
        return mirroredPixelBuffer
    }
    
    func verticallyMirroredPixelBuffer(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // Adjust the transform for vertical flipping
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -ciImage.extent.height)
        let mirroredImage = ciImage.transformed(by: transform)
        
        let context = CIContext()
        var mirroredPixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(mirroredImage.extent.width), Int(mirroredImage.extent.height),
                            CVPixelBufferGetPixelFormatType(pixelBuffer), nil, &mirroredPixelBuffer)
        
        context.render(mirroredImage, to: mirroredPixelBuffer!)
        return mirroredPixelBuffer
    }
    
    func convertToMatrix4(_ transform: CGAffineTransform) -> matrix_float4x4 {
        return matrix_float4x4(
            SIMD4<Float>(Float(transform.a), Float(transform.b), 0, 0),
            SIMD4<Float>(Float(transform.c), Float(transform.d), 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(Float(transform.tx), Float(transform.ty), 0, 1)
        )
    }
    
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
    
    func rotateImageData90DegreesCounterClockwise(imageData: CVPixelBuffer) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: imageData)

        // Rotate the CIImage 90 degrees counterclockwise
        let rotatedCIImage = ciImage.oriented(.left)

        // Create a CIContext for rendering the CIImage to a CVPixelBuffer
        let ciContext = CIContext()

        // Create a new CVPixelBuffer for the rotated image
        var rotatedPixelBuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let width = Int(rotatedCIImage.extent.width)
        let height = Int(rotatedCIImage.extent.height)
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, CVPixelBufferGetPixelFormatType(imageData), options as CFDictionary, &rotatedPixelBuffer)

        guard let outputBuffer = rotatedPixelBuffer else {
            print("Failed to create rotated CVPixelBuffer")
            return nil
        }

        // Render the rotated CIImage to the new CVPixelBuffer
        ciContext.render(rotatedCIImage, to: outputBuffer)

        return outputBuffer
    }
    
    private func processFrameAV(depthData: AVDepthData, imageData: CVImageBuffer) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var depthDataToUse = depthData
            
            depthDataToUse = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            
            let depthPixelBuffer = depthDataToUse.depthDataMap
            
            let depthWidth = CVPixelBufferGetWidth(depthPixelBuffer)
            let depthHeight = CVPixelBufferGetHeight(depthPixelBuffer)
            
            // VERY IMPORTANT LINE! THIS IS BECAUSE WE SET THE CONNECTION MODE TO PORTRAIT FROM LANDSCAPE IN CAMERAVIEWCONTROLLER...
            let rotatedPixelBuffer = rotateImageData90DegreesCounterClockwise(imageData: imageData)
                
            let colorPixelBuffer = self.resizePixelBuffer(rotatedPixelBuffer!, width: depthWidth, height: depthHeight)
            
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
            
            // Convert depthPixelFormatType to a string
            let depthPixelFormatTypeString = FourCharCodeToString(depthPixelFormatType)
            print("Depth Pixel Format Type: \(depthPixelFormatTypeString)")  // Log the pixel format type
            
            var depthBytesPerPixel: Int = 0 // Initialize with zero
            
            switch depthPixelFormatType {
            case kCVPixelFormatType_DepthFloat32:
                depthBytesPerPixel = 4
            case kCVPixelFormatType_DepthFloat16:
                depthBytesPerPixel = 2
            default:
                print("Unsupported depth pixel format type: \(depthPixelFormatTypeString)")
                return
            }
            
            print("depthBytesPerPixel: \(depthBytesPerPixel)")
            
            // Ensure that you're iterating within the bounds of both buffers
            let commonWidth = min(colorWidth, depthWidth)
            let commonHeight = min(colorHeight, depthHeight)
            
            // Assuming colorData is the base address for the BGRA image buffer
            let colorBaseAddress = CVPixelBufferGetBaseAddress(colorPixelBuffer!)!.assumingMemoryBound(to: UInt8.self)
            
            let metadata = PointCloudMetadata(
                yaw: Double(self.previewYaws.last ?? 0.0),
                pitch: Double(self.previewRolls.last ?? 0.0),
                roll: Double(self.previewPitches.last ?? 0.0),
                noseTip: noseTip,
                chin: chin,
                leftEyeLeftCorner: leftEyeLeftCorner,
                rightEyeRightCorner: rightEyeRightCorner,
                leftMouthCorner: leftMouthCorner,
                rightMouthCorner: rightMouthCorner,
                image: imageData,
                depth: depthDataToUse
            )
            
            ExternalData.pointCloudDataArray.append(metadata)
            
            // Call the point cloud creation function
            ExternalData.convertToSceneKitModel(
                depthData: depthDataToUse,
                colorPixelBuffer: colorPixelBuffer!,
                colorData: colorBaseAddress,
                metadata: metadata,
                width: commonWidth,
                height: commonHeight,
                bytesPerRow: colorBytesPerRow, // Use the correct bytes per row for color data,
                scaleX: self.scaleX,
                scaleY: self.scaleY,
                scaleZ: self.scaleZ
            )
        }
    }
    
    // Function to convert FourCharCode to String
    func FourCharCodeToString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
    
    private func calculateClosest3DPoint(xInt: Int, yInt: Int, threshold: CGFloat, depthWidth: Int, depthHeight: Int, depthPixelBuffer: CVPixelBuffer, cameraIntrinsics: matrix_float3x3) -> SCNVector3? {
        CVPixelBufferLockBaseAddress(depthPixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthPixelBuffer, .readOnly) }
        
        let depthPointer = CVPixelBufferGetBaseAddress(depthPixelBuffer)!.assumingMemoryBound(to: Float32.self)
        
        var closestDepthValue: Float32?
        var closestPoint = CGPoint(x: xInt, y: yInt)
        
        let startX = max(xInt - Int(threshold), 0)
        let endX = min(xInt + Int(threshold), depthWidth - 1)
        let startY = max(yInt - Int(threshold), 0)
        let endY = min(yInt + Int(threshold), depthHeight - 1)
        
        for y in startY...endY {
            for x in startX...endX {
                let depthIndex = y * depthWidth + x
                let depthValue = depthPointer[depthIndex]
                
                if closestDepthValue == nil || abs(depthValue - closestDepthValue!) < Float32(threshold) {
                    closestDepthValue = depthValue
                    closestPoint = CGPoint(x: x, y: y)
                }
            }
        }
        
        guard let finalDepthValue = closestDepthValue else { return nil }
        
        let x = (Float(closestPoint.x) - cameraIntrinsics[2][0]) / cameraIntrinsics[0][0]
        let y = (Float(closestPoint.y) - cameraIntrinsics[2][1]) / cameraIntrinsics[1][1]
        let z = finalDepthValue
        
        return SCNVector3(x * z, y * z, z)
    }
    
    private var landmarkNodes = [SCNNode]() // Add this property to your class
    
    private func averagePoint(from normalizedPoints: [CGPoint], in boundingBox: CGRect, pixelBuffer: CVPixelBuffer) -> CGPoint {
        // Calculate the average point in normalized Vision coordinates
        let viewSize = UIScreen.main.bounds.size
        
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
        
        return finalPoint
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Initialize the DlibWrapper with cloudView
        wrapper = DlibWrapper(cameraViewController: self, pointCloudView: cloudView)
        
        openSession()
        startAVCaptureSession()
        
        configureCloudView()
        addAndConfigureSwiftUIView()
        
        // Configure imageView
        // configureImageView()
        
        setupEyeNode()
        
        layer.frame = preview.bounds
        
        preview.layer.addSublayer(layer)
        preview.transform = CGAffineTransformMakeRotation(CGFloat(Double.pi))
        preview.transform = CGAffineTransformScale(preview.transform, 1, -1)
        
        self.view.bringSubviewToFront(preview)
        
        view.layoutIfNeeded()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        viewFrameSize = self.view.frame.size
        
        // Comment the line below to disable orbit controls in DEBUG...
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        cloudView.addGestureRecognizer(pinchGesture)
        
        let rotateGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
        cloudView.addGestureRecognizer(rotateGesture)
        
        let panOneFingerGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanOneFinger))
        panOneFingerGesture.maximumNumberOfTouches = 1
        panOneFingerGesture.minimumNumberOfTouches = 1
        cloudView.addGestureRecognizer(panOneFingerGesture)
    }
    
    // Method to update the yaw angle from external sources
    @objc func updateYawAngle(_ yawAngle: Double) {
        DispatchQueue.main.async {
            self.faceYawAngle = yawAngle
        }
    }
    
    @objc func updateFacialLandmarks(noseTip: CGPoint, chin: CGPoint, leftEyeLeftCorner: CGPoint, rightEyeRightCorner: CGPoint, leftMouthCorner: CGPoint, rightMouthCorner: CGPoint) {
        DispatchQueue.main.async {
            self.noseTip = noseTip
            self.chin = chin
            self.leftEyeLeftCorner = leftEyeLeftCorner
            self.rightEyeRightCorner = rightEyeRightCorner
            self.leftMouthCorner = leftMouthCorner
            self.rightMouthCorner = rightMouthCorner
        }
    }

    
    /// Creates To SCNSpheres To Loosely Represent The Eyes
    func setupEyeNode() {
        //1. Create A Node To Represent The Eye
        let eyeGeometry = SCNSphere(radius: 0.005)
        eyeGeometry.materials.first?.diffuse.contents = UIColor.cyan
        eyeGeometry.materials.first?.transparency = 1
        
        //2. Create A Holder Node & Rotate It So The Gemoetry Points Towards The Device
        let node = SCNNode()
        node.geometry = eyeGeometry
        node.eulerAngles.x = -.pi / 2
        node.position.z = 0.1
        
        //3. Create The Left & Right Eyes
        leftEye = node.clone()
        rightEye = node.clone()
    }
    
    func configureImageView() {
        imageView = UIImageView()
        
        self.view.addSubview(imageView)
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20), // 20 points from the top
            imageView.widthAnchor.constraint(equalToConstant: 200), // Set your desired width
            imageView.heightAnchor.constraint(equalToConstant: 200) // Set your desired height
        ])
        
        imageView.contentMode = .scaleAspectFit // Set content mode as needed
        imageView.backgroundColor = .clear // Set background color as needed
    }
    
    @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {}
    
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
        let hostingController = UIHostingController(rootView: ExportView(videoFrameData: videoFrameData))
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
    
    func convert(pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
    
    private func startAVCaptureSession() {
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [output, depthDataOutput])
        outputSynchronizer?.setDelegate(self, queue: dataOutputQueue)
        
        // Set the video orientation for each connection in the output
           for connection in output.connections {
               if connection.isVideoOrientationSupported {
                   connection.videoOrientation = .portrait
               }
           }
           
        print("AVCaptureSession Running")
    }
    
    private func pauseAVCaptureSession() {
        session.stopRunning()
        outputSynchronizer?.setDelegate(nil, queue: nil)
        print("AVCaptureSession Paused")
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
    
    // MARK: - Video + Depth Frame Processing (AVCaptureSession)
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        // Read all outputs
        guard ExternalData.renderingEnabled,
              let syncedDepthData: AVCaptureSynchronizedDepthData =
                synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
              let syncedVideoData: AVCaptureSynchronizedSampleBufferData =
                synchronizedDataCollection.synchronizedData(for: output) as? AVCaptureSynchronizedSampleBufferData else {
            // only work on synced pairs
            return
        }
        
        if syncedDepthData.depthDataWasDropped || syncedVideoData.sampleBufferWasDropped {
            return
        }
        
        // Process video sample buffer
            let sampleBuffer = syncedVideoData.sampleBuffer
        
        // Process depth data and video pixel buffer
        let depthData = syncedDepthData.depthData
        
        var depthDataToUse = depthData
        
        depthDataToUse = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16)
        
        // Process metadata
        if !currentMetadata.isEmpty {
            let boundsArray = currentMetadata
                .compactMap { $0 as? AVMetadataFaceObject }
                .map { NSValue(cgRect: $0.bounds) }
            
            wrapper.doWork(on: sampleBuffer, inRects: boundsArray, with: depthDataToUse)
        }
        
        guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
      
        DispatchQueue.main.async {
            self.videoFrameData.pixelBuffer = videoPixelBuffer
        }
        
        layer.enqueue(sampleBuffer)
//        cloudView?.setDepthFrame(nil, withTexture: nil)
//        cloudView?.setDepthFrame(depthData, withTexture: videoPixelBuffer)

        
        if ExternalData.isSavingFileAsPLY {
            processFrameAV(depthData: depthData, imageData: videoPixelBuffer)
            
            ExternalData.isSavingFileAsPLY = false
        }
    }
}
