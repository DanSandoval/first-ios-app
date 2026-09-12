import UIKit

/// Thin wrapper over UIKit's feedback generators.
///
/// Haptic feedback is a silent no-op in the Simulator and on devices without a
/// Taptic Engine, so callers never need to branch on availability.
enum Haptics {

    /// Fires a physical "impact" tap, e.g. when a button commits an action.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        // Warming the Taptic Engine first keeps the tap in sync with the tap.
        generator.prepare()
        generator.impactOccurred()
    }

    /// Fires a semantic notification pattern (success / warning / error).
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}
