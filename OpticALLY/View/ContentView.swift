//
//  ContentView.swift
//  OpticALLY
//
//  Created by John Seong on 9/10/23.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var globalState: GlobalState

    // Use a unique ID for each case of the view
    var uniqueID: String {
        UUID().uuidString
    }
    
    var body: some View {
        Group {
            switch globalState.currentView {
            case .introduction:
                IntroductionView()
                    .transition(.opacity)
                
            case .scanning:
                PostScanView()
                    .transition(.opacity)
                
            case .postScanning:
                PostScanView()
                    .transition(.opacity)
            }
                
//            case .scanning:
//                CameraView()
//                    .transition(.opacity)
//                    .ignoresSafeArea(.all)
//                
//            case .postScanning:
//                PostScanView()
//                    .transition(.opacity)
//            }
        }
        .animation(.easeInOut, value: globalState.currentView)
    }
}
