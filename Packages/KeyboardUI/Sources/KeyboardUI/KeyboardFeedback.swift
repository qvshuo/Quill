import UIKit

/// 按键点击反馈：强震感但略弱于满强度（.rigid + intensity 0.75）。
/// 触发后立即 prepare() 预热下一次，减少高频点击的迟滞；键盘出现时再统一预热一次。
/// 注意：触觉反馈需要键盘扩展拥有「完全访问」权限。
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
