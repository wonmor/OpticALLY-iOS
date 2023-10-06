//
//  ContentView.swift
//  OpticALLY
//
//  Created by John Seong on 9/10/23.
//

import SwiftUI

enum ViewState {
    case introduction
    case tracking
    case scanning
}

struct ContentView: View {
    @State private var currentView: ViewState = .introduction
    
    @Environment(\.scenePhase) var scenePhase
    
    var body: some View {
        Group {
            switch currentView {
            case .introduction:
                IntroductionView(currentView: $currentView)
                    .transition(.opacity)
                
            case .tracking:
                EyesTrackingView(currentView: $currentView)
                    .transition(.opacity)
                
            case .scanning:
                CameraView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: true)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
