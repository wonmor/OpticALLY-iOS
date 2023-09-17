//
//  ContentView.swift
//  OpticALLY
//
//  Created by John Seong on 9/10/23.
//

import SwiftUI

struct ContentView: View {
    @State var isNavigate = false
    
    var body: some View {
        if (isNavigate) {
            EyesTrackingView()
        } else {
            IntroductionView(isNavigate: $isNavigate)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
