import UIKit
import SwiftUI
import RimeEngine
import Sync
import Models
import KeyboardUI

/// 键盘扩展入口。职责极薄：组合 KeyboardUI + RimeEngine。
final class InputController: UIInputViewController {

    private let rimeContext = RimeContext.shared
    private let inputState = InputState()
    private var displayedPreedit: String = ""
    private var hostingController: UIHostingController<KeyboardView>?
    private var doubleSpaceTracker = DoubleSpaceTracker(interval: 0.35)

    /// 最近一次写入视图的键盘类型 / 回车键类型，用于在字段切换时按需刷新。
    private var lastKeyboardType: UIKeyboardType?
    private var lastReturnKeyType: UIReturnKeyType?

    /// 手动同步（长按空格键 5 秒触发）是否进行中，防止重复触发。
    private var isSyncing = false

    /// `.completed / .failed` toast 的自动收起任务。收起时长由控制器掌握
    /// （模型 `SyncToast` 不承载计时语义），新一次同步会取消上一次的收起。
    private var toastDismissTask: Task<Void, Never>?

    deinit {
        rimeContext.destroySession()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        recordFullAccessState()
        // 键盘扩展只 start()：全量部署内存远超 ~77MB 上限会被 Jetsam 杀死，数据来自
        // Bundle 内预构建的 SharedSupport/build。beginStart 串行化保证不会重复触发。
        rimeContext.log("Keyboard: viewDidLoad")
        Task {
            await rimeContext.start()
        }

        createKeyboardView()
        // 在 viewDidLoad 尽早预热震动引擎，减少首次按键反馈的迟滞。
        KeyboardFeedback.prepare()
    }

    /// 把「允许完全访问」状态写入共享 App Group 默认值，供主 App 判断是否提示授权。
    /// 无完全访问权限时键盘没有共享容器写权限（写入静默失败），因此该键实际只可能
    /// 被写成 true；用户关闭完全访问后扩展无法再向共享容器写入 false——撤销动作
    /// 在扩展侧不可观测，只能等权限恢复后重新写回 true。
    private func recordFullAccessState() {
        UserDefaults(suiteName: Paths.appGroupID)?.set(hasFullAccess, forKey: "hasFullAccess")
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshInputTextState()
        refreshKeyboardContext()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 首次出现时同步键盘类型与输入框文本状态（textDidChange 不一定先于 viewWillAppear 触发）。
        refreshInputTextState()
        refreshKeyboardContext()
        // fcitx5-ios 同款：viewDidLoad 挂载会造成巨大布局位移，须在 viewWillAppear 挂载。
        // 高度由 SwiftUI .frame(height:) 内在尺寸决定，无需 preferredContentSize。
        // 幂等挂载：viewWillAppear 可多次触发，重复 addChild / activate 约束会累积。
        guard let hostingController, hostingController.view.superview == nil else { return }
        addChild(hostingController)
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)

        view.window?.gestureRecognizers?.forEach { recognizer in
            // 只修改普通手势识别器，避免触碰系统 gate gesture recognizer 产生警告。
            let className = String(describing: type(of: recognizer))
            if !className.contains("System") {
                recognizer.delaysTouchesBegan = false
            }
        }
    }

    /// 读取宿主的键盘类型 / 回车键文案；仅在发生变化时重建 SwiftUI 根视图。
    private func refreshKeyboardContext() {
        let type = textDocumentProxy.keyboardType
        let returnType = textDocumentProxy.returnKeyType
        guard type != lastKeyboardType || returnType != lastReturnKeyType else { return }
        lastKeyboardType = type
        lastReturnKeyType = returnType
        hostingController?.rootView = makeKeyboardView()
    }

    /// 判断目标输入框是否已有文本（用于右下角回车键高亮）。
    /// 优先使用 `UIKeyInput.hasText`；部分字段的 document context 不可靠，再用上下文兜底。
    private func hasText(in proxy: UITextDocumentProxy) -> Bool {
        if proxy.hasText { return true }
        return !(proxy.documentContextBeforeInput?.isEmpty ?? true)
            || !(proxy.documentContextAfterInput?.isEmpty ?? true)
            || !(proxy.selectedText?.isEmpty ?? true)
    }

    /// 字段聚焦/切换时以 proxy 为准刷新「输入框有文本」状态。
    private func refreshInputTextState() {
        inputState.hasInputText = hasText(in: textDocumentProxy)
    }

    private func createKeyboardView() {
        let hostingController = UIHostingController(rootView: makeKeyboardView())
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        // 参考 fcitx5-ios：UIKit 层完全透明，面板背景由系统键盘容器统一绘制。
        // 深浅色由 SwiftUI @Environment(\.colorScheme) 自动跟随系统（fcitx5-ios 同款）。
        hostingController.view.backgroundColor = .clear
        view.backgroundColor = .clear
        self.hostingController = hostingController
    }

    private func makeKeyboardView() -> KeyboardView {
        KeyboardView(
            rimeContext: rimeContext,
            inputState: inputState,
            keyboardType: textDocumentProxy.keyboardType ?? .default,
            returnKeyType: textDocumentProxy.returnKeyType ?? .default,
            onKey: { [weak self] action in
                self?.handleKeyAction(action)
            }
        )
    }

    private func handleKeyAction(_ action: KeyAction) {
        var handled = false
        var preeditBefore: String = ""
        switch action {
        case .character(let char):
            resetDoubleSpaceState()
            let keyCode = rimeKeyCode(forCharacter: char) ?? 0
            handled = rimeContext.processKey(keyCode)
            // 英文（ascii_mode）下 RIME 不接管纯 ASCII 字符，返回「未处理」，
            // 直接上屏字符本身；有 preedit 时说明仍在组合，不插字。
            if !handled && rimeContext.preedit.isEmpty {
                insertToProxy(char)
                displayedPreedit = ""
            }
        case .directInput(let text):
            if text == " " {
                if !handleDoubleSpaceAsPeriod(".") {
                    insertToProxy(" ")
                    markLiteralSpaceInserted()
                }
                return
            }
            resetDoubleSpaceState()
            commitPendingComposition()
            insertToProxy(text)
            return
        case .backspace:
            // 退格不消耗一次性大写状态。
            resetDoubleSpaceState()
            // 无拼音 preedit 时无需经过 RIME，直接删字符（更快且避免丢震动）。
            if rimeContext.preedit.isEmpty {
                textDocumentProxy.deleteBackward()
                displayedPreedit = ""
            } else {
                handled = rimeContext.processKey(XK_BackSpace)
                if !handled {
                    textDocumentProxy.deleteBackward()
                    displayedPreedit = ""
                }
            }
        case .space:
            // 空格不消耗一次性大写状态（在英文模式下保持首字母大写）。
            // 组合期间空格交 RIME 上屏；双击句号转换只在两次都上屏字面空格时生效
            // （组合期第一下是「选词」，随后快速第二下应是补一个空格，而非变成句号）。
            if rimeContext.preedit.isEmpty, handleDoubleSpaceAsPeriod("。") {
                return
            }
            // 无拼音 preedit 时跳过 RIME，直接上屏字面空格。
            if rimeContext.preedit.isEmpty {
                insertToProxy(" ")
                markLiteralSpaceInserted()
                return
            }
            handled = rimeContext.processKey(XK_space)
            if !handled {
                insertToProxy(" ")
                markLiteralSpaceInserted()
            } else {
                // 组合期上屏候选：复位双击状态，让紧随的第二次空格按普通空格处理。
                resetDoubleSpaceState()
            }
        case .startSync:
            resetDoubleSpaceState()
            startManualSync()
            return
        case .return:
            resetDoubleSpaceState()
            // 无拼音 preedit 时跳过 RIME，直接换行。
            if rimeContext.preedit.isEmpty {
                insertToProxy("\n")
                return
            }
            preeditBefore = rimeContext.preedit
            handled = rimeContext.processKey(XK_Return)
        case .selectCandidate(let index):
            resetDoubleSpaceState()
            rimeContext.selectCandidate(at: index)
            handled = true
        case .toggleLanguage:
            resetDoubleSpaceState()
            // ascii_mode 选项由 KeyboardView 在 onKey 返回后写入 RIME。
            commitPendingComposition()
            return
        default:
            resetDoubleSpaceState()
            break
        }

        if handled {
            syncText()
        }

        // Return 回退：如果 RIME 没有产生 commit 且 preedit 仍保留，直接把原始输入上屏。
        if case .return = action,
           !preeditBefore.isEmpty,
           rimeContext.preedit == preeditBefore {
            commitRawPreedit(preeditBefore)
        }
    }

    /// 长按空格键 5 秒触发的手动 WebDAV 同步：
    /// 同步中 → 销毁并重启 RIME 会话（让新词生效）→ 同步完成（toast 由控制器收起）。
    private func startManualSync() {
        guard !isSyncing else { return }
        // 有未提交的拼音组合时放弃同步：打断组合会丢 preedit / 候选，
        // 且同步完成后重建会话本就是按 preedit 空判断的，这里直接不开始。
        guard rimeContext.preedit.isEmpty else { return }
        isSyncing = true
        toastDismissTask?.cancel()
        inputState.toast = .started
        rimeContext.log("Keyboard: manual WebDAV sync (space long-press)")
        let rime = rimeContext
        // 弱引用持有：同步可能耗时（最坏 15s 超时 + 后台僵尸同步跑完），键盘被收起时
        // 不应把控制器 / 输入状态一直保留到任务结束。
        Task { [weak self] in
            let success = await WebDAVSync.syncWithTimeout(.seconds(15))
            rime.log("Keyboard: manual WebDAV sync done success=\(success)")
            await MainActor.run {
                guard let self else { return }
                // 销毁并重启 RIME：让合并后的用户词库 / custom_phrase 生效。
                // 有未提交的组合时保留会话，避免丢 preedit。
                if self.rimeContext.preedit.isEmpty {
                    // 在同步专用串行队列上重建会话：超时后后台僵尸同步仍可能持引擎锁跑
                    // syncUserData，主线程直接调用会阻塞到它结束（键盘假死）。
                    // 直接捕获 context 单例，不经过 self——否则闭包会把控制器强持有
                    // 到僵尸同步结束（最坏 15s+）。
                    let rimeForRecreate = self.rimeContext
                    WebDAVSync.runAfterSync {
                        rimeForRecreate.recreateSession()
                    }
                }
                let toast: SyncToast = success ? .completed : .failed
                self.inputState.toast = toast
                self.isSyncing = false
                self.scheduleToastDismissal(for: toast)
            }
        }
    }

    /// `.completed / .failed` 停留片刻后自动收起；`started` 由同步结束直接替换。
    private func scheduleToastDismissal(for toast: SyncToast) {
        let delay: TimeInterval = toast == .failed ? 4.0 : 2.5
        toastDismissTask?.cancel()
        let state = inputState
        let task = Task { [weak state] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run { state?.toast = nil }
        }
        toastDismissTask = task
    }

    /// 提交当前拼音组合：优先空格确认，否则直接上屏 preedit 原文。
    private func commitPendingComposition() {
        guard !rimeContext.preedit.isEmpty else { return }
        if rimeContext.processKey(XK_space) {
            syncText()
        } else {
            commitRawPreedit(rimeContext.preedit)
        }
    }

    /// 直接上屏 preedit 原文并重置 RIME（用于 RIME 未确认/未处理组合的兜底提交）。
    private func commitRawPreedit(_ text: String) {
        commitReplacingMarkedText(text)
        rimeContext.reset()
        displayedPreedit = ""
    }

    /// 双击空格转换为句号：命中判定时回删上一次上屏的字面空格并插入 `periodText`，
    /// 返回 true 表示本次空格已被消费；未命中返回 false，由调用方按空格语义处理。
    private func handleDoubleSpaceAsPeriod(_ periodText: String) -> Bool {
        guard doubleSpaceTracker.isDoubleTap() else { return false }
        if doubleSpaceTracker.lastTapInsertedLiteralSpace {
            textDocumentProxy.deleteBackward()
        }
        insertToProxy(periodText)
        doubleSpaceTracker.reset()
        return true
    }

    private func markLiteralSpaceInserted() {
        doubleSpaceTracker.markLiteralSpaceInserted()
    }

    /// 本键盘向输入框上屏文本，并标记输入框已有文本。
    private func insertToProxy(_ text: String) {
        textDocumentProxy.insertText(text)
        markInputTextInserted()
    }

    /// 本键盘向输入框上屏了非空文本后，标记输入框已有文本。
    private func markInputTextInserted() {
        inputState.hasInputText = true
    }

    /// 上屏最终文本（候选词 / preedit 原文）。组合期间宿主字段里的 marked 区是
    /// 原始拼音，直接 `unmarkText()` 会把拼音固化进文档、随后的插入变成「拼音+候选」
    /// 拼接（部分 host 不替换 marked range）。改为用 setMarkedText 以最终文本
    /// 覆盖 marked 区后再固化；无 marked 区时按普通插入处理。
    private func commitReplacingMarkedText(_ text: String) {
        if displayedPreedit.isEmpty {
            insertToProxy(text)
        } else {
            let end = text.utf16.count
            textDocumentProxy.setMarkedText(text, selectedRange: NSRange(location: end, length: 0))
            textDocumentProxy.unmarkText()
            markInputTextInserted()
        }
    }

    private func resetDoubleSpaceState() {
        doubleSpaceTracker.reset()
    }

    /// 把 RIME 的 commit / preedit 同步进宿主输入框（marked 区维护）。
    /// 清空组合必须 `setMarkedText("")` + `unmarkText()`：裸 `unmarkText()` 会把
    /// 最后一个 marked 字母固化进文档，表现为需要两次退格。
    private func syncText() {
        if let commit = rimeContext.pollCommit(), !commit.isEmpty {
            commitReplacingMarkedText(commit)
            displayedPreedit = ""
        }

        let preedit = rimeContext.preedit
        if preedit != displayedPreedit {
            if preedit.isEmpty {
                textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
                textDocumentProxy.unmarkText()
            } else {
                let end = preedit.utf16.count
                textDocumentProxy.setMarkedText(preedit, selectedRange: NSRange(location: end, length: 0))
            }
            displayedPreedit = preedit
        }
    }
}

/// 双击空格 → 句号的状态跟踪。空格是「双语义」键：可能上屏字面空格（英文/数字页
/// 或 RIME 未接管），也可能交给 RIME（组合期上屏候选）。双击句号只在两次都上屏
/// 字面空格时生效：组合期第一下上屏候选后双击状态被复位，随后快速第二下按普通
/// 空格处理（选词 + 补空格），不会误转成句号。故需同时记录按键时刻与上一次是否
/// 真的上屏了字面空格，双击命中后回删该空格再插入句号。
private struct DoubleSpaceTracker {
    var lastTap = Date.distantPast
    var lastTapInsertedLiteralSpace = false
    let interval: TimeInterval

    /// 距上次记录的空格按键是否在双击窗口内（不消费状态）。
    func isDoubleTap(_ now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastTap) < interval
    }

    /// 本次空格上屏了字面空格。
    mutating func markLiteralSpaceInserted(_ now: Date = Date()) {
        lastTap = now
        lastTapInsertedLiteralSpace = true
    }

    /// 双击命中后复位（已回删旧空格并插入句号）。
    mutating func reset() {
        lastTap = .distantPast
        lastTapInsertedLiteralSpace = false
    }
}
