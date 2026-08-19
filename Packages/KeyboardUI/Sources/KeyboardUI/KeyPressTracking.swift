import Foundation
import SwiftUI
import UIKit

/// 长按连续触发：按下立即触发一次，长按超过 `repeatDelay` 后按 `repeatInterval` 持续触发。
final class KeyPressRepeater: @unchecked Sendable {
    private var timer: Timer?
    private var workItem: DispatchWorkItem?
    private let fire: () -> Void
    /// 仅在长按重复触发时调用（首次触发由外层 `onChange(isPressed)` 负责震动）。
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
        workItem?.cancel()
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

/// 长按键触摸跟踪：用 UIKit 触摸回调可靠地报告按下/松开（含取消）。
struct KeyTouchTracker: UIViewRepresentable {
    let onPress: () -> Void
    let onRelease: () -> Void

    init(
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func makeUIView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onPress = onPress
        view.onRelease = onRelease
        return view
    }

    func updateUIView(_ uiView: TrackerView, context: Context) {
        uiView.onPress = onPress
        uiView.onRelease = onRelease
    }

    final class TrackerView: UIView {
        var onPress: (() -> Void)?
        var onRelease: (() -> Void)?

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            self
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            onPress?()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            onRelease?()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            onRelease?()
        }
    }
}
