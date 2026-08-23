import Foundation

extension RimeContext {
    // MARK: - Logging

    /// 生命周期 / 错误级日志。打到 stderr（被 `redirectStderrToLogFile()` 统一
    /// 捕获进 quill.log）。不在按键热路径上调用。
    public func log(_ message: String) {
        let ts = Date().formatted(date: .omitted, time: .shortened)
        let line = "[\(ts)] \(message)"
        line.withCString { str in
            fputs(str, stderr)
            fputs("\n", stderr)
        }
    }

    public func exportLogURL() -> URL? {
        Paths.logDirectory?.appendingPathComponent(logFileName)
    }

    /// 把 stderr（NSLog / glog 输出）重定向到日志文件，这样 App 主页的日志
    /// 才能看到 RIME 引擎的真实日志。fcitx5-ios 同款做法。
    /// 每次启动检查文件大小，超过阈值时轮转一次（quill.log → quill.log.old），
    /// 防止 stderr 重定向让日志文件无限增长。
    private static let maxLogFileSize: UInt64 = 1 << 20 // 1 MiB

    public func redirectStderrToLogFile() {
        guard let url = Paths.logDirectory?.appendingPathComponent(logFileName) else { return }
        // 先回收 librime glog 每次进程遗留的文件：它们不自动清理，会无限累积。
        // 只保留 quill.log 与其 .old 轮转件；真正的 RIME/glog 详情仍走 stderr 进 quill.log。
        pruneGlogFiles()
        rotateLogFileIfNeeded(url)
        // withCString 保证 C 路径指针在 fopen 调用期间存活（`(NSString).utf8String`
        // 的指针只保证存活到当前表达式结束，跨语句使用是悬垂模式）。
        guard let file = url.path.withCString({ fopen($0, "a") }) else { return }
        dup2(fileno(file), STDERR_FILENO)
        fclose(file)
    }

    /// 删除 `Paths.logDirectory` 里非 `quill.log(.old)` 的残留文件（glog 按
    /// 进程名+级别+pid 生成 `*.INFO/WARNING/ERROR/FATAL`，含轮转后缀，长期累积）。
    private func pruneGlogFiles() {
        guard let dir = Paths.logDirectory else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        let keep = Set([logFileName, logFileName + ".old"])
        for url in files where !keep.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }

    private func rotateLogFileIfNeeded(_ url: URL) {
        let path = url.path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard let size = attributes?[.size] as? NSNumber, size.uint64Value >= Self.maxLogFileSize else { return }
        let oldPath = path + ".old"
        try? FileManager.default.removeItem(atPath: oldPath)
        try? FileManager.default.moveItem(atPath: path, toPath: oldPath)
    }
}
