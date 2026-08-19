import Foundation
import Observation
import Models

/// 输入框宿主状态（由键盘控制器维护，RIME 引擎不感知）：
/// 用于回车键蓝色高亮（`hasInputText`）与同步 toast（`toast`）。
/// 引擎状态（`RimeContext`）只关心 RIME 自身（candidates/preedit/commit），
/// 不再承载宿主导航状态，职责分域。
@MainActor
@Observable
public final class InputState {
    /// 宿主输入框是否有文本（由键盘控制器维护，供回车键蓝色高亮使用）。
    public var hasInputText: Bool = false
    /// 同步瞬时提示（长按空格键触发），KeyboardView 顶部悬浮胶囊据此展示；
    /// 收起的时长由键盘控制器掌握（`InputController.scheduleToastDismissal`）。
    public var toast: SyncToast? = nil

    public init() {}
}