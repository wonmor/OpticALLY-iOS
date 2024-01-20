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
import Resources

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

var standardOutReader: StandardOutReader?
var sys: PythonObject?

@main
struct OpticALLYApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
           DispatchQueue.global(qos: .userInitiated).async {
               SetPythonHome()
               SetTMP()
               
               sys = Python.import("sys")
               
               sys!.stdout = Python.open(NSTemporaryDirectory() + "stdout.txt", "w", encoding: "utf8")
               sys!.stderr = sys!.stdout
               
               print(sys!.stdout.encoding)
               
               print("Python \(sys!.version_info.major).\(sys!.version_info.minor)")
               print("Python Version: \(sys!.version)")
               print("Python Encoding: \(sys!.getdefaultencoding().upper())")
               
               standardOutReader = StandardOutReader(STDOUT_FILENO: Int32(sys!.stdout.fileno())!, STDERR_FILENO: Int32(sys!.stderr.fileno())!)
               
//               guard let rubiconPath = Bundle.main.url(forResource: "rubicon-objc-0.4.0", withExtension: nil)?.path else {
//                   return
//               }
//
//               sys.path.insert(1, rubiconPath)
//               
//               sys.path.insert(1, Bundle.main.bundlePath)
//               let bridge = Python.import("ObjCBridge")
               
   //            DispatchQueue.main.sync {
   //                Buffer.shared.text = ""
   //            }
//               
//               let code = Python.import("code")
//               code.interact(readfunc: bridge.input, exitmsg: "Bye.")
           }
        
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

class PythonBridge: NSObject {
    @objc func input(_ prompt: String) -> String {
        Buffer.shared.append(prompt)
//        print(prompt)
        return Buffer.shared.read()
    }
}

class Buffer: ObservableObject {
    static let shared = Buffer()
    
    @Published var text = ""
    
    @Published var input = ""
    
    var inputs: [String] = []
    
    let semaphore = DispatchSemaphore(value: 0)
    
    func append(_ string: String) {
        DispatchQueue.main.async {
            self.text.append(string)
        }
    }
    
    func read() -> String {
        if inputs.isEmpty {
            standardOutReader?.isBufferEnabled = false
            semaphore.wait()
            standardOutReader?.isBufferEnabled = true
        }
        return inputs.removeFirst()
    }
    
    func onCommit() {
        var t = input
        let table = [
            "\u{2018}": "\'", // ‘
            "\u{2019}": "\'", // ’
            "\u{201C}": "\"", // “
            "\u{201D}": "\"", // ”
        ]
        for (c, r) in table {
            t = t.replacingOccurrences(of: c, with: r)
        }
        print(input, "->", t)

        text.append(t.appending("\n"))
        inputs.append(t)
        input = ""
        semaphore.signal()
    }
}

class StandardOutReader {
    let inputPipe = Pipe()
    
    let outputPipe = Pipe()
    
    var isBufferEnabled = true
    
    init(STDOUT_FILENO: Int32 = Darwin.STDOUT_FILENO, STDERR_FILENO: Int32 = Darwin.STDERR_FILENO) {
        dup2(STDOUT_FILENO, outputPipe.fileHandleForWriting.fileDescriptor)
        
        dup2(inputPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(inputPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        // listening on the readabilityHandler
        inputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            
            self?.outputPipe.fileHandleForWriting.write(data)
            
            guard self?.isBufferEnabled ?? false else {
                return
            }
            
            let str = String(data: data, encoding: .ascii) ?? "<Non-ascii data of size\(data.count)>\n"
            DispatchQueue.main.async {
                Buffer.shared.text += str
            }
        }
    }
}
