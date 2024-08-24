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
    
    @State private var uniqueId = UUID()
    
    var body: some View {
        Group {
            switch globalState.currentView {
            case .introduction:
                IntroductionView()
                    .transition(.opacity)

            case .scanning:
                CameraView()
                    .id(uniqueId)
                    .transition(.opacity)
                    .ignoresSafeArea(.all)
                
            case .postScanning:
                PostScanView(uniqueId: $uniqueId)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: globalState.currentView)
    }
}
