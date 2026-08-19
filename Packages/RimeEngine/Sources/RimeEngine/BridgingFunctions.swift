import Foundation
import RimeEngineC

/// Types that carry a `data_size` field (RimeTraits/RimeCommit/RimeContext).
/// Initialized with `rimeStructInit(&var)` so librime recognizes optional
/// fields (log_dir, prebuilt_data_dir, ...).
public protocol DataSizeable {
    var data_size: Int32 { get set }
}

/// Zero out the struct and set `data_size = sizeof(Self) - sizeof(data_size)`.
/// librime uses `data_size` to decide which optional fields are populated.
public func rimeStructInit<T: DataSizeable>(_ value: inout T) {
    _ = withUnsafeMutableBytes(of: &value) { $0.initializeMemory(as: UInt8.self, repeating: 0) }
    value.data_size = Int32(MemoryLayout<T>.size - MemoryLayout<Int32>.size)
}

/// `strdup`s a Swift string into a C-string pointer that librime keeps for the
/// lifetime of the process. Returns nil for nil input.
@discardableResult
public func setCString(_ value: String?, to target: inout UnsafePointer<CChar>?) -> UnsafePointer<CChar>? {
    guard let value else { return nil }
    let duplicated = strdup(value)
    target = UnsafePointer(duplicated)
    return target
}

/// `strdup`s a Swift string into a mutable C-string pointer (RimeTraits fields).
@discardableResult
public func setCString(_ value: String?, to target: inout UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let value else { return nil }
    let duplicated = strdup(value)
    target = duplicated
    return target
}

/// Nil-safe C-string → Swift String.
public func stringOrNil(_ pointer: UnsafePointer<CChar>?) -> String? {
    guard let pointer else { return nil }
    return String(cString: pointer)
}

// MARK: - DataSizeable conformances

extension RimeTraits: DataSizeable {}
extension RimeCommit: DataSizeable {}
extension RimeContext_stdbool: DataSizeable {}
