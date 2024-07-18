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
///

/// Size of the generated face texture
private let faceTextureSize = 1024 //px

/// Should the face mesh be filled in? (i.e. fill in the eye and mouth holes with geometry)
private let fillMesh = true

class CameraViewController: UIViewController, AVCaptureDataOutputSynchronizerDelegate, ObservableObject {
    var contentNode: SCNNode?

    // MARK: - Properties
    @Published var currentImage: UIImage!
    @Published var faceDistance: Int?
    
    @Published var faceYawAngle: Double = 0.0
    @Published var facePitchAngle: Double = 0.0
    @Published var faceRollAngle: Double = 0.0
    @Published var pupilDistance: Double = 0.0
    
    @Published var leftEyePosition = CGPoint(x: 0, y: 0)
    @Published var rightEyePosition = CGPoint(x: 0, y: 0)
    @Published var chinPosition = CGPoint(x: 0, y: 0)
    
    @Published var leftEyePosition3D = SCNVector3(0, 0, 0)
    @Published var rightEyePosition3D = SCNVector3(0, 0, 0)
    @Published var chinPosition3D = SCNVector3(0, 0, 0)
    
    var leftEye = SCNNode()
    var rightEye = SCNNode()
    
    @Published var avCaptureSession: AVCaptureSession = AVCaptureSession()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    @Published var videoDataOutput = AVCaptureVideoDataOutput()
    private var depthDataOutput = AVCaptureDepthDataOutput()
    
    private var previewYaws: [Float] = []
    private var previewPitches: [Float] = []
    private var previewRolls: [Float] = []
    
    private var sessionQueue = DispatchQueue(label: "session queue")
    private var dataOutputQueue = DispatchQueue(label: "data output queue")
    
    private var synchronizedDepthData: AVDepthData?
    private var synchronizedVideoPixelBuffer: CVPixelBuffer?
    
    private var videoDeviceInput: AVCaptureDeviceInput? = nil
    
    private var scaleX: Float = 1.0
    private var scaleY: Float = 1.0
    private var scaleZ: Float = 1.0
    
    // MARK: - UI Bindings
    @IBOutlet weak private var preview: UIView!
    @IBOutlet weak private var cameraUnavailableLabel: UILabel!
    @IBOutlet weak private var depthSmoothingSwitch: UISwitch!
    @IBOutlet weak private var mixFactorSlider: UISlider!
    @IBOutlet weak private var touchDepth: UILabel!
    @IBOutlet weak private var smoothDepthLabel: UILabel!
    @IBOutlet weak private var cloudView: PointCloudMetalView!
    
    var imageView: UIImageView!
    
    func updatePupillaryDistance() {
        // Step 1: Get 3D positions of both eyes
        // Assuming leftEyePosition3D and rightEyePosition3D are already updated
        // in the ARSessionDelegate methods
        
        // Step 2: Compute the Euclidean distance between the eyes
        let xDistance = rightEyePosition3D.x - leftEyePosition3D.x
        let yDistance = rightEyePosition3D.y - leftEyePosition3D.y
        let zDistance = rightEyePosition3D.z - leftEyePosition3D.z
        let distanceInMeters = sqrt(pow(xDistance, 2) + pow(yDistance, 2) + pow(zDistance, 2))
        
        // Step 3: Convert to millimeters (1 meter = 1000 millimeters)
        let distanceInMillimeters = distanceInMeters * 1000
        
        // Step 4: Update ViewModel
        pupilDistance = Double(distanceInMillimeters)
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
    
    
    func drawEyePositionsOnPixelBuffer(pixelBuffer: CVPixelBuffer, leftEyePosition: CGPoint, rightEyePosition: CGPoint) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let temporaryContext = CIContext(options: nil)
        guard let cgImage = temporaryContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        // Begin a graphics context to draw on
        UIGraphicsBeginImageContext(CGSize(width: cgImage.width, height: cgImage.height))
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Draw the original image as the background
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        // Set up the circle properties
        let circleRadius: CGFloat = 10 // Radius of the circles
        let circleColor = UIColor.red.cgColor
        
        // Function to draw a circle at a given point
        func drawCircle(at point: CGPoint, color: CGColor, radius: CGFloat) {
            let circleRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.setFillColor(color)
            context.fillEllipse(in: circleRect)
        }
        
        // Draw the left and right eye positions
        drawCircle(at: leftEyePosition, color: circleColor, radius: circleRadius)
        drawCircle(at: rightEyePosition, color: circleColor, radius: circleRadius)
        
        // Get the final image
        guard let finalImage = UIGraphicsGetImageFromCurrentImageContext() else { return nil }
        UIGraphicsEndImageContext()
        
        // Convert UIImage back to CVPixelBuffer
        return finalImage.toCVPixelBuffer()
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
    
    private func processFrameAV(depthData: AVDepthData, imageData: CVImageBuffer) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
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
            
            let metadata = PointCloudMetadata(
                yaw: Double(previewYaws.last ?? 0.0),
                pitch: Double(previewRolls.last ?? 0.0),
                roll: Double(previewPitches.last ?? 0.0),
                leftEyePosition: leftEyePosition,
                rightEyePosition: rightEyePosition,
                chinPosition: chinPosition,
                leftEyePosition3D: leftEyePosition3D,
                rightEyePosition3D: rightEyePosition3D,
                chinPosition3D: chinPosition3D,
                image: imageData,
                depth: depthData
            )
            
            ExternalData.pointCloudDataArray.append(metadata)
            
            // Call the point cloud creation function
            ExternalData.convertToSceneKitModel(
                depthData: depthData,
                colorPixelBuffer: colorPixelBuffer!,
                colorData: colorBaseAddress,
                metadata: metadata,
                width: commonWidth,
                height: commonHeight,
                bytesPerRow: colorBytesPerRow, // Use the correct bytes per row for color data,
                scaleX: scaleX,
                scaleY: scaleY,
                scaleZ: scaleZ
            )
        }
    }
    
    func drawEyePositionsOnImage(image: UIImage, leftEyePosition: CGPoint, rightEyePosition: CGPoint) -> UIImage? {
        // Begin a graphics context to draw on
        UIGraphicsBeginImageContextWithOptions(image.size, false, 0)
        image.draw(at: .zero) // Draw the original image as the background
        
        // Set up the circle properties
        let circleRadius: CGFloat = 10 // Radius of the circles
        let circleColor = UIColor.red
        
        // Function to draw a circle at a given point
        func drawCircle(at point: CGPoint, color: UIColor, radius: CGFloat) {
            let circleRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            color.setFill()
            UIRectFill(circleRect)
        }
        
        // Draw the left and right eye positions
        drawCircle(at: leftEyePosition, color: circleColor, radius: circleRadius)
        drawCircle(at: rightEyePosition, color: circleColor, radius: circleRadius)
        
        // Get the final image
        let finalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return finalImage
    }
    
    func findClosest3DPoint(to point2D: CGPoint, within threshold: CGFloat, in depthData: AVDepthData) -> SCNVector3? {
        guard let depthPixelBuffer: CVPixelBuffer? = depthData.depthDataMap,
              let cameraCalibrationData = depthData.cameraCalibrationData else { return nil }
        
        let depthWidth = CVPixelBufferGetWidth(depthPixelBuffer!)
        let depthHeight = CVPixelBufferGetHeight(depthPixelBuffer!)
        
        let scaledPointX = point2D.x * CGFloat(depthWidth)
        let scaledPointY = point2D.y * CGFloat(depthHeight)
        
        scaleX = Float(depthWidth)
        scaleY = Float(depthHeight)
        
        ExternalData.scaleX = scaleX
        ExternalData.scaleY = scaleY
        
        let xInt = min(max(Int(scaledPointX), 0), depthWidth - 1)
        let yInt = min(max(Int(scaledPointY), 0), depthHeight - 1)
        
        let result = calculateClosest3DPoint(xInt: xInt, yInt: yInt, threshold: threshold, depthWidth: depthWidth, depthHeight: depthHeight, depthPixelBuffer: depthPixelBuffer!, cameraIntrinsics: cameraCalibrationData.intrinsicMatrix)
        
        if let result = result {
            return result
        } else {
            // Fallback: trying with inverted signs
            let invertedXInt = depthWidth - 1 - xInt
            let invertedYInt = depthHeight - 1 - yInt
            return calculateClosest3DPoint(xInt: invertedXInt, yInt: invertedYInt, threshold: threshold, depthWidth: depthWidth, depthHeight: depthHeight, depthPixelBuffer: depthPixelBuffer!, cameraIntrinsics: cameraCalibrationData.intrinsicMatrix)
        }
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
        
        configureAVCaptureSession()
        startAVCaptureSession()
        
        configureCloudView()
        // addAndConfigureSwiftUIView()
        
        // Configure imageView
        // configureImageView()
        
        setupEyeNode()
        
        let sessionHandler = SessionHandler(session: avCaptureSession, input: videoDeviceInput!, output: videoDataOutput)
        sessionHandler.openSession()
        
        let layer = sessionHandler.layer
        layer.frame = preview.bounds

        preview.layer.addSublayer(layer)
        
        self.view.bringSubviewToFront(preview)
        
        view.layoutIfNeeded()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
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
        let hostingController = UIHostingController(rootView: ExportView())
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
    
    private func configureAVCaptureSession() {
        // Setup AVCaptureSession but don't start it yet
        guard let videoDevice = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) else {
            print("TrueDepth camera is not available.")
            return
        }
        
        do {
            self.videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            if avCaptureSession.canAddInput(self.videoDeviceInput!) {
                avCaptureSession.addInput(self.videoDeviceInput!)
            }
            
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            if avCaptureSession.canAddOutput(videoDataOutput) {
                avCaptureSession.addOutput(videoDataOutput)
            }
            
            if avCaptureSession.canAddOutput(depthDataOutput) {
                avCaptureSession.addOutput(depthDataOutput)
            }
            
        } catch {
            print("Error configuring AVCaptureSession: \(error)")
        }
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
        
        if ExternalData.isSavingFileAsPLY {
            let depthData = syncedDepthData.depthData
            let sampleBuffer = syncedVideoData.sampleBuffer
            guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            
            processFrameAV(depthData: depthData, imageData: videoPixelBuffer)
            
            // Set cloudView to empty depth data and texture
            // cloudView?.setDepthFrame(nil, withTexture: nil)
            // cloudView?.setDepthFrame(depthData, withTexture: videoPixelBuffer)
            
            ExternalData.isSavingFileAsPLY = false
        }
    }
}
