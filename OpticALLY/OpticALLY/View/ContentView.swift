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
    
    var body: some View {
        Group {
            switch globalState.currentView {
            case .introduction:
                IntroductionView()
                    .transition(.opacity)
                
            case .tracking:
                EyesTrackingView()
                    .transition(.opacity)
                
            case .scanning:
                CameraView()
                    .transition(.opacity)
                    .ignoresSafeArea(.all)
            }
        }
        .animation(.easeInOut, value: true)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(GlobalState())
    }
}
