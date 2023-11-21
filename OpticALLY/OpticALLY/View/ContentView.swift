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
                    .id(uniqueID)  // Using a unique ID to recreate the view
                    .transition(.opacity)
                
            case .tracking:
                EyesTrackingView()
                    .id(uniqueID)  // Using a unique ID to recreate the view
                    .transition(.opacity)
                
            case .scanning:
                CameraView()
                    .id(uniqueID)  // Using a unique ID to recreate the view
                    .transition(.opacity)
                    .ignoresSafeArea(.all)
                
            case .postScanning:
                PostScanView()
                    .id(uniqueID)  // Using a unique ID to recreate the view
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: globalState.currentView)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(GlobalState())
    }
}
