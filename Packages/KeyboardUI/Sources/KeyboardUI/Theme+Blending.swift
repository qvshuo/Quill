import UIKit
import SwiftUI

public extension Theme {
    /// fcitx5-ios 假定的系统深色键盘背板（半透明叠加的混合基底）。
    /// 键盘面板透明、由系统容器绘制深色背板 ≈ #2B2B2B，浅色不透明色直接着色，
    /// 深色叠加色（alpha < 1）经此背板混合出最终观感。
    nonisolated static let darkBackdrop: CGFloat = 43 / 255

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