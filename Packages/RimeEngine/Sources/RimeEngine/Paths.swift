import Foundation

/// 文件系统路径的唯一来源：主 App、键盘扩展、同步层与 RIME 引擎统一从这里
/// 取目录，避免各处散落的 App Group ID / Bundle 探测 / 目录拼接逻辑。
///
/// 设计要点：
/// - App Group 可用时（主 App 与键盘扩展共享容器），用户数据、日志都落在
///   App Group 容器下；否则回退到各自私有的 Application Support / Documents。
/// - `SharedSupport` 是预构建 RIME 数据（`build/*.bin`），部署时复制进主 App
///   bundle；键盘扩展的 `Bundle.main` 是 .appex，需向上回溯宿主 App bundle。
public enum Paths {
    public static let appGroupID = "group.art.anjing.quill"

    public static var appGroupContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// 预构建 RIME 数据目录（`default.yaml` + `build/*.bin`），随主 App 打包。
    public static var sharedSupportDirectory: URL? {
        // 主 App 与键盘扩展的 Bundle.main 不同；向上查找包含 SharedSupport 的宿主 bundle。
        var candidates: [Bundle] = [Bundle.main]
        if let main = Bundle.main.resourceURL {
            let appBundle = main.deletingLastPathComponent().deletingLastPathComponent()
            if let bundle = Bundle(url: appBundle) {
                candidates.append(bundle)
            }
        }
        if let execPath = Bundle.main.executableURL {
            let appex = execPath.deletingLastPathComponent() // .../QuillKeyboard.appex
            let hostApp = appex.deletingLastPathComponent().deletingLastPathComponent() // .../Quill.app
            if let bundle = Bundle(url: hostApp) {
                candidates.append(bundle)
            }
        }
        for bundle in candidates {
            if let url = bundle.url(forResource: "SharedSupport", withExtension: nil) {
                return url
            }
        }
        return nil
    }

    /// 用户数据目录优先使用 App Group（主 App 与键盘扩展共享）；无 App Group
    /// 时回退到应用私有 Application Support 目录。
    public static var userDataDirectory: URL? {
        if let group = appGroupContainer {
            return group.appendingPathComponent("Rime", isDirectory: true)
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return support.appendingPathComponent("Quill/Rime", isDirectory: true)
        }
        return nil
    }

    /// 日志目录：App Group 可用时在组容器下，否则 Documents/Logs（方便文件 App 导出）。
    public static var logDirectory: URL? {
        let base: URL?
        if let group = appGroupContainer {
            base = group
        } else {
            // 无 App Group 时把日志放到 Documents/Logs，方便通过文件 App 导出
            // （键盘扩展无法使用主 App 的 ShareLink，只能靠文件 App 查看）。
            base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        guard let base else { return nil }
        let url = base.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// librime 同步目录（`user_data_dir/sync`，或 installation.yaml 里配置的 sync_dir）。
    public static var syncDirectory: URL? {
        userDataDirectory?.appendingPathComponent("sync", isDirectory: true)
    }
}
