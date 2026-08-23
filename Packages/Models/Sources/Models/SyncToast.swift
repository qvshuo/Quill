import Foundation

/// 手动 WebDAV 同步的 toast 提示（键盘候选区顶部居中的悬浮胶囊）。
/// 纯状态模型：`started` 在同步期间持续展示、结束由控制器替换为
/// `.completed / .failed`；收起的时长不属于状态语义，由订阅方（键盘
/// 控制器）按结果掌握。
public enum SyncToast: Sendable, Equatable {
    case started
    case completed
    case failed

    public var message: String {
        switch self {
        case .started: return "正在同步…"
        case .completed: return "同步完成"
        case .failed: return "同步失败，请检查设置"
        }
    }
}