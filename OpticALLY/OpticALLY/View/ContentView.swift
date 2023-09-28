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
}

struct ContentView: View {
    @State private var currentView: ViewState = .introduction
    
    var body: some View {
        Group {
            switch currentView {
            case .introduction:
                IntroductionView(currentView: $currentView)
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation {
                            currentView = .tracking
                        }
                    }
            case .tracking:
                EyesTrackingView(currentView: $currentView)
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation {
                            currentView = .introduction
                        }
                    }
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
