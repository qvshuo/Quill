import Foundation
import Synchronization

extension RimeContext {
    // MARK: - Sync (安装信息 / 用户词典同步)

    /// 本设备在同步目录里的安装 ID，即 `sync/<installation_id>/` 子目录名。
    /// 默认 "Quill"；同步层（Sync）在开始同步前按保存的凭据设置实际值。
    /// 引擎层保持后端无关，不读取网络凭据。主线程与同步后台队列都可能读写，用锁保护。
    private static let installationIDStorage = Mutex<String>("Quill")
    public static var installationID: String {
        get { installationIDStorage.withLock { $0 } }
        set { installationIDStorage.withLock { $0 = newValue } }
    }

    /// librime 同步目录（`user_data_dir/sync`，或 installation.yaml 里配置的 sync_dir）。
    /// 同步期间 installation.yaml 的 sync_dir 会被改写为暂存目录，本目录仅作启动时默认值。
    // MARK: - Sync (暂存目录覆盖)

    /// 同步期间的暂存目录覆盖。设置后 `sync_dir` 与导出目录都指向暂存目录
    /// （每次同步清空重建，不保留本地 `Rime_sync/` 缓存）。同步结束后应清空。
    /// 主 App 与键盘扩展、以及同步后台任务都会读写，用锁保护。
    private static let stagingDirectoryOverrideStorage = Mutex<URL?>(nil)
    private static var stagingDirectoryOverride: URL? {
        get { stagingDirectoryOverrideStorage.withLock { $0 } }
        set { stagingDirectoryOverrideStorage.withLock { $0 = newValue } }
    }

    /// 让 installation.yaml 的 `sync_dir` 指向同步暂存目录，并记录导出目录。
    /// 同步完成后调用 `clearStagingDirectory()` 复位。
    public func setStagingDirectory(_ stagingDir: URL) {
        Self.stagingDirectoryOverride = stagingDir
        try? FileManager.default.createDirectory(
            at: stagingDir, withIntermediateDirectories: true
        )
        // 重写 installation.yaml（sync_dir → staging）。
        rewriteInstallationInfo(syncDir: stagingDir)
    }

    public func clearStagingDirectory() {
        Self.stagingDirectoryOverride = nil
    }

    /// 确保 `installation.yaml` 里的 `installation_id` 为当前安装 ID，并开启配置备份
    /// （`backup_config_files`，否则 librime 不会把 `*.custom.yaml` / `custom_phrase.txt`
    /// 备份进同步目录）。
    /// `sync_dir` 指向同步暂存目录（覆盖生效时），否则为本地默认 `user_data_dir/sync`
    /// （实际同步只经暂存覆盖，本地目录仅为满足 librime installation.yaml 合法）。
    func ensureInstallationInfo() {
        guard let dir = Paths.userDataDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let root = Self.stagingDirectoryOverride ?? Paths.syncDirectory ?? dir
        try? FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )

        rewriteInstallationInfo(syncDir: root)
    }

    /// 写入 installation.yaml：`installation_id` + `backup_config_files` + `sync_dir`。
    private func rewriteInstallationInfo(syncDir: URL) {
        guard let dir = Paths.userDataDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: syncDir, withIntermediateDirectories: true
        )

        let file = dir.appendingPathComponent("installation.yaml")
        var lines = (try? String(contentsOf: file, encoding: .utf8))?
            .components(separatedBy: .newlines) ?? []
        lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("installation_id:") }
        lines.insert("installation_id: \"\(Self.installationID)\"", at: 0)
        lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("backup_config_files:") }
        lines.append("backup_config_files: true")
        lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("sync_dir:") }
        lines.append("sync_dir: \"\(syncDir.path)\"")
        try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        log("sync_dir = \(syncDir.path)")
    }

    /// 跑一次 librime 同步：把本机用户词典导出到同步暂存目录的
    /// `<installation_id>/` 下，并合并暂存目录里其他设备的 `*.userdb.txt`。
    /// 必须先 `setStagingDirectory(_:)` 设置暂存目录，否则抛 `missingDirectory`。
    /// `RimeSyncUserData` 异步执行，须 `join_maintenance_thread` 等待完成。
    /// 持锁执行：librime 非线程安全，若与输入热路径（processKey）并发会崩。
    @discardableResult
    public func syncUserData() throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        guard let staging = Self.stagingDirectoryOverride else {
            throw RimeError.missingDirectory
        }
        let exportDir = staging.appendingPathComponent(Self.installationID, isDirectory: true)
        guard let sync = rimeAPI.sync_user_data else {
            throw RimeError.syncFailed
        }
        try? FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        guard sync() else {
            throw RimeError.syncFailed
        }
        rimeAPI.join_maintenance_thread!()
        return exportDir
    }
}