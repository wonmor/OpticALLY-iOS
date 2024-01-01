//
//  CameraViewController.swift
//  OpticALLY
//
//  Created by John Seong on 9/10/23.
//

import SwiftUI
import UIKit
import ARKit
import SceneKit
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
///

/// Size of the generated face texture
private let faceTextureSize = 1024 //px

/// Should the face mesh be filled in? (i.e. fill in the eye and mouth holes with geometry)
private let fillMesh = true

class CameraViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate, AVCaptureDataOutputSynchronizerDelegate {
    var contentNode: SCNNode?
    
    // MARK: - Class Parameters
    var viewModel: FaceTrackingViewModel?
    
    // MARK: - Properties
    private var arSCNView: ARSCNView?
    private var avCaptureSession: AVCaptureSession = AVCaptureSession()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private var videoDataOutput = AVCaptureVideoDataOutput()
    private var depthDataOutput = AVCaptureDepthDataOutput()
    
    private var faceUvGenerator: FaceTextureGenerator!
    private var scnFaceGeometry: ARSCNFaceGeometry!
    
    /// Secondary scene view that shows the captured face
    private var previewSceneView: SCNView!
    private var previewFaceNode: SCNNode!
    private var previewFaceGeometry: ARSCNFaceGeometry!
    private var previewFaceAnchor: ARFaceAnchor!
    
    private var previewFaceAnchors: [ARFaceAnchor] = []
    
    private var previewYaws: [Float] = []
    private var previewPitches: [Float] = []
    private var previewRolls: [Float] = []
    
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
    
    private var leftEyePosition3D = SCNVector3(0, 0, 0)
    private var rightEyePosition3D = SCNVector3(0, 0, 0)
    private var chinPosition3D = SCNVector3(0, 0, 0)
    
    private var faceGeometry: ARSCNFaceGeometry?
    private var faceNode: SCNNode?
    private var faceAnchor: ARFaceAnchor?
    
    private var scaleX: Float = 1.0
    private var scaleY: Float = 1.0
    private var scaleZ: Float = 1.0
    
    // MARK: - UI Bindings
    @IBOutlet weak private var cameraUnavailableLabel: UILabel!
    @IBOutlet weak private var depthSmoothingSwitch: UISwitch!
    @IBOutlet weak private var mixFactorSlider: UISlider!
    @IBOutlet weak private var touchDepth: UILabel!
    @IBOutlet weak private var smoothDepthLabel: UILabel!
    
    @IBOutlet weak private var cloudView: PointCloudMetalView!
    
    deinit {
        if self.arSCNView != nil {
            pauseARSession()
            print("ARSession Paused")
        }
    }
    
    public func renderer(_: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARFaceAnchor else {
            return nil
        }
        
        let node = SCNNode(geometry: scnFaceGeometry)
        scnFaceGeometry.firstMaterial?.diffuse.contents = faceUvGenerator.texture
        return node
    }
    
    
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
        viewModel?.pupilDistance = Double(distanceInMillimeters)
    }
    
    public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else {
            return
        }
        
        guard let faceAnchor = anchor as? ARFaceAnchor,
              let frame = arSCNView!.session.currentFrame
        else {
            return
        }
        
        let leftEyeTransform = faceAnchor.leftEyeTransform
        let rightEyeTransform = faceAnchor.rightEyeTransform
        
        // Convert the transform to an SCNVector3 for position
        leftEyePosition3D = SCNVector3(leftEyeTransform.columns.3.x, leftEyeTransform.columns.3.y, leftEyeTransform.columns.3.z)
        rightEyePosition3D = SCNVector3(rightEyeTransform.columns.3.x, rightEyeTransform.columns.3.y, rightEyeTransform.columns.3.z)
        
        DispatchQueue.main.async { [self] in
            viewModel?.leftEyePosition3D = leftEyePosition3D
            viewModel?.rightEyePosition3D = rightEyePosition3D
            
            updatePupillaryDistance()
        }
        
        // Update face geometry
        self.previewFaceGeometry.update(from: faceAnchor.geometry)
        
        // Extract the Euler angles from the viewModel
        let yawAngle = viewModel?.faceYawAngle ?? 0.0
        let pitchAngle = viewModel?.facePitchAngle ?? 0.0
        let rollAngle = viewModel?.faceRollAngle ?? 0.0
        
        // Convert angles to radians and then to Float
        let yaw = Float(yawAngle * .pi / 180)
        let pitch = Float(pitchAngle * .pi / 180)
        let roll = Float(rollAngle * .pi / 180)
        
        // Create rotation matrices
        let rotationY = SCNMatrix4MakeRotation(yaw, 0, 1, 0)
        let rotationX = SCNMatrix4MakeRotation(pitch, 1, 0, 0)
        let rotationZ = SCNMatrix4MakeRotation(roll, 0, 0, 1)
        
        // Combine rotations
        let rotation = SCNMatrix4Mult(SCNMatrix4Mult(rotationZ, rotationX), rotationY)
        
        // Set the transform of the previewFaceNode
        self.previewFaceNode.transform = rotation
        
        // Match the world position of the faceAnchor
        let worldTransform = SCNMatrix4(faceAnchor.transform)// Convert simd_float4x4 to SCNMatrix4
        self.previewFaceNode.worldPosition = SCNVector3(worldTransform.m41, worldTransform.m42, worldTransform.m43)
        
        scnFaceGeometry.update(from: faceAnchor.geometry)
        faceUvGenerator.update(frame: frame, scene: self.arSCNView!.scene, headNode: node, geometry: scnFaceGeometry)
        
        self.previewFaceAnchor = faceAnchor
        self.previewFaceAnchors.append(faceAnchor)
        
        self.previewYaws.append(yaw)
        self.previewPitches.append(pitch)
        self.previewRolls.append(roll)
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
                yaw: viewModel?.faceYawAngle ?? 0.0,
                pitch: viewModel?.facePitchAngle ?? 0.0,
                roll: viewModel?.faceRollAngle ?? 0.0,
                leftEyePosition: leftEyePosition,
                rightEyePosition: rightEyePosition,
                chinPosition: chinPosition,
                leftEyePosition3D: leftEyePosition3D,
                rightEyePosition3D: rightEyePosition3D,
                chinPosition3D: chinPosition3D,
                image: imageData,
                depth: depthData,
                faceNode: previewFaceNode,
                faceAnchor: previewFaceAnchors.last!,
                faceTexture: textureToImage(self.faceUvGenerator.texture)!
            )
            
            ExternalData.pointCloudDataArray.append(metadata)
            
            // Call the point cloud creation function
            ExternalData.createAVPointCloudGeometry(
                depthData: depthData,
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
    
    private func detectFaceLandmarks(in pixelBuffer: CVPixelBuffer, sceneView: SCNView, depthData: AVDepthData) {
        try? faceDetectionHandler.perform([faceDetectionRequest], on: pixelBuffer, orientation: .right)
        guard let observations = faceDetectionRequest.results else {
            return
        }
        
        for observation in observations {
            if let leftEye = observation.landmarks?.leftEye, let rightEye = observation.landmarks?.rightEye {
                leftEyePosition = averagePoint(from: leftEye.normalizedPoints, in: observation.boundingBox, pixelBuffer: pixelBuffer)
                rightEyePosition = averagePoint(from: rightEye.normalizedPoints, in: observation.boundingBox, pixelBuffer: pixelBuffer)
                
                print("leftEyePosition: \(leftEyePosition)")
                
                viewModel?.leftEyePosition = leftEyePosition
                viewModel?.rightEyePosition = rightEyePosition
                viewModel?.chinPosition = chinPosition
                
                viewModel?.leftEyePosition3D = leftEyePosition3D
                viewModel?.rightEyePosition3D = rightEyePosition3D
                viewModel?.chinPosition3D = chinPosition3D
            }
        }
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
    
    private func configureARSCNView() {
        arSCNView = ARSCNView(frame: view.bounds)
        arSCNView!.isHidden = false
        view.addSubview(arSCNView!) // Add to view hierarchy
        arSCNView!.session.delegate = self
        arSCNView!.delegate = self
        
        // Initialize face geometry
        if let device = arSCNView?.device {
            self.scnFaceGeometry = ARSCNFaceGeometry(device: self.arSCNView!.device!, fillMesh: fillMesh)
            
            self.faceUvGenerator = FaceTextureGenerator(
                device: self.arSCNView!.device!,
                library: self.arSCNView!.device!.makeDefaultLibrary()!,
                viewportSize: self.view.bounds.size,
                face: self.scnFaceGeometry,
                textureSize: faceTextureSize)
            
            // Initialize and configure previewSceneView
            previewSceneView = SCNView()
            previewSceneView.translatesAutoresizingMaskIntoConstraints = false
            previewSceneView.rendersContinuously = true
            previewSceneView.backgroundColor = UIColor.clear
            previewSceneView.allowsCameraControl = true
            self.view.addSubview(previewSceneView)
            previewSceneView.scene = SCNScene()
            
            // Setup constraints for previewSceneView
            NSLayoutConstraint.activate([
                previewSceneView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                previewSceneView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 20), // Align to top with 20 points of padding
                previewSceneView.widthAnchor.constraint(equalToConstant: 200),
                previewSceneView.heightAnchor.constraint(equalToConstant: 200)
            ])
            
            let camera = SCNCamera()
            camera.fieldOfView = 30
            camera.zNear = 0.001
            camera.zFar = 1000
            
            let cameraNode = SCNNode()
            cameraNode.camera = camera
            cameraNode.position = SCNVector3Make(0, 0, 0.5) // Adjust the z-position to bring the camera closer
            previewSceneView.scene!.rootNode.addChildNode(cameraNode)
            cameraNode.look(at: SCNVector3Zero)
            
            self.previewFaceGeometry = ARSCNFaceGeometry(device: self.arSCNView!.device!, fillMesh: true)
            self.previewFaceNode = SCNNode(geometry: self.previewFaceGeometry)
            let faceScale = Float(4.0)
            self.previewFaceNode.scale = SCNVector3(x: faceScale, y: faceScale, z: faceScale)
            self.previewFaceGeometry.firstMaterial!.diffuse.contents = faceUvGenerator.texture
            self.previewFaceGeometry.firstMaterial!.isDoubleSided = true
            self.previewFaceAnchor = faceAnchor
            
            previewSceneView.scene!.rootNode.addChildNode(self.previewFaceNode!)
        }
    }
    
    private func startARSession() {
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        arSCNView!.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        print("ARSession Running")
        
        // Create a node with face geometry and add it to the scene
        if let faceNode: SCNNode? = SCNNode(geometry: faceGeometry) {
            arSCNView?.scene.rootNode.addChildNode(faceNode!)
        }
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        arSCNView!.session.run(ARFaceTrackingConfiguration(),
                               options: [.removeExistingAnchors,
                                         .resetTracking,
                                         .resetSceneReconstruction,
                                         .stopTrackedRaycasts])
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureARSCNView()
        configureGestureRecognizers()
        configureAVCaptureSession()
        switchSession(toARSession: true)
        
        configureCloudView()
        addAndConfigureSwiftUIView()
        
        self.view.bringSubviewToFront(previewSceneView)
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
            
            self.faceAnchor = faceAnchor
            
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
                        self.detectFaceLandmarks(in: videoPixelBuffer, sceneView: arSCNView!, depthData: depthData)
                        // cloudView.setDepthFrame(depthData, withTexture: videoPixelBuffer)
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
        
        for anchor in anchors {
            if let faceAnchor = anchor as? ARFaceAnchor, let faceGeometry = self.faceGeometry {
                faceGeometry.update(from: faceAnchor.geometry)
            }
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
    
    private func pauseARSession() {
        arSCNView?.session.pause()
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
