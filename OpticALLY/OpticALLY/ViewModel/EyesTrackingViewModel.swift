//
//  EyesTrackingViewModel.swift
//  OpticALLY
//
//  Created by John Seong on 9/11/23.
//

import SwiftUI
import Combine
import ARKit
import Combine

/// `EyesTrackingViewModel` manages and processes AR face tracking data, focusing on tracking eye movement
/// and identifying where a user is looking on a virtual phone screen. It offers real-time feedback on the user's
/// gaze position on a screen and their distance from the device.
///
/// Use this class to initialize and run an AR session with face tracking configuration and pause the session as needed.
///
/// ```
/// let viewModel = EyesTrackingViewModel()
/// viewModel.startSession() // Starts AR face tracking session
/// viewModel.pauseSession() // Pauses the ongoing AR session
/// ```
///
/// > Warning: Ensure AR face tracking is supported on the device before starting the session.
///
/// - Properties:
///     - `eyePosition`: Current eye position represented as a `CGPoint`.
///     - `distanceText`: Approximate distance (in centimeters) of the user's eyes from the device.
///     - `lookAtPositionXText` & `lookAtPositionYText`: X and Y coordinates of user's gaze on the virtual phone screen.
///     - `eyePositionIndicatorTransform`: Current position of eye tracking indicator on screen as a `CGAffineTransform`.
///
/// - Methods:
///     - `startSession()`: Initializes and runs the AR session with face tracking configuration.
///     - `pauseSession()`: Pauses the ongoing AR session.
///     - `update(withFaceAnchor:)`: Updates and processes the latest face anchor data, calculates eye look-at positions, and updates related properties.
///
/// - Conformances:
///     - `ARSCNViewDelegate`: Allows the class to respond to AR Scene View events.
///     - `ARSessionDelegate`: Allows the class to respond to AR session changes.

class EyesTrackingViewModel: NSObject, ObservableObject, ARSCNViewDelegate, ARSessionDelegate {
    @Published var leftEyePosition: CGPoint = .zero
    @Published var rightEyePosition: CGPoint = .zero
    
    @Published var distanceText: String = ""
    
    @Published var lookAtPositionXText: String = ""
    @Published var lookAtPositionYText: String = ""
    
    @Published var sideLength: CGFloat = 0.0
    
    // Additional Published properties for bindings:
    @Published var eyePositionIndicatorTransform: CGAffineTransform = .identity
    
    private var rightEyePositionSubject = PassthroughSubject<CGPoint, Never>()
    private var leftEyePositionSubject = PassthroughSubject<CGPoint, Never>()
    
    private var cancellables: Set<AnyCancellable> = []
    
    private func setupDebounce() {
        rightEyePositionSubject
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main) // debounce by 100ms, adjust as needed
            .sink { [weak self] newPosition in
                self?.rightEyePosition = newPosition
            }
            .store(in: &cancellables)
        
        leftEyePositionSubject
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] newPosition in
                self?.leftEyePosition = newPosition
            }
            .store(in: &cancellables)
    }
    
    func updateRightEyePosition(_ newPosition: CGPoint) {
        rightEyePositionSubject.send(newPosition)
    }
    
    func updateLeftEyePosition(_ newPosition: CGPoint) {
        leftEyePositionSubject.send(newPosition)
    }
    
    private var faceGeometry: ARFaceGeometry?
    private var faceNode: SCNNode = SCNNode()
    private var eyeLNode: SCNNode = {
        let geometry = SCNCone(topRadius: 0.005, bottomRadius: 0, height: 0.2)
        geometry.radialSegmentCount = 3
        geometry.firstMaterial?.diffuse.contents = UIColor.blue
        let node = SCNNode()
        node.geometry = geometry
        node.eulerAngles.x = -.pi / 2
        node.position.z = 0.1
        let parentNode = SCNNode()
        parentNode.addChildNode(node)
        return parentNode
    }()
    
    private var eyeRNode: SCNNode = {
        let geometry = SCNCone(topRadius: 0.005, bottomRadius: 0, height: 0.2)
        geometry.radialSegmentCount = 3
        geometry.firstMaterial?.diffuse.contents = UIColor.blue
        let node = SCNNode()
        node.geometry = geometry
        node.eulerAngles.x = -.pi / 2
        node.position.z = 0.1
        let parentNode = SCNNode()
        parentNode.addChildNode(node)
        return parentNode
    }()
    private var lookAtTargetEyeLNode: SCNNode = SCNNode()
    private var lookAtTargetEyeRNode: SCNNode = SCNNode()
    private let phoneScreenSize = CGSize(width: 0.0623908297, height: 0.135096943231532)
    private let phoneScreenPointSize = CGSize(width: 375, height: 812)
    private var virtualPhoneNode: SCNNode = SCNNode()
    private var virtualScreenNode: SCNNode = {
        let screenGeometry = SCNPlane(width: 1, height: 1)
        screenGeometry.firstMaterial?.isDoubleSided = true
        screenGeometry.firstMaterial?.diffuse.contents = UIColor.green
        
        return SCNNode(geometry: screenGeometry)
    }()
    private var eyeLookAtPositionXs: [CGFloat] = []
    private var eyeLookAtPositionYs: [CGFloat] = []
    
    private var session: ARSession!
    
    override init() {
        super.init()
        self.session = ARSession()
        self.session.delegate = self
        setupDebounce()
    }
    
    private func computeLookAtPoint(from eyeTransform: simd_float4x4, to targetTransform: simd_float4x4) -> CGPoint? {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        let scaleFactor = Constants.scaleFactorForEyeImagePos + screenWidth / 2
        
        // Compute a ray starting from the eye and pointing forward from the eye
        let eyePosition = SIMD3<Float>(eyeTransform.columns.3.x * Float(scaleFactor) , eyeTransform.columns.3.y * Float(scaleFactor), eyeTransform.columns.3.z * Float(scaleFactor))
        let eyeDirection = SIMD3<Float>(-eyeTransform.columns.2.x, -eyeTransform.columns.2.y, -eyeTransform.columns.2.z)
        
        // For simplicity, assume the virtual phone screen is a plane at z = 0 (in the phone's coordinate system).
        // This may not be accurate depending on the actual setup. Adjust as necessary.
        let planeNormal = SIMD3<Float>(0, 0, 1)
        
        // The intersection point of the ray with the plane gives the gaze position
        if let intersection = rayPlaneIntersection(rayOrigin: eyePosition, rayDirection: eyeDirection, planePoint: SIMD3<Float>(0, 0, 0), planeNormal: planeNormal) {
            return CGPoint(x: CGFloat(intersection.x), y: CGFloat(intersection.y))
        }
        return nil
    }
    
    private func rayPlaneIntersection(rayOrigin: SIMD3<Float>, rayDirection: SIMD3<Float>, planePoint: SIMD3<Float>, planeNormal: SIMD3<Float>) -> SIMD3<Float>? {
        let dotNumerator = planePoint - rayOrigin
        let dotD = dot(planeNormal, dotNumerator)
        let dotR = dot(planeNormal, rayDirection)
        if abs(dotR) < 0.0001 {
            // Nearly parallel
            return nil
        }
        let t = dotD / dotR
        return rayOrigin + rayDirection * t
    }
    
    /// Creates A GLKVector3 From a Simd_Float4
    ///
    /// - Parameter transform: simd_float4
    /// - Returns: GLKVector3
    func glkVector3FromARFaceAnchorTransform(_ transform: simd_float4) -> GLKVector3{
        return GLKVector3Make(transform.x, transform.y, transform.z)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        faceNode.transform = node.transform
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        update(withFaceAnchor: faceAnchor)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        virtualPhoneNode.transform = (renderer as! ARSCNView).pointOfView!.transform
    }
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let sceneView = renderer as? ARSCNView else { return nil }
        if let faceAnchor = anchor as? ARFaceAnchor {
            let faceMesh = ARSCNFaceGeometry(device: sceneView.device!)
            let node = SCNNode(geometry: faceMesh)
            node.geometry?.firstMaterial?.fillMode = .lines
            return node
        }
        return nil
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        faceNode.transform = node.transform
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        
        if let leftEyeLookAt = computeLookAtPoint(from: faceAnchor.leftEyeTransform, to: virtualPhoneNode.simdTransform) {
            DispatchQueue.main.async {
                self.updateLeftEyePosition(leftEyeLookAt)
                print("Left Eye Gaze Position: \(leftEyeLookAt)")
            }
        }
        
        if let rightEyeLookAt = computeLookAtPoint(from: faceAnchor.rightEyeTransform, to: virtualPhoneNode.simdTransform) {
            DispatchQueue.main.async {
                self.updateRightEyePosition(rightEyeLookAt)
                print("Right Eye Gaze Position: \(rightEyeLookAt )")
            }
        }
        
        //2. Get The Position Of The Left & Right Eyes
        let leftEyePositionLocal = glkVector3FromARFaceAnchorTransform(faceAnchor.leftEyeTransform.columns.3)
        let rightEyePositionLocal = glkVector3FromARFaceAnchorTransform(faceAnchor.rightEyeTransform.columns.3)
        
        //3. Calculate The Distance Between Them
        let distanceBetweenEyesInMetres = GLKVector3Distance(leftEyePositionLocal, rightEyePositionLocal)
        let distanceBetweenEyesInMM = Int(round(distanceBetweenEyesInMetres * 100 * 10))
        
        // TO DO: Update left/rightEyePosition @Published var...
        
        print("The Distance Between The Eyes Is Approximatly \(distanceBetweenEyesInMM)")
        
        DispatchQueue.main.async {
            self.distanceText = "\(distanceBetweenEyesInMM) mm"
        }
        
        update(withFaceAnchor: faceAnchor)
    }
    
    func update(withFaceAnchor anchor: ARFaceAnchor) {
        // Store face geometry data
        faceGeometry = anchor.geometry
        
        // Access vertices for depth data
        let vertices = faceGeometry?.vertices
        
        // Adjust the gaze direction using depth data if necessary. This might involve creating a more complex 3D representation of the face and adjusting the direction from the eyes.
        // This is a placeholder. The actual implementation would be more involved and requires testing.
        let depthAdjustment = vertices?.first?.z ?? 0
        
        eyeRNode.simdTransform = anchor.rightEyeTransform
        eyeLNode.simdTransform = anchor.leftEyeTransform
        
        var eyeLLookAt = CGPoint()
        var eyeRLookAt = CGPoint()
        
        let heightCompensation: CGFloat = 312
        
        DispatchQueue.main.async {
            
            // Perform Hit test using the ray segments that are drawn by the center of the eyeballs to somewhere two meters away at direction of where users look at to the virtual plane that place at the same orientation of the phone screen
            
            let phoneScreenEyeRHitTestResults = self.virtualPhoneNode.hitTestWithSegment(from: self.lookAtTargetEyeRNode.worldPosition, to: self.eyeRNode.worldPosition, options: nil)
            
            let phoneScreenEyeLHitTestResults = self.virtualPhoneNode.hitTestWithSegment(from: self.lookAtTargetEyeLNode.worldPosition, to: self.eyeLNode.worldPosition, options: nil)
            
            // Now when calculating the position on the virtual phone, consider the depth adjustment. This is a simple representation; the actual depth-based adjustment might be more complex.
            eyeRLookAt.x += CGFloat(depthAdjustment)
            eyeLLookAt.y += CGFloat(depthAdjustment)
            
            for result in phoneScreenEyeRHitTestResults {
                eyeRLookAt.x = CGFloat(result.localCoordinates.x) / (self.phoneScreenSize.width / 2) * self.phoneScreenPointSize.width
                
                eyeRLookAt.y = CGFloat(result.localCoordinates.y) / (self.phoneScreenSize.height / 2) * self.phoneScreenPointSize.height + heightCompensation
            }
            
            for result in phoneScreenEyeLHitTestResults {
                
                eyeLLookAt.x = CGFloat(result.localCoordinates.x) / (self.phoneScreenSize.width / 2) * self.phoneScreenPointSize.width
                
                eyeLLookAt.y = CGFloat(result.localCoordinates.y) / (self.phoneScreenSize.height / 2) * self.phoneScreenPointSize.height + heightCompensation
            }
            
            // Add the latest position and keep up to 8 recent position to smooth with.
            let smoothThresholdNumber: Int = 10
            self.eyeLookAtPositionXs.append((eyeRLookAt.x + eyeLLookAt.x) / 2)
            self.eyeLookAtPositionYs.append(-(eyeRLookAt.y + eyeLLookAt.y) / 2)
            self.eyeLookAtPositionXs = Array(self.eyeLookAtPositionXs.suffix(smoothThresholdNumber))
            self.eyeLookAtPositionYs = Array(self.eyeLookAtPositionYs.suffix(smoothThresholdNumber))
            
            let smoothEyeLookAtPositionX = self.eyeLookAtPositionXs.average!
            let smoothEyeLookAtPositionY = self.eyeLookAtPositionYs.average!
            
            // Update indicator position
            self.eyePositionIndicatorTransform = CGAffineTransform(translationX: smoothEyeLookAtPositionX, y: smoothEyeLookAtPositionY)
            
            // Update eye look at labels values
            self.lookAtPositionXText = "\(Int(round(smoothEyeLookAtPositionX + self.phoneScreenPointSize.width / 2)))"
            self.lookAtPositionYText = "\(Int(round(smoothEyeLookAtPositionY + self.phoneScreenPointSize.height / 2)))"
        }
    }
}
