import Foundation
import RimeEngine
import Synchronization

/// WebDAV 同步编排（Squirrel 逻辑）：
/// 1. 清空临时暂存目录
/// 2. 从 WebDAV `Rime_Sync/` 下载所有设备子目录的 `luna_pinyin_extended.userdb.txt` 与 `custom_phrase.txt`
/// 3. 把 `installation.yaml` 的 sync_dir 指到暂存目录
/// 4. 调 librime `RimeSyncUserData`：导出本机词典到 `暂存/<本机ID>/`，并把暂存下所有设备合并进本地词典
/// 5. 把 `暂存/<本机ID>/` 上传回 WebDAV `Rime_Sync/<本机ID>/`
/// 6. 完成后发 Darwin 通知（主 App 可监听刷新状态）
///
/// 只同步 `luna_pinyin_extended.userdb.txt` 与 `custom_phrase.txt` 两个文件，其余一律不处理。
/// 暂存目录每次清空、用完即弃，不保留本地 `Rime_sync/` 缓存（完全以 WebDAV 为准）。
public enum WebDAVSync {
    /// Darwin 通知名：键盘扩展同步完成，主 App 监听后刷新状态。
    public static let completionNotificationName = "com.anjing.quill.webdav.sync.completed"

    /// 远程同步根目录（相对 baseURL）。默认 `Rime_Sync`，可在主 App 设置里自定义。
    public static var syncRootPath: String {
        let saved = WebDAVKeychainStore.load()?.syncPath?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? "Rime_Sync" : saved
    }

    /// 同步暂存目录：每次同步前清空重建。
    static var stagingDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RimeSyncStage", isDirectory: true)
    }

    /// librime 同步（`RimeSyncUserData` + `join_maintenance_thread`）是阻塞式调用，
    /// 不能在 Swift 协作线程池上等待（会饿死同一执行器的其他任务）。放到专用串行队列。
    private static let librimeSyncQueue = DispatchQueue(label: "art.anjing.quill.librime.sync")

    /// 在 librime 同步专用串行队列上执行一段引擎操作（如同步后的会话重建）。
    /// 与在途的 `syncUserData` 按 FIFO 顺序执行，且不阻塞主线程：同步超时后后台
    /// 「僵尸同步」仍可能持引擎锁跑 `syncUserData`，主线程直接调用会阻塞到它结束。
    public static func runAfterSync(_ block: @escaping () -> Void) {
        librimeSyncQueue.async(execute: block)
    }

    /// 在专用队列上执行 librime 同步导出 + 合并。
    private static func runLibrimeSync(context: RimeContext, staging: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            librimeSyncQueue.async {
                // 无论成功与否都复位目录覆盖，避免同步失败后残留暂存指向。
                context.setStagingDirectory(staging)
                defer { context.clearStagingDirectory() }
                do {
                    continuation.resume(returning: try context.syncUserData())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 只同步这两个文件：`luna_pinyin_extended.userdb.txt`（用户词库）和
    /// `custom_phrase.txt`（自定义短语）。其他文件一律不同步。
    private static func relevantFile(_ name: String) -> Bool {
        name == "luna_pinyin_extended.userdb.txt" || name == "custom_phrase.txt"
    }

    /// 单一同步在途标记。超时竞速里「输家」不会被取消，可能仍在后台跑完；
    /// 若此时用户再次触发同步，两次同步会并发清空/读写同一暂存目录与用户词库。
    /// 此标记让并发触发直接跳过，避免两个同步任务交错。
    private static let inFlight = Mutex(false)

    /// 完整同步一次，返回是否成功。进度经 `RimeContext.log()` 记录。
    /// 与上一次同步在途时（含超时后仍在后台跑完的）直接返回 false，不重复执行。
    @discardableResult
    public static func sync() async -> Bool {
        let context = RimeContext.shared
        context.log("WebDAVSync: begin")
        if inFlight.withLock({ $0 }) {
            context.log("WebDAVSync: already in flight, skip")
            return false
        }
        inFlight.withLock { $0 = true }
        defer { inFlight.withLock { $0 = false } }
        guard let credentials = WebDAVKeychainStore.load() else {
            context.log("WebDAVSync: no credentials saved")
            postCompletion()
            return false
        }
        // 引擎层保持后端无关，安装 ID 由同步层按保存的凭据设置。
        RimeContext.installationID = credentials.installationID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Quill"

        let client = WebDAVClient(credentials: credentials)
        let rootPath = syncRootPath

        do {
            // 清空并重建暂存目录
            let staging = stagingDirectory
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

            // 列出 Rime_Sync/ 下的设备目录
            var devices: [String] = []
            do {
                let entries = try await client.listDirectory(relativePath: rootPath)
                devices = entries.filter(\.isDirectory).map(\.name)
                context.log("WebDAVSync: devices under Rime_Sync/ = \(devices)")
            } catch let error as WebDAVClient.WebDAVError {
                // 404 = 目录还不存在，跳过下载，直接导出+上传。
                if case .serverError(let code) = error, code == 404 {
                    context.log("WebDAVSync: Rime_Sync/ not found, will create")
                } else {
                    throw error
                }
            }

            // 下载每个设备目录里的相关文件到暂存
            for device in devices {
                let remoteDir = "\(rootPath)/\(device)"
                let files: [String]
                do {
                    let entries = try await client.listDirectory(relativePath: remoteDir)
                    files = entries.filter { !$0.isDirectory && relevantFile($0.name) }.map(\.name)
                } catch {
                    context.log("WebDAVSync: list \(device) failed: \(error.localizedDescription)")
                    continue
                }
                context.log("WebDAVSync: download \(device): \(files)")
                for file in files {
                    do {
                        let data = try await client.download(relativePath: "\(remoteDir)/\(file)")
                        let localDir = staging.appendingPathComponent(device, isDirectory: true)
                        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
                        try data.write(to: localDir.appendingPathComponent(file), options: .atomic)
                        context.log("WebDAVSync: downloaded \(device)/\(file) (\(data.count) bytes)")
                    } catch {
                        context.log("WebDAVSync: download \(device)/\(file) failed: \(error.localizedDescription)")
                    }
                }
            }

            // 3.5 把其他设备目录里的 custom_phrase.txt 复制进本地用户目录。
            // 注意：librime 同步只合并 *.userdb.txt；custom_phrase.txt 需手动覆盖到
            // 用户目录，下一次会话创建时 StableDb 才会读它。
            if let userDir = Paths.userDataDirectory {
                try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
                for device in devices where device != RimeContext.installationID {
                    let deviceDir = staging.appendingPathComponent(device, isDirectory: true)
                    let source = deviceDir.appendingPathComponent("custom_phrase.txt")
                    if FileManager.default.fileExists(atPath: source.path) {
                        let target = userDir.appendingPathComponent("custom_phrase.txt")
                        try? FileManager.default.removeItem(at: target)
                        try? FileManager.default.copyItem(at: source, to: target)
                        context.log("WebDAVSync: applied custom_phrase.txt from \(device)")
                    }
                }
            }

            // 指向暂存目录并跑 librime 同步（导出 + 合并）。
            let result = try await Self.runLibrimeSync(context: context, staging: staging)
            context.log("WebDAVSync: librime sync done, export dir = \(result.path)")

            // 上传本机导出目录回 WebDAV。单个文件读写失败不中断整体同步，
            // 仅记录日志（跳过该文件）。
            let ownID = RimeContext.installationID
            let ownDir = staging.appendingPathComponent(ownID, isDirectory: true)
            // 首次同步时同步根目录可能尚未创建，先 MKCOL 根目录再建本机目录
            // （父目录缺失时 MKCOL 子目录会返回 409；MKCOL 已存在目录返回 405，视为成功）。
            try await client.createDirectory(relativePath: rootPath)
            try await client.createDirectory(relativePath: "\(rootPath)/\(ownID)")
            if let files = try? FileManager.default.contentsOfDirectory(
                at: ownDir, includingPropertiesForKeys: nil
            ) {
                for file in files where relevantFile(file.lastPathComponent) {
                    guard let data = try? Data(contentsOf: file) else {
                        context.log("WebDAVSync: read \(ownID)/\(file.lastPathComponent) failed, skip")
                        continue
                    }
                    do {
                        let remote = "\(rootPath)/\(ownID)/\(file.lastPathComponent)"
                        try await client.upload(relativePath: remote, data: data)
                        context.log("WebDAVSync: uploaded \(ownID)/\(file.lastPathComponent) (\(data.count) bytes)")
                    } catch {
                        context.log("WebDAVSync: upload \(ownID)/\(file.lastPathComponent) failed: \(error.localizedDescription)")
                    }
                }
            }
            context.log("WebDAVSync: completed")
            // 只有同步成功才推进「最近同步于」时间戳；失败不写（主 App 读到的仍是上次成功时间）。
            WebDAVKeychainStore.saveLastSyncDate(Date())
            postCompletion()
            return true
        } catch {
            context.log("WebDAVSync: failed: \(error.localizedDescription)")
            postCompletion()
            return false
        }
    }

    /// 带超时的同步。到 `timeout` 仍未结束即返回 `false`。
    ///
    /// 实现用「竞速」而非「取消」：`runLibrimeSync` 在专用阻塞队列上等待 librime，
    /// 中途取消任务会让 `withCheckedThrowingContinuation` 与队列回调出现
    /// 双 resume 崩溃。这里两个子任务互不取消，先到者胜——超时后同步在后台
    /// 继续跑完（结果被丢弃，用户目录/字典合并无害），键盘 UI 不被阻塞。
    @discardableResult
    public static func syncWithTimeout(_ timeout: Duration = .seconds(15)) async -> Bool {
        await withCheckedContinuation { continuation in
            let winner = RaceWinner()
            let syncTask = Task {
                let result = await sync()
                winner.finish(result: result, continuation)
            }
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                winner.finish(result: false, continuation)
            }
            // 两个 Task 被子闭包强持有即可保持存活；输家跑完即被丢弃。
            _ = syncTask
            _ = timeoutTask
        }
    }

    /// 竞速辅助：两个子任务谁先调用 `finish` 就 resume 一次，后到者忽略
    /// （`CheckedContinuation` 只能 resume 一次）。
    private final class RaceWinner: Sendable {
        private let winner = Mutex(false)

        func finish(result: Bool, _ continuation: CheckedContinuation<Bool, Never>) {
            let shouldResume = winner.withLock { state in
                if state { return false }
                state = true
                return true
            }
            if shouldResume {
                continuation.resume(returning: result)
            }
        }
    }

    /// 发 Darwin 通知，主 App 可监听后刷新状态。
    /// 注意：Darwin 通知不携带 payload，观察者无法据此区分同步成功/失败；
    /// 成功与否应以 `WebDAVKeychainStore.loadLastSyncDate()` 或本函数返回值判断。
    /// `deliverImmediately` 固定传 `true`，进程内同步送达观察者。
    private static func postCompletion() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(completionNotificationName as CFString),
            nil,
            nil,
            true
        )
    }
}
