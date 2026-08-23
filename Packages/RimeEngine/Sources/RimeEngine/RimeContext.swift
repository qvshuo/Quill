import Foundation
import Observation
import Models
@preconcurrency import RimeEngineC

/// 进程内单例 RIME 上下文。桥接对齐 Squirrel：Swift 直接持有 `RimeApi_stdbool`
/// 调用 librime C API，无 ObjC 包装层。
///
/// 生命周期：每个进程只 `start()` 一次（键盘扩展 `viewDidLoad` / 主 App 设置页
/// `.task`），start = setup → initialize，不做 deploy（数据预构建，见 AGENTS.md
/// 「No deploy path」）。setup 完成前 `processKey` 丢键（`isReady` 守卫）。
/// glog 每进程只允许 `setup()` 一次，`isSetup` 仅作兜底。
///
/// 方法按职责拆在 `RimeContext+*.swift` extension 文件中；本文件只保留类声明与
/// 共享内部状态。内部存储属性为 `internal`（模块内），供 extension 文件访问。
/// `librime` 非线程安全：所有 C API 调用都持 `lock`（NSRecursiveLock）执行。
@Observable
public final class RimeContext: @unchecked Sendable {
    public static let shared = RimeContext()

    // MARK: - librime direct bridge

    let rimeAPI: RimeApi_stdbool = rime_get_api_stdbool()!.pointee
    let lock = NSRecursiveLock()

    var isSetup = false
    var isStarting = false
    /// setup 完成、可以处理按键。
    var isReady = false
    var session: RimeSessionId = 0
    /// 会话创建后应写入的 `ascii_mode` 初始值；会话未创建时先 pending。
    /// `.asciiCapable` 字段需要英文模式，`.default` 需要中文模式。
    var pendingAsciiMode: Bool = false

    /// 每次刷新一次性取回的候选数（初始直接 77，支持展开网格）。
    let candidateBatchSize = 77

    // MARK: - Observable state

    public internal(set) var candidates: [Candidate] = []
    public internal(set) var preedit: String = ""
    public internal(set) var highlightedCandidateIndex: Int = 0
    /// 一次性 commit 缓冲：只经 `pollCommit()` 消费，无 UI 观察者。
    /// 标记 `@ObservationIgnored`：它在持锁下由任意线程（含同步队列的
    /// `recreateSession`）写入，不能走「只在主线程写」的可观察状态通道。
    @ObservationIgnored public internal(set) var commitText: String = ""

    let logFileName = "quill.log"

    private init() {}
}

extension RimeContext {
    public enum RimeError: Error, LocalizedError {
        case missingDirectory
        case syncFailed

        public var errorDescription: String? {
            switch self {
            case .missingDirectory: return "无法定位 RIME 数据目录"
            case .syncFailed: return "同步失败"
            }
        }
    }
}
