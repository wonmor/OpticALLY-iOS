//
//  LogManager.swift
//  OpticALLY
//
//  Created by John Seong on 11/25/23.
//

import Foundation

extension LogManager {
    func clearLogs() {
        logs.removeAll()
        latestLog = nil
    }
}

class LogManager: ObservableObject {
    static let shared = LogManager()
    private var logs: [String] = []
    @Published var latestLog: String?
    private var timer: Timer?
    
    private init() {
        // Set up a timer that updates `latestLog` every 3 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateLatestLog()
        }
    }
    
    func log(_ message: String) {
        DispatchQueue.main.async {
            self.logs.append(message)
        }
    }
    
    private func updateLatestLog() {
        DispatchQueue.main.async {
            self.latestLog = self.logs.last
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
