import Foundation
import SwiftUI
import UIKit

/// 长按连续触发：按下立即触发一次，长按 0.5 秒后每 0.1 秒持续触发。
final class KeyPressRepeater: @unchecked Sendable {
    private var timer: Timer?
    private var workItem: DispatchWorkItem?
    private let fire: () -> Void
    /// 仅在长按重复触发时调用（首次触发的震动由按键触摸回调负责）。
    private let feedback: (() -> Void)?

    init(
        fire: @escaping () -> Void,
        feedback: (() -> Void)? = nil
    ) {
        self.fire = fire
        self.feedback = feedback
    }

    func startPress() {
        fire()
        // 防御：清掉上一次 press 残留的定时器，避免异常调用序列下双重触发。
        endPress()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.timer?.invalidate()
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.fire()
                self.feedback?()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func endPress() {
        workItem?.cancel()
        workItem = nil
        timer?.invalidate()
        timer = nil
    }
}

/// 长按键触摸跟踪：用 UIKit 触摸回调可靠地报告按下/松开/取消/滑离。
/// - `onRelease`：正常松手，触发按键动作。
/// - `onCancel`：触摸被系统取消（来电横幅、Control Center、键盘收起手势）
///   或手指滑离按键（漂移超过容差）——复位按压视觉但不产生动作。
/// 跟踪首个触摸的对象身份：多点触控时其余手指不触发重复 press/release。
struct KeyTouchTracker: UIViewRepresentable {
    let onPress: () -> Void
    let onRelease: () -> Void
    let onCancel: (() -> Void)?

    init(
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.onPress = onPress
        self.onRelease = onRelease
        self.onCancel = onCancel
    }

    func makeUIView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onPress = onPress
        view.onRelease = onRelease
        view.onCancel = onCancel
        return view
    }

    func updateUIView(_ uiView: TrackerView, context: Context) {
        uiView.onPress = onPress
        uiView.onRelease = onRelease
        uiView.onCancel = onCancel
    }

    final class TrackerView: UIView {
        var onPress: (() -> Void)?
        var onRelease: (() -> Void)?
        var onCancel: (() -> Void)?

        /// 当前跟踪的触摸；nil 表示没有按下的手指。
        private var activeTouch: UITouch?
        private var hasDrifted = false

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            bounds.contains(point) ? self : nil
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            guard activeTouch == nil, let touch = touches.first else { return }
            activeTouch = touch
            hasDrifted = false
            onPress?()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            guard let touch = activeTouch, touches.contains(touch), !hasDrifted else { return }
            // 滑出按键周边容差即视为漂移：停止长按计时、复位视觉，松手不再触发动作
            // （原生键盘的纠错手势）。
            let tolerance: CGFloat = 20
            let location = touch.location(in: self)
            if !bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(location) {
                hasDrifted = true
                onCancel?()
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            guard let touch = activeTouch, touches.contains(touch) else { return }
            activeTouch = nil
            if hasDrifted {
                onCancel?()
            } else {
                onRelease?()
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            guard activeTouch != nil else { return }
            activeTouch = nil
            onCancel?()
        }
    }
}
