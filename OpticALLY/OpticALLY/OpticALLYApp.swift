//
//  OpticALLYApp.swift
//  OpticALLY
//
//  Created by John Seong on 9/10/23.
//

import SwiftUI
import DevicePpi

let devicePPI: Double = {
    switch Ppi.get() {
    case .success(let ppi):
        return ppi
    case .unknown(let bestGuessPpi, let error):
        // A bestGuessPpi value is provided but may be incorrect
        // Treat as a non-fatal error -- e.g. log to your backend and/or display a message
        return bestGuessPpi
    }
}()

enum ViewState {
    case introduction
    case tracking
    case scanning
    case postScanning
}

class GlobalState: ObservableObject {
    @Published var currentView: ViewState = .introduction
}

@main
struct OpticALLYApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        for family: String in UIFont.familyNames
        {
            print(family)
            for names: String in UIFont.fontNames(forFamilyName: family)
            {
                print("== \(names)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(GlobalState())
        }
    }
}
