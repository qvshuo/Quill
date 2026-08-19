import Testing
import SwiftUI
import UIKit
@testable import KeyboardUI

/// 主题键帽填充色的纯映射逻辑测试：按压统一使用按压色（浅色变暗 / 深色变亮）。
/// 深色为 fcitx5-ios 同款「半透明叠加」，经系统深色键盘背板（≈ #2B2B2B）混合出最终观感。
struct ThemeFillColorTests {
    @Test("未按压时填充色返回对应基础 token")
    func unpressedReturnsBaseTokens() {
        for theme in [Theme.light, Theme.dark] {
            #expect(theme.fillColor(style: .normal, isPressed: false) == theme.keyBackground)
            #expect(theme.fillColor(style: .special, isPressed: false) == theme.specialKeyBackground)
            #expect(theme.fillColor(style: .confirm, isPressed: false) == Theme.confirmKeyColor)
        }
    }

    @Test("按压时所有键型统一使用按压色（normal/special/confirm）")
    func pressedUsesPressedColor() {
        for theme in [Theme.light, Theme.dark] {
            #expect(theme.fillColor(style: .normal, isPressed: true) == theme.pressedKeyBackground)
            #expect(theme.fillColor(style: .special, isPressed: true) == theme.pressedKeyBackground)
            #expect(theme.fillColor(style: .confirm, isPressed: true) == theme.pressedKeyBackground)
        }
    }

    @Test("两种主题下按压都产生可见的填充变化（按压色不同于各基色）")
    func pressIsVisiblyDifferentInBothThemes() {
        for theme in [Theme.light, Theme.dark] {
            #expect(notEqual(theme.pressedKeyBackground, theme.keyBackground))
            #expect(notEqual(theme.pressedKeyBackground, theme.specialKeyBackground))
            #expect(notEqual(theme.pressedKeyBackground, Theme.confirmKeyColor))
            #expect(notEqual(theme.fillColor(style: .normal, isPressed: true),
                theme.fillColor(style: .normal, isPressed: false)))
            #expect(notEqual(theme.fillColor(style: .special, isPressed: true),
                theme.fillColor(style: .special, isPressed: false)))
            #expect(notEqual(theme.fillColor(style: .confirm, isPressed: true),
                theme.fillColor(style: .confirm, isPressed: false)))
        }
    }

    @Test("确认键蓝色为单一常量 #007AFF")
    func confirmBlueIsSingleConstant() {
        #expect(Theme.confirmKeyColor == Color(hex: 0x007AFF))
        #expect(Theme.light.fillColor(style: .confirm, isPressed: false)
            == Theme.dark.fillColor(style: .confirm, isPressed: false))
    }

    @Test("深浅色主题色值基线（浅色功能键为白色；深色为半透明叠加）")
    func themeColorBaselines() {
        // 浅色不透明：键/功能键白色，按压色比旧 #ABB1BA 更浅。
        #expect(Theme.light.keyBackground == Color(hex: 0xFFFFFF))
        #expect(Theme.light.specialKeyBackground == Color(hex: 0xFFFFFF))
        #expect(Theme.light.pressedKeyBackground == Color(hex: 0xD1D4D9))
        // 深色为半透明叠加（alpha < 1），经背板混合后见 darkOverlayBlendsToOriginalColors。
        #expect(rgba(Theme.dark.keyBackground).a < 1.0)
        #expect(rgba(Theme.dark.specialKeyBackground).a < 1.0)
        #expect(rgba(Theme.dark.pressedKeyBackground).a < 1.0)
        #expect(rgba(Theme.dark.candidateSelectionFill).a < 1.0)
    }

    @Test("深色叠加色经 #2B2B2B 背板混合后 ≈ 原不透明深色值")
    func darkOverlayBlendsToOriginalColors() {
        let cases: [(Color, UInt32)] = [
            (Theme.dark.keyBackground, 0x575858),
            (Theme.dark.specialKeyBackground, 0x3A3A3C),
            (Theme.dark.pressedKeyBackground, 0x6A6A6C),
            (Theme.dark.candidateSelectionFill, 0x595858),
        ]
        for (color, targetHex) in cases {
            let blended = Theme.blended(color)
            let target = Theme.rgba(Color(hex: targetHex))
            // 容差 ≈ 5/255：叠加色刻意取整 alpha，与目标色允许轻微偏差。
            #expect(abs(blended.r - target.r) < 0.02,
                "r: \(blended.r) vs \(target.r)")
            #expect(abs(blended.g - target.g) < 0.02,
                "g: \(blended.g) vs \(target.g)")
            #expect(abs(blended.b - target.b) < 0.02,
                "b: \(blended.b) vs \(target.b)")
        }
    }
}

// MARK: - Helpers

/// 将 Color 解析为 sRGB 的 (r, g, b, a) 分量（避免依赖 SwiftUI Color 的 Equatable 语义）。
/// 生产实现见 `Theme.rgba`；这里仅用于「不相等」断言。
private func rgba(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    Theme.rgba(color)
}

private func notEqual(_ a: Color, _ b: Color) -> Bool {
    rgba(a) != rgba(b)
}
