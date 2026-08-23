import SwiftUI
import UIKit
import Models
import RimeEngine

public struct KeyboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: KeyboardViewModel
    @State private var candidatesExpanded = false
    let rimeContext: RimeContext
    let inputState: InputState
    let keyboardType: UIKeyboardType
    let returnKeyType: UIReturnKeyType
    let onKey: (KeyAction) -> Void

    /// 主题跟随系统深浅色（`@Environment(\.colorScheme)`，fcitx5-ios 同款）：
    /// 控制器不再解析深浅色，由 SwiftUI 环境在系统切换时自动重求值。
    private var resolvedTheme: Theme {
        colorScheme == .dark ? .dark : .light
    }

    public init(
        rimeContext: RimeContext,
        inputState: InputState,
        keyboardType: UIKeyboardType = .default,
        returnKeyType: UIReturnKeyType = .default,
        onKey: @escaping (KeyAction) -> Void
    ) {
        self.rimeContext = rimeContext
        self.inputState = inputState
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.onKey = onKey
        let model = KeyboardViewModel()
        model.rimeContext = rimeContext
        model.inputState = inputState
        self._viewModel = State(initialValue: model)
    }

    public var body: some View {
        let theme = resolvedTheme
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // 面板透明、由系统键盘容器统一绘制（fcitx5-ios 风格），避免色差。
                Color.black.opacity(0.001)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if candidatesExpanded {
                        // 展开态网格覆盖整个键盘，避免与折叠候选栏首词重复。
                        ExpandedCandidateGrid(
                            rimeContext: rimeContext,
                            theme: theme,
                            totalWidth: geometry.size.width,
                            onCollapse: { candidatesExpanded = false },
                            onSelect: selectAndCollapse
                        )
                        .transition(.opacity)
                    } else {
                        CandidatesBar(
                            rimeContext: rimeContext,
                            theme: theme,
                            isExpanded: $candidatesExpanded,
                            onSelect: selectAndCollapse
                        )

                        keyArea(theme: theme, in: geometry.size.width)
                            .transition(.opacity)

                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.1), value: candidatesExpanded)
        }
        // 用主题计算出的总高度作为 SwiftUI 内在尺寸（fcitx5-ios 用
        // .frame(height: totalHeight) 同思路），让系统键盘容器按此高度
        // 平滑滑入，无需控制器手动设置 preferredContentSize。
        .frame(height: theme.totalHeight)
        .frame(maxWidth: .infinity)
        // 同步进度提示：候选栏顶部居中悬浮胶囊，不挡按键点击。toast 状态只在
        // `SyncToastOverlay` 自身 body 读取，变化不重求值整棵键盘树。
        .overlay(alignment: .top) {
            SyncToastOverlay(inputState: inputState, theme: theme)
        }
        .onAppear {
            KeyboardFeedback.prepare()
            viewModel.handleKeyboardTypeChange(keyboardType)
            viewModel.handleReturnKeyType(returnKeyType)
            rimeContext.setAsciiMode(viewModel.inputLanguage == .english)
        }
        .onChange(of: keyboardType) { _, newType in
            viewModel.handleKeyboardTypeChange(newType)
            rimeContext.setAsciiMode(viewModel.inputLanguage == .english)
        }
        .onChange(of: returnKeyType) { _, newType in
            viewModel.handleReturnKeyType(newType)
        }
        // 展开时一次性补齐全部候选，供网格选择。热路径只保留了当前页候选。
        // 候选清空后的自动收起由 CandidatesBar / ExpandedCandidateGrid
        // 在各自的 body 作用域观察（见子视图），不挂在整键盘 body 上。
        .onChange(of: candidatesExpanded) { _, expanded in
            if expanded {
                rimeContext.loadExpandedCandidates()
            }
        }
    }

    private func selectAndCollapse(_ index: Int) {
        // 与 handleKey 同一门禁：同步 toast 期间不响应候选选择 / 展开收起。
        guard inputState.toast == nil else { return }
        candidatesExpanded = false
        onKey(.selectCandidate(index))
    }

    /// 键区：只依赖「布局/语言/大小写/同步状态」这些低频变化的行集合。
    /// 敲键期间的 preedit/hasInputText/候选高频变化被收窄到 `KeyboardRowView`
    /// （仅含回车键的行）与候选区子视图，不流经此方法。
    private func keyArea(theme: Theme, in totalWidth: CGFloat) -> some View {
        VStack(spacing: theme.rowSpacing) {
            if viewModel.currentRows.isEmpty {
                // 布局加载失败兜底：显示错误而非空白键盘。
                // 高度 = 键区高度（总高 − 候选栏 − 上下内边距），与正常键区一致。
                let keysAreaHeight = theme.totalHeight
                    - theme.candidateBarHeight
                    - theme.keyboardPadding.top
                    - theme.keyboardPadding.bottom
                VStack(spacing: 8) {
                    Text("键盘布局加载失败")
                        .font(theme.candidateFont)
                        .foregroundStyle(.secondary)
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: keysAreaHeight)
            } else {
                // 行的相对顺序固定（每 layout+language 的键位不变），用下标做稳定身份，
                // 避免每次渲染重建导致 @State 丢失与视图树抖动。
                ForEach(Array(viewModel.currentRows.enumerated()), id: \.offset) { _, row in
                    KeyboardRowView(
                        row: row,
                        theme: theme,
                        totalWidth: totalWidth,
                        shiftState: viewModel.shiftState,
                        returnKeyLabel: viewModel.returnKeyLabel,
                        rimeContext: rimeContext,
                        inputState: inputState,
                        onKey: handleKey
                    )
                }
            }
        }
        .padding(
            EdgeInsets(
                top: 0,
                leading: theme.keyboardPadding.leading,
                bottom: theme.keyboardPadding.bottom,
                trailing: theme.keyboardPadding.trailing
            )
        )
    }

    private func handleKey(_ action: KeyAction) {
        // 同步 toast 展示期间屏蔽所有按键（字母/功能/切换键），待同步结果收起后再恢复。
        // `.startSync` 在 toast 置位前通过本入口，故长按空格仍能启动同步。
        guard inputState.toast == nil else { return }
        // @State 的 viewModel 在 rootView 替换时保留首份实例，其弱引用可能指向旧
        // context；consume() 前刷新为当前传入实例，避免走错对象（needsConfirm 等）。
        viewModel.rimeContext = rimeContext
        viewModel.inputState = inputState
        if let transformed = viewModel.consume(action) {
            onKey(transformed)
            // 中/英切换：视图按当前语言把 ascii_mode 写回 RIME。
            if case .toggleLanguage = transformed {
                rimeContext.setAsciiMode(viewModel.inputLanguage == .english)
            }
        }
    }
}

/// 折叠候选栏：在自身 body 作用域观察候选，候选刷新只重求值本视图，
/// 不重求值整棵键盘树（键盘树根 body 不读取候选状态）。
private struct CandidatesBar: View {
    let rimeContext: RimeContext
    let theme: Theme
    @Binding var isExpanded: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        CandidatePanel(
            candidates: rimeContext.candidates,
            highlightedIndex: rimeContext.highlightedCandidateIndex,
            theme: theme,
            isExpanded: $isExpanded,
            onSelect: onSelect
        )
        // 上屏/清空后候选为空时自动收起，避免空网格挡住键盘。
        .onChange(of: rimeContext.candidates.isEmpty) { _, empty in
            if empty { isExpanded = false }
        }
    }
}

/// 单行键盘行视图：只有「含回车键的行」在自身 body 作用域读取
/// `rimeContext.preedit` / `hasInputText`。拼音组合期间（preedit 变化）
/// 只重求值这一行，其余行与整个键区不随敲键重渲染。
private struct KeyboardRowView: View {
    let row: RowDescriptor
    let theme: Theme
    let totalWidth: CGFloat
    let shiftState: ShiftState
    let returnKeyLabel: String
    let rimeContext: RimeContext
    let inputState: InputState
    let onKey: (KeyAction) -> Void

    var body: some View {
        // 只有包含回车键的行才依赖 preedit / hasInputText：在自身 body 作用域读取。
        // 三元条件短路保证不含回车键的行从不读取这两个属性（不被 Observation 追踪）。
        let hasReturn = row.keys.contains { $0.action.isReturn }
        let hasPreedit = hasReturn ? !rimeContext.preedit.isEmpty : false
        let highlightReturn = hasReturn ? (!hasPreedit && inputState.hasInputText) : false
        let effectiveReturnLabel = hasReturn
            ? KeyboardViewModel.effectiveReturnLabel(hasPreedit: hasPreedit, hostLabel: returnKeyLabel)
            : nil

        let layout = RowLayoutMath.layout(RowLayoutParameters(
            keys: row.keys,
            totalWidth: totalWidth,
            sideInset: row.leadingPadding,
            keyboardLeading: theme.keyboardPadding.leading,
            keyboardTrailing: theme.keyboardPadding.trailing,
            keySpacing: theme.keySpacing,
            keyHeight: theme.keyHeight,
            minSpaceWidth: theme.keyHeight * 2.0,
            returnLabelWidth: hasReturn
                ? ReturnLabelWidth.measure(effectiveReturnLabel ?? returnKeyLabel, fontSize: theme.specialKeyFontSize)
                : 0
        ))

        return HStack(spacing: 0) {
                // 键位固定，用下标做稳定身份（见行 ForEach 说明）。行间距由 `gaps` 决定，
                // 使 ⇧/⌫ 与字母之间能插入对齐空隙（见 RowLayoutMath）。
                ForEach(Array(layout.keys.enumerated()), id: \.offset) { index, key in
                    if index > 0 {
                        Spacer()
                            .frame(width: layout.gaps[index - 1])
                    }
                    Key(
                        descriptor: effectiveDescriptor(
                            for: key,
                            hasReturn: hasReturn,
                            effectiveReturnLabel: effectiveReturnLabel,
                            highlightReturn: highlightReturn
                        ),
                        theme: theme,
                        shiftState: shiftState,
                        action: onKey
                    )
                    .frame(
                        width: layout.widths[index],
                        height: theme.keyHeight
                    )
                }
        }
        .padding(.horizontal, layout.sideInset)
    }

    /// 回车键的动态文案/高亮：有 preedit 显示「⏎」，否则显示宿主文案；
    /// 无 preedit 且输入框有文本时用 `.confirm` 蓝色高亮。其余键原样返回。
    private func effectiveDescriptor(
        for key: KeyDescriptor,
        hasReturn: Bool,
        effectiveReturnLabel: String?,
        highlightReturn: Bool
    ) -> KeyDescriptor {
        guard hasReturn, key.action.isReturn else { return key }
        return key.with(label: effectiveReturnLabel ?? key.label, style: highlightReturn ? .confirm : key.style)
    }
}

/// 同步 toast 悬浮层：在自身 body 作用域观察 `inputState.toast`，
/// toast 出现/替换/消失只重求值本视图，不重求值整棵键盘树。
private struct SyncToastOverlay: View {
    let inputState: InputState
    let theme: Theme

    var body: some View {
        Group {
            if let toast = inputState.toast {
                SyncToastView(toast: toast, theme: theme)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: inputState.toast)
    }
}

/// 同步 toast：候选栏顶部居中的悬浮胶囊。
/// 状态语义（见 `SyncToast`）：`started` 在同步期间持续展示，由控制器在结果
/// 到来时替换为 `.completed / .failed`；收起的时长由控制器计时（见
/// `InputController.scheduleToastDismissal`），视图不承载。
/// 纯文本，无交互，`allowsHitTesting(false)` 不挡候选与按键的点击。
/// 视觉：胶囊形（非选中候选 pill），阴影与字体参考按键悬浮预览气泡
/// （`Key.swift` 的 `shadow(color: .black.opacity(0.2), radius: 2, y: 1)`）；
/// 字号较候选略小、前景用次级色调，保持易读但不喧宾夺主。
private struct SyncToastView: View {
    let toast: SyncToast
    let theme: Theme

    var body: some View {
        Text(toast.message)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background {
                Capsule()
                    .fill(theme.keyBackground)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
            }
            .allowsHitTesting(false)
    }
}

/// 展开态候选网格：候选词铺满全宽、按文本自然宽度分行（`calculateLayout` 同款）。
/// 首行与折叠候选栏垂直对齐（首行中心 = barHeight/2，顶边距按首行实际行高
/// 34/32 计算），左对齐、让出 34pt 箭头区。只在自身 body 作用域观察候选。
private struct ExpandedCandidateGrid: View {
    let rimeContext: RimeContext
    let theme: Theme
    let totalWidth: CGFloat
    let onCollapse: () -> Void
    let onSelect: (Int) -> Void

    var body: some View {
        grid
            // 上屏/清空后候选为空时自动收起，避免空网格挡住键盘。
            .onChange(of: rimeContext.candidates.isEmpty) { _, empty in
                if empty { onCollapse() }
            }
    }

    /// 网格在展开/选取时会被重建，候选会异步变为当前页或空。网格行的排版
    /// 与单元格绘制必须基于同一份快照，避免 LazyVStack 惰性渲染读到已被
    /// 替换的、更短的 `candidates` 数组而下标越界崩溃。
    private var grid: some View {
        let barHeight = theme.candidateBarHeight + theme.keyboardPadding.top
        let gridPadding: CGFloat = theme.keyboardPadding.leading
        let chevronWidth = theme.chevronWidth
        let list = rimeContext.candidates
        let innerWidth = totalWidth - gridPadding * 2
        let metrics = CandidateGridLayout.measure(
            candidateTexts: list.map(\.text),
            highlightedIndex: rimeContext.highlightedCandidateIndex,
            in: innerWidth,
            chevronWidth: chevronWidth,
            font: UIFont.systemFont(ofSize: theme.candidateCellFontSize),
            barHeight: barHeight,
            selectionHeight: theme.candidateSelectionHeight,
            cellHeight: theme.candidateCellHeight
        )

        return ZStack(alignment: .topTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(metrics.rows.indices, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<metrics.rows[row], id: \.self) { col in
                                let index = metrics.rowStarts[row] + col
                                cell(index: index, list: list, minWidth: metrics.minCellWidth)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, row == 0 ? chevronWidth : 0)
                    }
                }
                .padding(.leading, gridPadding)
                .padding(.trailing, gridPadding)
                .padding(.bottom, gridPadding)
                .padding(.top, metrics.topInset)
            }

            CandidateChevronButton(
                isExpanded: true,
                height: barHeight,
                theme: theme,
                action: onCollapse
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 网格候选单元格：文本左对齐（首列与折叠候选栏首词对齐）。内容自然宽度
    /// （仅设 minWidth），不缩字体、不强塞，放不下由分行逻辑换到下一行。
    @ViewBuilder
    private func cell(index: Int, list: [Candidate], minWidth: CGFloat) -> some View {
        // 惰性网格读的是传入的快照 `list`，若取选中后候选被替换，跳过的单元格
        // 直接返回空视图，绝不越界读取。
        if list.indices.contains(index) {
            let candidate = list[index]
            CandidateCellView(
                text: candidate.text,
                isHighlighted: index == rimeContext.highlightedCandidateIndex,
                theme: theme,
                action: { onSelect(index) }
            )
            .frame(minWidth: minWidth, alignment: .leading)
        } else {
            Color.clear
        }
    }
}

#Preview("Light Keyboard") {
    KeyboardView(
        rimeContext: RimeContext.shared,
        inputState: InputState(),
        onKey: { action in
            print("key: \(action)")
        }
    )
    .preferredColorScheme(.light)
}

#Preview("Dark Keyboard") {
    KeyboardView(
        rimeContext: RimeContext.shared,
        inputState: InputState(),
        onKey: { action in
            print("key: \(action)")
        }
    )
    .preferredColorScheme(.dark)
}
