//
//  ARFaceTrackingView.swift
//  OpticALLY
//
//  Created by John Seong on 12/7/23.
//

import SwiftUI
import ARKit

struct ARFaceTrackingView: View {
    var body: some View {
        ZStack {
            SceneKitUSDZView(usdzFileName: "Male_Base_Head.usdz", viewModel: faceTrackingViewModel)
        }
    }
}
