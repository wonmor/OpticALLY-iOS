//
//  HapticManager.swift
//  OpticALLY
//
//  Created by John Seong on 11/26/23.
//

import Foundation

struct HapticManager {
    static func playHapticFeedback() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
