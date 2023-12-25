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

    // Dummy variable to trigger view refresh
    @Published var refreshTrigger: Bool = false

    // Method to refresh the view
    func refreshView() {
        refreshTrigger.toggle() // This will cause the view to refresh
    }
}
