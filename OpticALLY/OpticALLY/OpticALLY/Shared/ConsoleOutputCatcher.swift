//
//  ConsoleOutputCatcher.swift
//  OpticALLY
//
//  Created by John Seong on 11/9/23.
//

import Foundation
import Combine

class ConsoleOutputCatcher {
    static let shared = ConsoleOutputCatcher()
    private init() {}
    
    private var output = "" {
        didSet {
            DispatchQueue.main.async {
                self.outputPublisher.send(self.output)
            }
        }
    }
    
    let outputPublisher = PassthroughSubject<String, Never>()

    func catchOutput(_ closure: () -> Void) {
        let pipe = Pipe()
        let dupStdOut = dup(STDOUT_FILENO)
        
        fflush(stdout)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        
        closure()
        
        fflush(stdout)
        dup2(dupStdOut, STDOUT_FILENO)
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let string = String(data: data, encoding: .utf8) {
            output += string
        }
        
        close(dupStdOut)
    }
}

