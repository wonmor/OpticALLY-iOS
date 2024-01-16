//
//  FaceTrackingViewModel.swift
//  OpticALLY
//
//  Created by John Seong on 12/7/23.
//

import Foundation
import ARKit

class FaceTrackingViewModel: ObservableObject {
    @Published var faceAnchor: ARFaceAnchor?
    
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
}
