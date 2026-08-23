import UIKit

/// 按键点击反馈：.rigid + intensity 0.75，触发后立即 prepare() 预热下一次。
/// 需要键盘扩展拥有「完全访问」权限。
@MainActor
public enum KeyboardFeedback {
    private static let feedback = UIImpactFeedbackGenerator(style: .rigid)

    public static func prepare() {
        feedback.prepare()
    }

    public static func play() {
        feedback.impactOccurred(intensity: 0.75)
        feedback.prepare()
    }
}
