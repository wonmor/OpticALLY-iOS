import UIKit

struct HapticManager {
    enum HapticFeedbackStyle {
        case light
        case medium
        case heavy
        case success
        case warning
        case error
    }
    
    static func playHapticFeedback(style: HapticFeedbackStyle) {
        switch style {
        case .light, .medium, .heavy:
            let impactStyle: UIImpactFeedbackGenerator.FeedbackStyle
            
            switch style {
            case .light:
                impactStyle = .light
            case .medium:
                impactStyle = .medium
            case .heavy:
                impactStyle = .heavy
            default:
                return // This should not be possible
            }
            
            let impactGenerator = UIImpactFeedbackGenerator(style: impactStyle)
            impactGenerator.impactOccurred()
            
        case .success, .warning, .error:
            let notificationType: UINotificationFeedbackGenerator.FeedbackType
            
            switch style {
            case .success:
                notificationType = .success
            case .warning:
                notificationType = .warning
            case .error:
                notificationType = .error
            default:
                return // This should not be possible
            }
            
            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.notificationOccurred(notificationType)
        }
    }
}
