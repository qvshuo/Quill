import UIKit
import SwiftUI

public extension Theme {
    /// fcitx5-ios 假定的系统深色键盘背板（半透明叠加的混合基底）。
    /// 键盘面板透明、由系统容器绘制深色背板 ≈ #2B2B2B，浅色不透明色直接着色，
    /// 深色叠加色（alpha < 1）经此背板混合出最终观感。
    /// 这是整个深色主题唯一的假设点：所有叠加 alpha 由它与目标色反解得出，
    /// iOS 若更换键盘底色需重校此处并跑 `ThemeTests` 混合断言。
    nonisolated static let darkBackdrop: CGFloat = 43 / 255

    /// 反解叠加 alpha：使中性灰基色 `base` 经背板混合后命中目标不透明灰 `target`
    /// （两者均为 0xRRGGBB 的中性灰）。纯函数，供深色主题构造与单元测试共用。
    nonisolated static func overlayAlpha(base: UInt32, target: UInt32) -> CGFloat {
        let backdrop = darkBackdrop
        let baseLevel = CGFloat((base >> 8) & 0xFF) / 255
        let targetLevel = CGFloat((target >> 8) & 0xFF) / 255
        guard baseLevel != backdrop else { return 0 }
        return max(0, min(1, (targetLevel - backdrop) / (baseLevel - backdrop)))
    }

    /// 中性灰叠加色：基色（默认白色）以上方反解的 alpha 半透明着色，
    /// 经背板混合后即为目标不透明灰。
    nonisolated static func overlay(
        base: UInt32 = 0xFFFFFF,
        target: UInt32
    ) -> Color {
        Color(hex: base).opacity(overlayAlpha(base: base, target: target))
    }

    /// 把半透明叠加色解析为 sRGB 分量，并混合到指定背板上（alpha 合成），
    /// 返回最终呈现在屏幕上的不透明 RGB。默认背板为深色系统键盘底色。
    ///
    /// fcitx5-ios 同款思路：`assertBlendedPrototype` 用它验证深色 overlay 经
    /// `#2B2B2B` 混合后 ≈ 原不透明深色值。纯函数，供视图调试与单元测试共用。
    nonisolated static func blended(
        _ color: Color,
        over backdrop: CGFloat = darkBackdrop
    ) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let c = rgba(color)
        return (
            c.r * c.a + backdrop * (1 - c.a),
            c.g * c.a + backdrop * (1 - c.a),
            c.b * c.a + backdrop * (1 - c.a)
        )
    }

    /// 将 Color 解析为 sRGB 的 (r, g, b, a) 分量。
    nonisolated static func rgba(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}