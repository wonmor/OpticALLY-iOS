//
//  CameraViewModel.swift
//  OpticALLY
//
//  Created by John Seong on 12/25/23.
//

import Foundation

class SharedViewModel: ObservableObject {
    @Published var shouldReloadCameraView: Bool = false
}
