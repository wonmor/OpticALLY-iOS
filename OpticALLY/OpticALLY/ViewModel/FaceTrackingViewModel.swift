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
}
