import Foundation

/// 手动 WebDAV 同步的 toast 提示（键盘候选区顶部居中的悬浮胶囊）。
/// 纯状态模型：`started` 在同步期间持续展示、结束由控制器替换为
/// `.completed / .timedOut / .failed`；收起的时长不属于状态语义，由订阅方
/// （键盘控制器）按结果掌握。
public enum SyncToast: Sendable, Equatable {
    case started
    case completed
    /// 超时判负但同步仍在后台跑（竞速不取消输家），最终大概率完成。
    case timedOut
    case failed

    public var message: String {
        switch self {
        case .started: return "正在同步…"
        case .completed: return "同步完成"
        case .timedOut: return "同步超时，仍在后台进行"
        case .failed: return "同步失败，请检查设置"
        }
    }
}