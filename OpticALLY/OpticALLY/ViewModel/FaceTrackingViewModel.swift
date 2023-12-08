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
}
