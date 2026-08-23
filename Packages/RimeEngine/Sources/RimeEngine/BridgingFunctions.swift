import Foundation
import RimeEngineC

/// 带 `data_size` 字段的 C 结构（RimeTraits / RimeCommit / RimeContext）。
///须经 `rimeStructInit(&var)` 初始化，librime 才会填充可选字段
/// （log_dir、prebuilt_data_dir 等）。
public protocol DataSizeable {
    var data_size: Int32 { get set }
}

/// 结构体清零并置 `data_size = sizeof(Self) - sizeof(data_size)`。
/// librime 依据 `data_size` 判断可选字段是否有效。
public func rimeStructInit<T: DataSizeable>(_ value: inout T) {
    _ = withUnsafeMutableBytes(of: &value) { $0.initializeMemory(as: UInt8.self, repeating: 0) }
    value.data_size = Int32(MemoryLayout<T>.size - MemoryLayout<Int32>.size)
}

/// 把 Swift 字符串 `strdup` 成 librime 进程生命周期内持有的 C 字符串指针；
/// 入参为 nil 时返回 nil。注意：strdup 的内存刻意不释放（setup/initialize 会
/// 持有 traits 里的指针直到进程结束）。
@discardableResult
public func setCString(_ value: String?, to target: inout UnsafePointer<CChar>?) -> UnsafePointer<CChar>? {
    guard let value else { return nil }
    let duplicated = strdup(value)
    target = UnsafePointer(duplicated)
    return target
}

/// 把 Swift 字符串 `strdup` 成可变 C 字符串指针（RimeTraits 各字段）。
@discardableResult
public func setCString(_ value: String?, to target: inout UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let value else { return nil }
    let duplicated = strdup(value)
    target = duplicated
    return target
}

/// nil 安全的 C 字符串 → Swift String。
public func stringOrNil(_ pointer: UnsafePointer<CChar>?) -> String? {
    guard let pointer else { return nil }
    return String(cString: pointer)
}

// MARK: - DataSizeable conformances

extension RimeTraits: DataSizeable {}
extension RimeCommit: DataSizeable {}
extension RimeContext_stdbool: DataSizeable {}
