//
//  EyesTrackingViewModel.swift
//  OpticALLY
//
//  Created by John Seong on 9/11/23.
//

import Foundation
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
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        faceNode.transform = node.transform
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        
        //2. Get The Position Of The Left & Right Eyes
        let leftEyePosition = glkVector3FromARFaceAnchorTransform(faceAnchor.leftEyeTransform.columns.3)
        let righEyePosition = glkVector3FromARFaceAnchorTransform(faceAnchor.rightEyeTransform.columns.3)
        
        self.leftEyePosition = CGPoint(x: CGFloat(leftEyePosition.x), y: CGFloat(leftEyePosition.y))
        self.rightEyePosition = CGPoint(x: CGFloat(rightEyePosition.x), y: CGFloat(rightEyePosition.y))

        //3. Calculate The Distance Between Them
        let distanceBetweenEyesInMetres = GLKVector3Distance(leftEyePosition, righEyePosition)
        let distanceBetweenEyesInCM = distanceBetweenEyesInMetres * 100

        print("The Distance Between The Eyes Is Approximatly \(distanceBetweenEyesInCM)")
        
        self.distanceText = "\(distanceBetweenEyesInCM) cm"
        
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

extension SCNVector3 {
    func magnitude() -> Float {
        return sqrt(x*x + y*y + z*z)
    }
    
    static func dot(_ v1: SCNVector3, _ v2: SCNVector3) -> Float {
        return (v1.x * v2.x) + (v1.y * v2.y) + (v1.z * v2.z)
    }
    
    static func subtractVectors(_ left: SCNVector3, _ right: SCNVector3) -> SCNVector3 {
        return SCNVector3Make(left.x - right.x, left.y - right.y, left.z - right.z)
    }
}
