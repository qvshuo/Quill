import SwiftUI
import Models

/// 单个按键视图：完全纯色键帽（无阴影/描边/渐变/按压高亮）+ 字符键按压气泡。
public struct Key: View {
    let descriptor: KeyDescriptor
    let theme: Theme
    let shiftState: ShiftState
    let action: (KeyAction) -> Void

    @State private var isPressed = false
    @State private var repeater: KeyPressRepeater?
    /// 空格键 5 秒长按定时器与触发标记。
    @State private var spaceHoldWorkItem: DispatchWorkItem?
    @State private var spaceHoldTriggeredSync = false
    private static let spaceSyncHoldDuration: TimeInterval = 5.0

    private var isRepeatable: Bool {
        descriptor.action.isBackspace
    }

    private var isSpaceAction: Bool {
        descriptor.action.isSpace
    }

    /// 仅字符键显示按压气泡；数字和符号布局在解析时同样使用 `.character`。
    private var previewText: String? {
        guard case .character = descriptor.action else { return nil }
        return descriptor.label
    }

    public init(
        descriptor: KeyDescriptor,
        theme: Theme,
        shiftState: ShiftState = .lowercase,
        action: @escaping (KeyAction) -> Void
    ) {
        self.descriptor = descriptor
        self.theme = theme
        self.shiftState = shiftState
        self.action = action
    }

    public var body: some View {
        Group {
            if isRepeatable {
                repeatableKeyBody
            } else if isSpaceAction {
                spaceKeyBody
            } else {
                Button(action: { action(descriptor.action) }) {
                    keyLabel
                        .foregroundStyle(foregroundColor)
                }
                .buttonStyle(
                    KeyButtonStyle(
                        theme: theme,
                        style: descriptor.style,
                        previewText: previewText,
                        pressed: $isPressed
                    )
                )
            }
        }
        .zIndex(isPressed ? 1 : 0)
    }

    /// 退格支持长按连续输入：按下立即触发一次，长按 0.5s 后每 0.1s 重复。
    ///
    /// 用 UIKit 触摸回调（touchesBegan/touchesEnded/touchesCancelled）驱动起停：
    /// SwiftUI 的 DragGesture 在键盘扩展里松手时 onEnded 不可靠，会导致退格
    /// 松手后仍持续触发（尤其是被系统手势中断时不会走到 onEnded）。
    private var repeatableKeyBody: some View {
        keyLabel
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .keyBackground(
                isPressed: isPressed,
                style: descriptor.style,
                theme: theme
            )
            .contentShape(Rectangle())
            // 显式覆盖系统默认按键动效（约 0.2s）：默认太慢产生迟滞感。
            .animation(.easeOut(duration: 0.05), value: isPressed)
            .overlay {
                KeyTouchTracker(
                    onPress: {
                        guard !isPressed else { return }
                        isPressed = true
                        // 在 UIKit 触摸回调里直接触发震动，比 SwiftUI onChange 更可靠，
                        // 系统手势中断时也不会丢震动。
                        KeyboardFeedback.play()
                        if repeater == nil {
                            repeater = KeyPressRepeater(
                                fire: { action(descriptor.action) },
                                feedback: { KeyboardFeedback.play() }
                            )
                        }
                        repeater?.startPress()
                    },
                    onRelease: {
                        isPressed = false
                        repeater?.endPress()
                    }
                )
            }
            .onDisappear {
                repeater?.endPress()
            }
    }

    /// 空格键：单击上屏空格（双击=句号逻辑由控制器处理），长按 5 秒触发手动同步。
    /// 不重复连打空格；长按期间松手则按普通空格处理，满 5 秒才触发同步并吞掉本次松手。
    private var spaceKeyBody: some View {
        keyLabel
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .keyBackground(
                isPressed: isPressed,
                style: descriptor.style,
                theme: theme
            )
            .contentShape(Rectangle())
            // 显式覆盖系统默认按键动效（约 0.2s）：默认太慢产生迟滞感。
            .animation(.easeOut(duration: 0.05), value: isPressed)
            .overlay {
                KeyTouchTracker(
                    onPress: {
                        guard !isPressed else { return }
                        isPressed = true
                        KeyboardFeedback.play()
                        startSpaceHoldTimer()
                    },
                    onRelease: {
                        isPressed = false
                        cancelSpaceHoldTimer()
                        // 长按满 5 秒已触发同步，本次松手不再输入空格。
                        if !spaceHoldTriggeredSync {
                            action(.space)
                        }
                    }
                )
            }
            .onDisappear {
                cancelSpaceHoldTimer()
            }
    }

    /// 空格长按 5 秒后触发同步。
    private func startSpaceHoldTimer() {
        spaceHoldTriggeredSync = false
        spaceHoldWorkItem?.cancel()
        // self 是结构体值拷贝，闭包内通过 @State 的非 mutating setter 写共享存储即可。
        let item = DispatchWorkItem { [self] in
            self.spaceHoldTriggeredSync = true
            KeyboardFeedback.play()
            self.action(.startSync)
        }
        spaceHoldWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.spaceSyncHoldDuration, execute: item)
    }

    private func cancelSpaceHoldTimer() {
        spaceHoldWorkItem?.cancel()
        spaceHoldWorkItem = nil
    }

    @ViewBuilder
    private var keyLabel: some View {
        switch descriptor.action {
        case .backspace:
            Image(systemName: "delete.left")
                .font(.system(size: 21, weight: .medium))
        case .space:
            Color.clear
        case .return:
            Text(descriptor.label)
                .font(.system(size: theme.specialKeyFontSize, weight: .regular))
        case .numbers, .letters, .symbols, .toggleLanguage:
            Text(descriptor.label)
                .font(.system(size: theme.specialKeyFontSize, weight: .regular))
        case .shift:
            Image(systemName: shiftImageName)
                .font(.system(size: 21, weight: shiftState == .uppercaseLocked ? .semibold : .medium))
                .scaleEffect(shiftState == .uppercaseLocked ? 1.2 : 1.0)
                .animation(.easeOut(duration: 0.1), value: shiftState)
                .accessibilityLabel("大小写")
        default:
            Text(descriptor.label)
                .font(theme.font)
        }
    }

    /// shift 处于激活（一次大写或大写锁定）时显示实心上箭头，与原生输入法一致。
    private var shiftImageName: String {
        switch shiftState {
        case .uppercaseOnce, .uppercaseLocked:
            return "shift.fill"
        case .lowercase:
            return "shift"
        }
    }

    private var foregroundColor: Color {
        switch descriptor.style {
        case .confirm:
            // 确认键按压时底色变为统一按压色（见 Theme.fillColor），
            // 前景同步换成 keyForeground，避免亮底亮字隐身（fcitx5-ios EnterView 同款）。
            return isPressed ? theme.keyForeground : .white
        case .special:
            return theme.specialKeyForeground
        default:
            return theme.keyForeground
        }
    }
}

private struct KeyButtonStyle: ButtonStyle {
    let theme: Theme
    let style: KeyStyle
    let previewText: String?
    let pressed: Binding<Bool>

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .keyBackground(
                isPressed: configuration.isPressed,
                style: style,
                theme: theme
            )
            .contentShape(Rectangle())
            // 显式覆盖系统默认按键动效（约 0.2s）：默认太慢产生迟滞感。
            .animation(.easeOut(duration: 0.05), value: configuration.isPressed)
            .overlay(alignment: .top) {
                if configuration.isPressed, let previewText {
                    Text(previewText)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(theme.keyForeground)
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                // 不透明背景：气泡悬浮于键帽上方，深色若用半透明
                                // 叠加会透出键缝/面板显得「透明」（Theme token 保证）。
                                .fill(theme.previewBubbleBackground)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
                        .offset(y: -47)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: configuration.isPressed) { _, isPressed in
                pressed.wrappedValue = isPressed
                if isPressed {
                    KeyboardFeedback.play()
                }
            }
    }
}
