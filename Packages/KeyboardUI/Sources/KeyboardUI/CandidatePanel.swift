import SwiftUI
import Models

/// 候选面板（collapsed 态）：横向滚动展示全部候选，候选按钮按内容自然宽度排布
/// （几个候选就占多宽，不强制填满一行；超出视口的通过横滑查看全部 77 个）。
/// 右侧 chevron 独立于滚动区之外，候选不会滚到箭头下方；展开为覆盖整个键盘的
/// 候选网格（网格由 KeyboardView 承载，参考 fcitx5-ios）。注释不渲染。
public struct CandidatePanel: View {
    let candidates: [Candidate]
    let highlightedIndex: Int
    let theme: Theme
    @Binding var isExpanded: Bool
    let onSelect: (Int) -> Void

    private var barHeight: CGFloat {
        theme.candidateBarHeight + theme.keyboardPadding.top
    }

    public init(
        candidates: [Candidate],
        highlightedIndex: Int,
        theme: Theme,
        isExpanded: Binding<Bool>,
        onSelect: @escaping (Int) -> Void
    ) {
        self.candidates = candidates
        self.highlightedIndex = highlightedIndex
        self.theme = theme
        _isExpanded = isExpanded
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        // 候选文本每次敲键都会变，内容身份无 diff 收益；用下标做稳定身份，
                        // 避免 `Candidate` 每次重建引入新的身份导致整组重建。
                        ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                            candidateButton(index: index, candidate: candidate)
                        }
                    }
                    .padding(.leading, theme.keyboardPadding.leading)
                    .frame(height: geometry.size.height, alignment: .center)
                }
            }

            if !candidates.isEmpty {
                expandToggle
            }
        }
        .frame(height: barHeight)
    }

    private var expandToggle: some View {
        CandidateChevronButton(
            isExpanded: isExpanded,
            height: barHeight,
            theme: theme,
            action: { isExpanded.toggle() }
        )
    }

    private func candidateButton(index: Int, candidate: Candidate) -> some View {
        let isSelected = index == highlightedIndex
        return CandidateCellView(
            text: candidate.text,
            isHighlighted: isSelected,
            theme: theme,
            action: { onSelect(index) }
        )
        .frame(height: barHeight, alignment: .center)
    }
}

/// 候选词单元格（折叠候选栏与展开网格共享）：选中 = pill，未选中 = 普通格。
/// 规格由 Theme token 统一（高度/圆角/边距/填充），两处渲染必须一致。
struct CandidateCellView: View {
    let text: String
    let isHighlighted: Bool
    let theme: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(theme.candidateFont)
                .foregroundStyle(.primary)
                // 选中 pill：左右边距收紧、上下边距略增、圆角更大（保持整体不过度放大）。
                .padding(.horizontal, isHighlighted ? theme.candidateSelectionHPadding : 10)
                .frame(height: isHighlighted ? theme.candidateSelectionHeight : theme.candidateCellHeight)
                .background {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: theme.candidateSelectionCornerRadius, style: .continuous)
                            .fill(theme.candidateSelectionFill)
                    }
                }
        }
        .buttonStyle(CandidateFeedbackButtonStyle())
    }
}

/// 候选栏右 / 网格角的展开箭头（折叠时向下、展开时向上）。
struct CandidateChevronButton: View {
    let isExpanded: Bool
    let height: CGFloat
    let theme: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // 与 fcitx5-ios / iOS 惯例一致：折叠时向下箭头（提示可展开），
            // 展开时向上箭头（提示可收起）。
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 13, weight: .medium))
                // 深浅色模式一致的固定灰色。
                .foregroundStyle(Color(hex: 0x4D5650))
                .frame(width: theme.chevronWidth, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 候选词按下时触发触觉反馈（与按键一致的震动）。
struct CandidateFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    KeyboardFeedback.play()
                }
            }
    }
}
