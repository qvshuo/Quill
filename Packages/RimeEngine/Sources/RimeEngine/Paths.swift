import Foundation

/// 文件系统路径唯一来源：主 App、键盘扩展、同步层统一从这里取目录。
/// 本应用按自签安装设计，两个进程默认各自独立（词库/日志不共享）；
/// 若签名带 App Group（如模拟器开发构建），则落共享容器。
/// SharedSupport 是预构建 RIME 数据，键盘扩展的 Bundle.main 是 .appex，
/// 需向上回溯宿主 App bundle。
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

    /// 用户数据目录：有 App Group（模拟器开发构建）时落共享容器；
    /// 自签基线下各进程用私有 Application Support 目录。
    public static var userDataDirectory: URL? {
        if let group = appGroupContainer {
            return group.appendingPathComponent("Rime", isDirectory: true)
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return support.appendingPathComponent("Quill/Rime", isDirectory: true)
        }
        return nil
    }

    /// 日志目录：自签基线下放 Documents/Logs（键盘扩展可经文件 App 查看）；
    /// 有 App Group 时两进程写同一份。
    public static var logDirectory: URL? {
        let base: URL?
        if let group = appGroupContainer {
            base = group
        } else {
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
