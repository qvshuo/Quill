import SwiftUI

/// 键盘主题 token，近似 iOS 26.6 简体拼音键盘的视觉参数。
/// 键帽为纯色填充，无阴影、描边、渐变等任何效果，边缘绝对清晰。
/// 键盘面板背景保持透明，由系统键盘容器统一绘制（fcitx5-ios 风格）。
/// 浅色为不透明色；深色采用 fcitx5-ios 同款「半透明叠加」——键帽色为半透明白/灰，
/// 经透明面板后的系统深色键盘背板（≈ #2B2B2B）混合出最终观感，混合结果与原不透明
/// 深色基本一致（见 `Theme.dark` 注释）。深浅色由 `@Environment(\.colorScheme)` 自动跟随。
/// 按压效果为统一按压色（浅色变暗 / 深色变亮），
/// 由 `fillColor(style:isPressed:)` 推导，仅设一个按压色 token。
public struct Theme {
    public let keyBackground: Color
    public let specialKeyBackground: Color
    /// 按键按压时的填充色（浅色变暗 / 深色变亮，原生同款；所有键型共用）。
    public let pressedKeyBackground: Color
    public let keyForeground: Color
    public let specialKeyForeground: Color
    /// 字符键按压预览气泡背景：必须是**不透明**色（气泡悬浮于键帽之上，
    /// 背后是透明面板/键缝，深色若沿用半透明叠加会透出背板显得「透明」）。
    public let previewBubbleBackground: Color
    public let keyCornerRadius: CGFloat
    public let keyHeight: CGFloat
    public let keySpacing: CGFloat
    public let rowSpacing: CGFloat
    public let keyboardPadding: EdgeInsets
    public let candidateBarHeight: CGFloat
    public let candidateSelectionFill: Color
    /// 候选栏右侧展开/收起箭头宽度（候选网格首行避让宽度）。
    public let chevronWidth: CGFloat
    /// 候选单元格高度（折叠态选中背景与展开网格单元格一致）。
    public let candidateCellHeight: CGFloat
    /// 选中候选 pill 高度（略高于普通候选，上下留白更大）。
    public let candidateSelectionHeight: CGFloat
    /// 选中候选文字与背景的左右边距（普通候选用 10，选中收紧到该值）。
    public let candidateSelectionHPadding: CGFloat
    /// 选中候选 pill 圆角。
    public let candidateSelectionCornerRadius: CGFloat
    /// 候选文字字号（与 `candidateFont` 一致，供文本宽度测量）。
    public let candidateCellFontSize: CGFloat
    /// 特殊键（123 / ABC / 中英切换 / 回车等）的文字字号。
    public let specialKeyFontSize: CGFloat
    public let font: Font
    public let candidateFont: Font

    /// 键盘内容总高度：候选栏 + 键区 + 内边距。
    public var totalHeight: CGFloat {
        candidateBarHeight
            + keyboardPadding.top
            + 4 * keyHeight
            + 3 * rowSpacing
            + keyboardPadding.bottom
    }

    public nonisolated(unsafe) static let light = Theme(
        keyBackground: Color(hex: 0xFFFFFF),
        specialKeyBackground: Color(hex: 0xFFFFFF),
        pressedKeyBackground: Color(hex: 0xD1D4D9),
        keyForeground: Color(hex: 0x171717),
        specialKeyForeground: Color(hex: 0x171717),
        previewBubbleBackground: Color(hex: 0xFFFFFF),
        candidateSelectionFill: Color(hex: 0xF6F8F9),
        geometry: base
    )

    public nonisolated(unsafe) static let dark = Theme(
        // 深色采用 fcitx5-ios 同款「半透明叠加」：这些半透明白/灰经系统深色键盘背板
        // （≈ #2B2B2B）混合后 ≈ 原不透明色——keyBackground 白@0.21→#585858（原 #575858）、
        // specialKeyBackground 灰#858585@0.17→#3A3A3A（原 #3A3A3C）、
        // pressedKeyBackground 白@0.30→#6B6B6B（原 #6A6A6C）、
        // candidateSelectionFill 白@0.22→#5A5A5A（原 #595858）。与系统背板联动更自然。
        keyBackground: Color.white.opacity(0.21),
        specialKeyBackground: Color(red: 133 / 255, green: 133 / 255, blue: 133 / 255).opacity(0.17),
        pressedKeyBackground: Color.white.opacity(0.30),
        keyForeground: Color(hex: 0xFFFFFF),
        specialKeyForeground: Color(hex: 0xFFFFFF),
        // 不透明：等价深色键帽白@0.21 经 #2B2B2B 背板混合后的观感（#585858），
        // 悬浮气泡不透明才不会被背板透出。
        previewBubbleBackground: Color(hex: 0x585858),
        candidateSelectionFill: Color.white.opacity(0.22),
        geometry: base
    )

    // 主题共享的几何/字体 token：深浅色仅颜色不同，几何一致，
    // 收敛为单一来源，避免两处维护发散。
    private static let base = ThemeGeometry(
        keyCornerRadius: 8,
        keyHeight: 45,
        keySpacing: 6,
        rowSpacing: 11,
        keyboardPadding: EdgeInsets(top: 8, leading: 7, bottom: 5, trailing: 7),
        candidateBarHeight: 40,
        chevronWidth: 34,
        candidateCellHeight: 32,
        candidateSelectionHeight: 34,
        candidateSelectionHPadding: 6,
        candidateSelectionCornerRadius: 9,
        candidateCellFontSize: 19,
        specialKeyFontSize: 17,
        font: .system(size: 24, weight: .regular),
        candidateFont: .system(size: 19, weight: .regular)
    )

    private init(
        keyBackground: Color,
        specialKeyBackground: Color,
        pressedKeyBackground: Color,
        keyForeground: Color,
        specialKeyForeground: Color,
        previewBubbleBackground: Color,
        candidateSelectionFill: Color,
        geometry: ThemeGeometry
    ) {
        self.keyBackground = keyBackground
        self.specialKeyBackground = specialKeyBackground
        self.pressedKeyBackground = pressedKeyBackground
        self.keyForeground = keyForeground
        self.specialKeyForeground = specialKeyForeground
        self.previewBubbleBackground = previewBubbleBackground
        self.candidateSelectionFill = candidateSelectionFill
        self.keyCornerRadius = geometry.keyCornerRadius
        self.keyHeight = geometry.keyHeight
        self.keySpacing = geometry.keySpacing
        self.rowSpacing = geometry.rowSpacing
        self.keyboardPadding = geometry.keyboardPadding
        self.candidateBarHeight = geometry.candidateBarHeight
        self.chevronWidth = geometry.chevronWidth
        self.candidateCellHeight = geometry.candidateCellHeight
        self.candidateSelectionHeight = geometry.candidateSelectionHeight
        self.candidateSelectionHPadding = geometry.candidateSelectionHPadding
        self.candidateSelectionCornerRadius = geometry.candidateSelectionCornerRadius
        self.candidateCellFontSize = geometry.candidateCellFontSize
        self.specialKeyFontSize = geometry.specialKeyFontSize
        self.font = geometry.font
        self.candidateFont = geometry.candidateFont
    }
}

/// 深浅色主题共享的几何/字体 token。
private struct ThemeGeometry {
    let keyCornerRadius: CGFloat
    let keyHeight: CGFloat
    let keySpacing: CGFloat
    let rowSpacing: CGFloat
    let keyboardPadding: EdgeInsets
    let candidateBarHeight: CGFloat
    let chevronWidth: CGFloat
    let candidateCellHeight: CGFloat
    let candidateSelectionHeight: CGFloat
    let candidateSelectionHPadding: CGFloat
    let candidateSelectionCornerRadius: CGFloat
    let candidateCellFontSize: CGFloat
    let specialKeyFontSize: CGFloat
    let font: Font
    let candidateFont: Font
}

public extension View {
    /// 键帽背景：纯色填充，无阴影、描边、渐变等任何效果，边缘绝对清晰。
    /// 浅色不透明、深色半透明叠加（经系统背板混合，见 `Theme.dark`）。
    /// 按压时切换到统一按压底色（浅色变暗 / 深色变亮，见 `Theme.fillColor`）。
    @ViewBuilder
    func keyBackground(
        isPressed: Bool,
        style: KeyStyle,
        theme: Theme
    ) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: theme.keyCornerRadius, style: .continuous)
                .fill(theme.fillColor(style: style, isPressed: isPressed))
        )
    }
}

public extension Theme {
    /// 确认（回车）键底色：单一常量，与 fcitx5-ios `highlightBackground` 一致。
    static let confirmKeyColor = Color(hex: 0x007AFF)

    /// 键帽填充色（含按压态）：按压统一使用 `pressedKeyBackground`
    /// （浅色变暗、深色变亮，原生同款；所有键型共用）。
    /// 纯函数，供视图与单元测试共用。
    func fillColor(style: KeyStyle, isPressed: Bool) -> Color {
        switch style {
        case .confirm:
            return isPressed ? pressedKeyBackground : Theme.confirmKeyColor
        case .special:
            return isPressed ? pressedKeyBackground : specialKeyBackground
        case .normal:
            return isPressed ? pressedKeyBackground : keyBackground
        }
    }
}

extension Color {
    /// 0xRRGGBB 十六进制颜色。
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
