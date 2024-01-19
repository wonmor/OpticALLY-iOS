//
//  OpticALLYApp.swift
//  OpticALLY
//
//  Created by John Seong on 9/10/23.
//

import SwiftUI
import SystemConfiguration
import DevicePpi
import PythonSupport
import PythonKit

let faceTrackingViewModel = FaceTrackingViewModel()

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
        PythonSupport.initialize()

        let sys = Python.import("sys")

        print("Python \(sys.version_info.major).\(sys.version_info.minor)")
        print("Python Version: \(sys.version)")
        print("Python Encoding: \(sys.getdefaultencoding().upper())")
        
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
    
    // Network Reachability Check
    static func isConnectedToNetwork() -> Bool {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let defaultRouteReachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            return false
        }
        
        var flags: SCNetworkReachabilityFlags = []
        if !SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) {
            return false
        }
        
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        
        return (isReachable && !needsConnection)
    }
}
