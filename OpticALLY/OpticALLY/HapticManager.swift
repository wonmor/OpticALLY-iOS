//
//  HapticManager.swift
//  OpticALLY
//
//  Created by John Seong on 11/26/23.
//

import Foundation

struct HapticManager {
    static func playHapticFeedback(type: UINotificationFeedbackGenerator.FeedbackType = .success) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
}
