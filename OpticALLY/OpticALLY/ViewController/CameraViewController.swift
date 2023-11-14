/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 Contains view controller code for previewing live-captured content.
 */

import UIKit
import AVFoundation
import CoreVideo
import MobileCoreServices
import Accelerate
import SwiftUI
import Vision
import UIKit
import SceneKit
import ARKit
import Combine

class LogManager: ObservableObject {
    static let shared = LogManager()
    private var logs: [String] = []
    @Published var latestLog: String?
    private var timer: Timer?
    
    private init() {
        // Set up a timer that updates `latestLog` every 3 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateLatestLog()
        }
    }
    
    func log(_ message: String) {
        DispatchQueue.main.async {
            self.logs.append(message)
        }
    }
    
    private func updateLatestLog() {
        DispatchQueue.main.async {
            self.latestLog = self.logs.last
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

struct ExternalData {
    static var renderingEnabled = true
    static var isSavingFileAsPLY = false
    static var exportPLYData: Data?
    static var pointCloudGeometry: SCNGeometry?
    
    // Function to convert depth and color data into a point cloud geometry
    static func createPointCloudGeometry(depthData: AVDepthData, colorData: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var colors: [UIColor] = []
        
        let convertedDepthData = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let depthDataMap = convertedDepthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthDataMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthDataMap, .readOnly) }
        
        for y in 0..<height {
            for x in 0..<width {
                let depthOffset = y * CVPixelBufferGetBytesPerRow(depthDataMap) + x * MemoryLayout<Float32>.size
                let depthPointer = CVPixelBufferGetBaseAddress(depthDataMap)!.advanced(by: depthOffset).assumingMemoryBound(to: Float32.self)
                let depth = depthPointer.pointee
                
                // Scale and offset the depth as needed to fit your scene
                let vertex = SCNVector3(x: Float(x), y: Float(y), z: Float(depth))
                
                vertices.append(vertex)
                
                let colorOffset = y * bytesPerRow + x * 4 // Assuming BGRA format
                let bComponent = Double(colorData[colorOffset]) / 255.0
                let gComponent = Double(colorData[colorOffset + 1]) / 255.0
                let rComponent = Double(colorData[colorOffset + 2]) / 255.0
                let aComponent = Double(colorData[colorOffset + 3]) / 255.0
                
                let color = UIColor(red: CGFloat(rComponent), green: CGFloat(gComponent), blue: CGFloat(bComponent), alpha: CGFloat(aComponent))
                colors.append(color)
            }
        }
        
        // Create the geometry source for vertices
        let vertexSource = SCNGeometrySource(vertices: vertices)
        
        // Assuming the UIColor's data is not properly formatted for the SCNGeometrySource
        // Instead, create an array of normalized float values representing the color data
        
        var colorComponents: [CGFloat] = []
        
        var counter = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let colorOffset = y * bytesPerRow + x * 4 // Assuming BGRA format
                let bComponent = CGFloat(colorData[colorOffset]) / 255.0
                let gComponent = CGFloat(colorData[colorOffset + 1]) / 255.0
                let rComponent = CGFloat(colorData[colorOffset + 2]) / 255.0
                let aComponent = CGFloat(colorData[colorOffset + 3]) / 255.0
                
                print("Converting \(counter)th point: \([rComponent, gComponent, bComponent, aComponent])")
                LogManager.shared.log("Converting \(counter)th point: \([rComponent, gComponent, bComponent, aComponent])")
                
                // Append color components in RGBA order, which is typically used in SceneKit
                colorComponents += [rComponent, gComponent, bComponent, aComponent]
                
                counter += 1
            }
        }
        
        let colorData = Data(buffer: UnsafeBufferPointer(start: &colorComponents, count: colorComponents.count))
        let colorSource = SCNGeometrySource(data: colorData,
                                            semantic: .color,
                                            vectorCount: vertices.count,
                                            usesFloatComponents: true,
                                            componentsPerVector: 4,
                                            bytesPerComponent: MemoryLayout<CGFloat>.size,
                                            dataOffset: 0,
                                            dataStride: MemoryLayout<CGFloat>.stride * 4)
        
        // Create the geometry element
        let indices: [Int32] = Array(0..<Int32(vertices.count))
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: indexData,
                                         primitiveType: .point,
                                         primitiveCount: vertices.count,
                                         bytesPerIndex: MemoryLayout<Int32>.size)
        
        // Create the point cloud geometry
        pointCloudGeometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        
        // Set the shader modifier to change the point size
        let pointSize: CGFloat = 5.0 // Adjust the point size as necessary
        let shaderModifier = """
            #pragma transparent
            #pragma body
            gl_PointSize = \(pointSize);
        """
        pointCloudGeometry!.shaderModifiers = [.geometry: shaderModifier]
        
        // Set the lighting model to constant to ensure the points are fully lit
        pointCloudGeometry!.firstMaterial?.lightingModel = .constant
        
        // Set additional material properties as needed, for example, to make the points more visible
        pointCloudGeometry!.firstMaterial?.isDoubleSided = true
        
        print("Done constructing the 3D object!")
        LogManager.shared.log("Done constructing the 3D object!")
        
        return pointCloudGeometry!
    }
    
    static func exportGeometryAsPLY(to url: URL) {
        guard let geometry = pointCloudGeometry,
              let vertexSource = geometry.sources.first(where: { $0.semantic == .vertex }),
              let colorSource = geometry.sources.first(where: { $0.semantic == .color }) else {
            print("Unable to access vertex or color source from geometry")
            return
        }
        
        // Access vertex data
        guard let vertexData: Data? = vertexSource.data else {
            print("Unable to access vertex data")
            return
        }
        
        // Access color data
        guard let colorData: Data? = colorSource.data else {
            print("Unable to access color data")
            return
        }
        
        let vertexCount = vertexSource.vectorCount
        let colorStride = colorSource.dataStride / MemoryLayout<CGFloat>.size
        let vertices = vertexData!.toArray(type: SCNVector3.self, count: vertexCount)
        let colors = colorData!.toArray(type: CGFloat.self, count: vertexCount * colorStride)
        
        var plyString = "ply\n"
        plyString += "format ascii 1.0\n"
        plyString += "element vertex \(vertexCount)\n"
        plyString += "property float x\n"
        plyString += "property float y\n"
        plyString += "property float z\n"
        plyString += "property uchar red\n"
        plyString += "property uchar green\n"
        plyString += "property uchar blue\n"
        plyString += "property uchar alpha\n"
        plyString += "end_header\n"
        
        for i in 0..<vertexCount {
            let vertex = vertices[i]
            let colorIndex = i * colorStride
            
            // Ensure the index is within the bounds of the colors array
            guard colorIndex + 3 < colors.count else {
                print("Color data index out of range for vertex \(i).")
                continue
            }
            
            let color: [UInt8] = (0..<4).compactMap { i -> UInt8? in
                let index = colorIndex + i
                guard index < colors.count else {
                    return nil
                }
                return UInt8(colors[index] * 255)
            }
            
            // Only proceed if we have all four color components
            guard color.count == 4 else {
                print("Incomplete color data for vertex \(i).")
                continue
            }
            
            plyString += "\(vertex.x) \(vertex.y) \(vertex.z) \(color[0]) \(color[1]) \(color[2]) \(color[3])\n"
        }
        
        do {
            try plyString.write(to: url, atomically: true, encoding: .ascii)
            print("PLY file was successfully saved to: \(url.path)")
        } catch {
            print("Failed to write PLY file: \(error)")
        }
    }
}

@available(iOS 11.1, *)
class CameraViewController: UIViewController, AVCaptureDataOutputSynchronizerDelegate {
    
    // MARK: - Properties
    
    @IBOutlet weak private var cameraUnavailableLabel: UILabel!
    
    @IBOutlet weak private var depthSmoothingSwitch: UISwitch!
    
    @IBOutlet weak private var mixFactorSlider: UISlider!
    
    @IBOutlet weak private var touchDepth: UILabel!
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private var setupResult: SessionSetupResult = .success
    
    private let session = AVCaptureSession()
    
    private var isSessionRunning = false
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], autoreleaseFrequency: .workItem)
    private var videoDeviceInput: AVCaptureDeviceInput!
    
    private let dataOutputQueue = DispatchQueue(label: "video data queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    
    private var globalDepthData: AVDepthData!
    private var globalVideoPixelBuffer: CVImageBuffer!
    
    private let videoDepthMixer = VideoMixer()
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera],
                                                                               mediaType: .video,
                                                                               position: .front)
    
    private var statusBarOrientation: UIInterfaceOrientation = .portrait
    
    private var touchDetected = false
    
    private var touchCoordinates = CGPoint(x: 0, y: 0)
    
    @IBOutlet weak private var cloudView: PointCloudMetalView!
    
    @IBOutlet weak private var smoothDepthLabel: UILabel!
    
    private var lastScale = Float(1.0)
    
    private var lastScaleDiff = Float(0.0)
    
    private var lastZoom = Float(0.0)
    
    private var lastXY = CGPoint(x: 0, y: 0)
    
    private var viewFrameSize = CGSize()
    
    private var autoPanningIndex = Int(-1) // start with auto-panning off
    
    // MARK: - View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
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
        sessionQueue.async {
            self.configureSession()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let interfaceOrientation = UIApplication.shared.statusBarOrientation
        statusBarOrientation = interfaceOrientation
        
        let initialThermalState = ProcessInfo.processInfo.thermalState
        
        if initialThermalState == .serious || initialThermalState == .critical {
            // If iPhone is too hot at startup, make it so that it pauses stream after waiting 5 seconds...
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                ExternalData.renderingEnabled = false
            }
            showThermalState(state: initialThermalState)
        }
        
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
                
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
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
    
    override func viewWillDisappear(_ animated: Bool) {
        dataOutputQueue.async {
            ExternalData.renderingEnabled = false
        }
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    @objc
    func didEnterBackground(notification: NSNotification) {
        // Free up resources
        dataOutputQueue.async {
            ExternalData.renderingEnabled = false
            //            if let videoFilter = self.videoFilter {
            //                videoFilter.reset()
            //            }
            self.videoDepthMixer.reset()
        }
    }
    
    @objc
    func willEnterForground(notification: NSNotification) {
        dataOutputQueue.async {
            ExternalData.renderingEnabled = true
        }
    }
    
    // You can use this opportunity to take corrective action to help cool the system down.
    @objc
    func thermalStateChanged(notification: NSNotification) {
        if let processInfo = notification.object as? ProcessInfo {
            if (processInfo.thermalState == .serious || processInfo.thermalState == .critical) {
                ExternalData.renderingEnabled = false
            }
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
            self.sessionQueue.async {
                /*
                 The photo orientation is based on the interface orientation. You could also set the orientation of the photo connection based
                 on the device orientation by observing UIDeviceOrientationDidChangeNotification.
                 */
                let videoOrientation = self.videoDataOutput.connection(with: .video)!.videoOrientation
            }
        }, completion: nil)
    }
    
    // MARK: - KVO and Notifications
    
    private var sessionRunningContext = 0
    
    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification,	object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError),
                                               name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
        
        session.addObserver(self, forKeyPath: "running", options: NSKeyValueObservingOptions.new, context: &sessionRunningContext)
        
        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted),
                                               name: NSNotification.Name.AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded),
                                               name: NSNotification.Name.AVCaptureSessionInterruptionEnded,
                                               object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange),
                                               name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange,
                                               object: videoDeviceInput.device)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        session.removeObserver(self, forKeyPath: "running", context: &sessionRunningContext)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if context != &sessionRunningContext {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
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
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            return
        }
        
        session.beginConfiguration()
        
        session.sessionPreset = AVCaptureSession.Preset.vga640x480
        
        // Add a video input
        guard session.canAddInput(videoDeviceInput) else {
            print("Could not add video device input to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        session.addInput(videoDeviceInput)
        
        // Add a video data output
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        } else {
            print("Could not add video data output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add a depth data output
        if session.canAddOutput(depthDataOutput) {
            session.addOutput(depthDataOutput)
            depthDataOutput.isFilteringEnabled = true
            if let connection = depthDataOutput.connection(with: .depthData) {
                connection.isEnabled = true
            } else {
                print("No AVCaptureConnection")
            }
        } else {
            print("Could not add depth data output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
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
            session.commitConfiguration()
            return
        }
        
        // Use an AVCaptureDataOutputSynchronizer to synchronize the video data and depth data outputs.
        // The first output in the dataOutputs array, in this case the AVCaptureVideoDataOutput, is the "master" output.
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
        outputSynchronizer!.setDelegate(self, queue: dataOutputQueue)
        session.commitConfiguration()
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
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
    
    @IBAction private func changeMixFactor(_ sender: UISlider) {
        let mixFactor = sender.value
        
        dataOutputQueue.async {
            self.videoDepthMixer.mixFactor = mixFactor
        }
    }
    
    @IBAction private func changeDepthSmoothing(_ sender: UISwitch) {
        let smoothingEnabled = sender.isOn
        
        sessionQueue.async {
            self.depthDataOutput.isFilteringEnabled = smoothingEnabled
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
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }
    
    @IBAction private func resumeInterruptedSession(_ sender: UIButton) {
        sessionQueue.async {
            /*
             The session might fail to start running. A failure to start the session running will be communicated via
             a session runtime error notification. To avoid repeatedly failing to start the session
             running, we only try to restart the session running in the session runtime error handler
             if we aren't trying to resume the session running.
             */
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "TrueDepthStreamer", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
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
        cloudView.resetView()
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
    
    func printDepthData(depthData: AVDepthData, imageData: CVImageBuffer) {
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
        
        print("Starting iteration with commonWidth: \(commonWidth), commonHeight: \(commonHeight)")
        
        // Iterate over the image buffer
        for y in stride(from: 0, to: commonHeight, by: 10) {
            for x in stride(from: 0, to: commonWidth, by: 10) {
                let colorPixelOffset = y * colorBytesPerRow + x * colorBytesPerPixel
                let colorPixel = colorData.advanced(by: colorPixelOffset).assumingMemoryBound(to: UInt8.self)
                
                // Extract BGRA components
                let blue = colorPixel[0]
                let green = colorPixel[1]
                let red = colorPixel[2]
                let alpha = colorPixel[3]
                
                // Print the (x, y) coordinates and color value in BGRA
                print("Color at (\(x), \(y)): B:\(blue) G:\(green) R:\(red) A:\(alpha)")
                
                // Calculate the depth data's corresponding pixel offset
                let depthPixelOffset = y * depthBytesPerRow + x * depthBytesPerPixel
                let depthPixel = depthDataAddress.advanced(by: depthPixelOffset).assumingMemoryBound(to: Float.self)
                let depthValue = depthPixel.pointee
                
                // Print the (x, y) coordinates and depth value
                print("Depth at (\(x), \(y)): \(depthValue)")
            }
        }
        
        print("Completed iteration")
        
        // Assuming colorData is the base address for the BGRA image buffer
        let colorBaseAddress = CVPixelBufferGetBaseAddress(colorPixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        
        // Call the point cloud creation function
        let pointCloudGeometry = ExternalData.createPointCloudGeometry(
            depthData: depthData,
            colorData: colorBaseAddress,
            width: commonWidth,
            height: commonHeight,
            bytesPerRow: colorBytesPerRow // Use the correct bytes per row for color data
        )
        
        // Synchronize access to the shared resource
        DispatchQueue.main.async {
            ExternalData.renderingEnabled.toggle()
        }
    }
    
    // MARK: - Video + Depth Frame Processing
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        if !ExternalData.renderingEnabled {
            return
        }
        
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
            printDepthData(depthData: depthData, imageData: videoPixelBuffer)
            
            // Set cloudView to empty depth data and texture
            // cloudView?.setDepthFrame(nil, withTexture: nil)
            
            ExternalData.isSavingFileAsPLY = false
        }
        
        globalDepthData = depthData
        globalVideoPixelBuffer = videoPixelBuffer
        
        cloudView?.setDepthFrame(depthData, withTexture: videoPixelBuffer)
    }
    
    @IBSegueAction func embedSwiftUIView(_ coder: NSCoder) -> UIViewController? {
        // Upon Scan Completion...
        let hostingController = UIHostingController(coder: coder, rootView: SwiftUIView())!
        hostingController.view.backgroundColor = .clear
        return hostingController
    }
}

enum CurrentState {
    case begin, start
}

// ViewModel to handle the export and share
class ExportViewModel: ObservableObject {
    @Published var fileURL: URL?
    @Published var showShareSheet = false
    
    var objcExporter: PointCloudMetalView // Replace with your actual Objective-C class name

    init() {
        objcExporter = PointCloudMetalView() // Initialize the Objective-C class
    }
    
    func exportPLY(completion: @escaping () -> Void) {
        // Determine a temporary file URL to save the PLY file
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("model.ply")
        
        // Export the PLY data to the file
        ExternalData.exportGeometryAsPLY(to: fileURL)
        
        objcExporter.exportPointCloudPLY {
            // This will be called when the export is completed
            completion()
        }
//        // Update the state to indicate that there's a file to share
//        DispatchQueue.main.async {
//            self.fileURL = fileURL
//            self.showShareSheet = true
//        }
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

struct SwiftUIView: View {
    @State private var isViewLoaded: Bool = false
    @State private var fingerOffset: CGFloat = -30.0
    @State private var isAnimationActive: Bool = true
    @State private var currentState: CurrentState = .begin
    @State private var isScanComplete: Bool = false
    @State private var showDropdown: Bool = false
    @State private var showConsoleOutput: Bool = false
    
    @ObservedObject var logManager = LogManager.shared
    @EnvironmentObject var globalState: GlobalState
    @StateObject private var exportViewModel = ExportViewModel()
    
    let maxOffset: CGFloat = 30.0 // change this to control how much the finger moves
    
    var body: some View {
        ZStack {
            switch currentState {
            case .begin:
                VStack {
                    // Animated finger image
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .frame(width: 150, height: 50)
                            .foregroundColor(Color.black)
                        
                        Image(systemName: "hand.point.up.left")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                            .offset(x: fingerOffset)
                            .onAppear() {
                                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                                    fingerOffset = maxOffset
                                }
                            }
                    }
                    
                    if showConsoleOutput {
                        ScrollView {
                            if let lastLog = logManager.latestLog {
                                Text(lastLog)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .multilineTextAlignment(.center)
                                    .monospaced()
                            }
                        }
                        .onDisappear {
                            logManager.stopTimer()
                        }
                        
                    } else {
                        ScrollView {
                            Text("HAROLDEN\n3D CAPTURE")
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .monospaced()
                        }
                    }
                    
                    // Button to start/pause scanning
                    Button(action: {
                        showConsoleOutput = true
                        
                        ExternalData.isSavingFileAsPLY = true
                    }) {
                        if showConsoleOutput {
                            if let lastLog = logManager.latestLog {
                                if lastLog.lowercased().contains("done") {
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
                                        
                                        // Dropdown list view
                                        if showDropdown {
                                            VStack {
                                                Button(action: {
                                                    exportViewModel.exportPLY {
                                                        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                                                                let plyFilePath = documentsPath.appendingPathComponent("pointcloud.ply")
                                                            
                                                                if FileManager.default.fileExists(atPath: plyFilePath.path) {
                                                                    DispatchQueue.main.async {
                                                                        let activityViewController = UIActivityViewController(activityItems: [plyFilePath], applicationActivities: nil)
                                                                        // Present the share sheet
                                                                        if let viewController = UIApplication.shared.windows.first?.rootViewController {
                                                                            viewController.present(activityViewController, animated: true, completion: nil)
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                    }
                                                }) {
                                                    Text(".PLY")
                                                        .padding()
                                                        .foregroundColor(.white)
                                                        .background(Capsule().fill(Color.gray.opacity(0.4)))
                                                }
                                            }
                                            .padding(.top, 5)
                                            .sheet(isPresented: $exportViewModel.showShareSheet, onDismiss: {
                                                exportViewModel.showShareSheet = false
                                            }) {
                                                // This will present the share sheet
                                                if let fileURL = exportViewModel.fileURL {
                                                    ShareSheet(fileURL: fileURL)
                                                }
                                            }
                                            
                                        } else {
                                            Button(action: {
                                                globalState.currentView = .postScanning
                                            }) {
                                                HStack {
                                                    Image(systemName: "checkmark.circle.fill")
                                                    Text("CONTINUE")
                                                        .font(.body)
                                                        .bold()
                                                }
                                                .padding()
                                                .foregroundColor(.white)
                                                .background(Capsule().fill(Color.black).overlay(Capsule().stroke(Color.white, lineWidth: 2)))
                                            }
                                        }
                                        
                                    }
                                    .padding()
                                } else {
                                    HStack {
                                        Image(systemName: "circle.dotted") // Different SF Symbols for start and pause
                                        Text("READING...")
                                            .font(.title3)
                                            .bold()
                                    }
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Capsule().fill(Color.black).overlay(Capsule().stroke(Color.white, lineWidth: 2)))
                                }
                            }
                        } else {
                            HStack {
                                Image(systemName: "play.circle") // Different SF Symbols for start and pause
                                Text("SCAN")
                                    .font(.title3)
                                    .bold()
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Capsule().fill(Color.black).overlay(Capsule().stroke(Color.white, lineWidth: 2)))
                        }
                    }
                }
                
            case .start:
                VStack {
                    Button(action: {
                        ExternalData.renderingEnabled.toggle()
                        currentState = .begin
                        isScanComplete = false
                    }) {
                        HStack {
                            Image(systemName: "arrow.left") // Using system arrow left image for back
                            Text("Back")
                        }
                        .padding()
                        .foregroundColor(.primary) // Adjust color as needed
                    }
                    .navigationBarItems(leading:
                                            Button(action: {
                        // Handle your back action here
                    }) {
                        Image(systemName: "arrow.left")
                    }
                    )
                    
                    Image("1024")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 20)) // Clips the image as a rounded rectangle
                        .overlay(
                            RoundedRectangle(cornerRadius: 20) // Applies a border on top of the rounded rectangle image
                                .stroke(Color.primary, lineWidth: 2) // Adjust the color and line width as needed
                        )
                        .accessibility(hidden: true)
                    
                    Text("HAROLDEN")
                        .bold()
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .padding(.bottom)
                    
                    FaceIDScanView(isScanComplete: $isScanComplete, showDropdown: $showDropdown)
                        .background(Color.black.opacity(0.8).blur(radius: 40.0))
                    
                    if isScanComplete {
                        VStack {
                            Button(action: {
                                // Toggle the dropdown
                                showDropdown.toggle()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.down.circle")
                                    Text("DOWNLOAD")
                                        .font(.body)
                                        .bold()
                                }
                                .foregroundColor(.black)
                                .padding()
                                .background(Capsule().fill(Color.white))
                            }
                            
                            // Dropdown list view
                            if showDropdown {
                                VStack {
                                    Button(action: {
                                        
                                    }) {
                                        Text(".PLY")
                                            .padding()
                                            .foregroundColor(.white)
                                            .background(Capsule().fill(Color.gray.opacity(0.4)))
                                    }
                                }
                                .padding(.top, 5)
                                
                            } else {
                                Button(action: {
                                    ExternalData.renderingEnabled.toggle()
                                    currentState = .begin
                                    isScanComplete = false
                                }) {
                                    Text("RESCAN")
                                        .font(.body)
                                        .bold()
                                        .foregroundColor(.white)
                                        .padding()
                                }
                                .background(Color.black.opacity(0.8).blur(radius: 40.0))
                            }
                            
                        }
                        .padding()
                        
                    } else {
                        Text("For an accurate scan, ensure you pan around the sides, top, and bottom of your face.")
                            .font(.caption)
                            .bold()
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                            .foregroundColor(.white)
                    }
                    
                }
                .background(isScanComplete ? Color.clear.blur(radius: 40.0) : Color.black.opacity(0.8).blur(radius: 40.0))
            }
        }
        .padding()
        .onAppear {
            // Make it pause due to thermal concerns...
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                ExternalData.renderingEnabled = false
            }
        }
    }
}

struct FaceIDScanView: View {
    @Binding var isScanComplete: Bool
    @Binding var showDropdown: Bool
    
    @State private var isAnimating: Bool = false
    @StateObject private var cameraDelegate = CameraDelegate()
    
    var body: some View {
        if cameraDelegate.isComplete {
            Spacer()
                .onAppear {
                    isScanComplete = true
                }
        } else {
            ZStack {
                CameraPreview(session: $cameraDelegate.session)
                    .clipShape(Circle())
                    .frame(width: 200, height: 200)
                
                Circle()
                    .trim(from: 0, to: CGFloat(cameraDelegate.rotationPercentage))
                    .stroke(Color.green, lineWidth: 5)
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(cameraDelegate.isFaceDetected ? 360 : 0))
                    .onAppear {
                        withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                            isAnimating.toggle()
                        }
                    }
                
                if !cameraDelegate.isFaceDetected {
                    Image(systemName: "face.dashed")
                        .foregroundColor(.white)
                        .font(.system(size: 75))
                        .background(Color.black.opacity(0.8).blur(radius: 20.0))
                }
                
                // Draw face landmarks
                ForEach(cameraDelegate.faceLandmarks, id: \.self) { face in
                    Path { path in
                        if let leftEye: CGPoint? = face.leftEyePosition {
                            path.addEllipse(in: CGRect(x: leftEye!.x - 5, y: leftEye!.y - 5, width: 10, height: 10))
                        }
                        if let rightEye: CGPoint? = face.rightEyePosition {
                            path.addEllipse(in: CGRect(x: rightEye!.x - 5, y: rightEye!.y - 5, width: 10, height: 10))
                        }
                        // Add more landmarks as needed
                    }
                    .stroke(Color.green, lineWidth: 2)
                }
                
                // Display face shape
                if !showDropdown {
                    VStack {
                        Spacer()
                        
                        Text(cameraDelegate.faceShape?.rawValue ?? "Determining")
                            .foregroundColor(.white)
                            .font(.title)
                            .fontWeight(.semibold)
                        
                        Text("FACE PROFILE")
                            .bold()
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .padding(.bottom, 20)
                    }
                }
            }
            .onAppear(perform: cameraDelegate.setupCamera)
        }
    }
}


struct CameraPreview: UIViewControllerRepresentable {
    @Binding var session: AVCaptureSession
    
    func makeUIViewController(context: Context) -> CameraPreviewController {
        let controller = CameraPreviewController()
        controller.session = session
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraPreviewController, context: Context) {
        // Nothing to update
    }
}

class CameraPreviewController: UIViewController {
    var session: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }
}

class CameraDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isFaceDetected: Bool = false
    @Published var rotationPercentage: Double = 0
    @Published var isComplete: Bool = false
    @Published var faceLandmarks: [CIFaceFeature] = []
    @Published var faceShape: FaceShape? = nil
    
    var stillImageOutput: AVCaptureStillImageOutput!
    
    private var computeFaceShapeWorkItem: DispatchWorkItem?
    
    enum FaceShape: String {
        case oval = "Oval"
        case square = "Square"
        case rectangle = "Rectangle"
        case round = "Round"
        case triangle = "Triangle"
        case diamond = "Diamond"
    }
    
    func computeFaceShape(from faces: [CIFaceFeature]) {
        guard let face = faces.first else {
            faceShape = nil
            return
        }
        
        let faceWidth = face.bounds.width
        let faceLength = face.bounds.height
        
        // Detecting aspect ratio
        let aspectRatio = faceLength / faceWidth
        
        print("Face Aspect Ratio: \(aspectRatio)")
        
        // Using a threshold to decide the face shape based on the aspect ratio and position of landmarks
        if aspectRatio < 1.2 {
            if let leftEye: CGPoint? = face.leftEyePosition, let rightEye: CGPoint? = face.rightEyePosition {
                let eyeWidth = abs(leftEye!.x - rightEye!.x)
                
                if eyeWidth / faceWidth > 0.5 {
                    faceShape = .round
                } else {
                    faceShape = .square
                }
            }
        } else if aspectRatio < 1.5 {
            faceShape = .oval
        } else if aspectRatio >= 1.5 {
            faceShape = .rectangle
        }
        
        // If there are landmarks available, modify the classification based on their positions
        if let leftEye: CGPoint? = face.leftEyePosition, let rightEye: CGPoint? = face.rightEyePosition, let mouthPosition: CGPoint? = face.mouthPosition {
            let eyeCenterY = (leftEye!.y + rightEye!.y) / 2.0
            let topThird = face.bounds.minY + faceLength * (2.0/3.0)
            let bottomThird = face.bounds.minY + faceLength * (1.0/3.0)
            
            if eyeCenterY > topThird {
                faceShape = .triangle
            } else if mouthPosition!.y < bottomThird {
                faceShape = .diamond
            }
        }
    }
    
    var session = AVCaptureSession()
    private var lastFaceBounds: CGRect? = nil
    
    func setupCamera() {
        session.sessionPreset = .photo
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Unable to access the camera!")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            if session.canAddInput(input) {
                session.addInput(input)
                
                let metadataOutput = AVCaptureMetadataOutput()
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                if session.canAddOutput(metadataOutput) {
                    session.addOutput(metadataOutput)
                    metadataOutput.metadataObjectTypes = [.face]
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.session.startRunning()
                    }
                }
            }
        } catch {
            print(error.localizedDescription)
        }
        // Add video data output
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }
        
        stillImageOutput = AVCaptureStillImageOutput()
        if session.canAddOutput(stillImageOutput) {
            session.addOutput(stillImageOutput)
        }
    }
    
    // Handle video frames and detect face landmarks
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        
        let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let faces = faceDetector?.features(in: ciImage) as? [CIFaceFeature] ?? []
        
        DispatchQueue.main.async {
            self.faceLandmarks = faces
            
            // Cancel the previous work item if it's still pending
            self.computeFaceShapeWorkItem?.cancel()
            
            // Create a new work item and dispatch it after a delay
            let workItem = DispatchWorkItem { [weak self] in
                self?.computeFaceShape(from: faces)
            }
            self.computeFaceShapeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)  // 0.5 second delay for debouncing
        }
    }
    
    func captureStillImage(completion: @escaping (CIImage?) -> Void) {
        guard let videoConnection = stillImageOutput.connection(with: .video) else { return }
        
        stillImageOutput.captureStillImageAsynchronously(from: videoConnection) { (sampleBuffer, error) in
            guard let sampleBuffer = sampleBuffer, let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer) else {
                completion(nil)
                return
            }
            
            let image = UIImage(data: imageData)
            completion(CIImage(image: image!))
        }
    }
    
    func detectFaceShape(from ciImage: CIImage) {
        let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let faces = faceDetector?.features(in: ciImage) as? [CIFaceFeature] ?? []
        if let face = faces.first {
            DispatchQueue.main.async {
                self.computeFaceShape(from: [face])
            }
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let faceObject = metadataObjects.first(where: { $0.type == .face }) as? AVMetadataFaceObject else {
            isFaceDetected = false
            return
        }
        
        isFaceDetected = true
        
        // If face is detected and we haven't computed the face shape yet, capture a still image
        if faceShape == nil {
            captureStillImage { image in
                if let ciImage = image {
                    self.detectFaceShape(from: ciImage)
                }
            }
        }
        
        if let lastBounds = lastFaceBounds {
            let movement = faceObject.bounds.origin.x - lastBounds.origin.x
            rotationPercentage += Double(abs(movement))
            if rotationPercentage >= 1 {
                rotationPercentage = 1
                isComplete = true
            }
        }
        
        lastFaceBounds = faceObject.bounds
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

