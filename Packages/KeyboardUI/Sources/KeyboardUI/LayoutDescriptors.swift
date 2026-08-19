import Foundation
import Models

/// 键盘键位描述。身份由视图层的稳定行/列下标提供（布局文件固定），不再自持随机 UUID。
public struct KeyDescriptor: Sendable {
    public let label: String
    public let action: KeyAction
    public let style: KeyStyle
    /// 弹性宽度权重：非固定键按此权重分摊剩余宽度（默认 1.0）。
    public let width: CGFloat
    /// 固定点宽（JSON `fixed` 字段）：nil 表示参与弹性分摊。方形键 / 宽键用它指定。
    public let fixedWidth: CGFloat?

    public init(
        label: String,
        action: KeyAction,
        style: KeyStyle,
        width: CGFloat,
        fixedWidth: CGFloat? = nil
    ) {
        self.label = label
        self.action = action
        self.style = style
        self.width = width
        self.fixedWidth = fixedWidth
    }

    /// 复制自身并替换 label / style（重建键描述时保留其余字段）。
    public func with(label: String? = nil, style: KeyStyle? = nil) -> KeyDescriptor {
        KeyDescriptor(
            label: label ?? self.label,
            action: action,
            style: style ?? self.style,
            width: width,
            fixedWidth: fixedWidth
        )
    }
}

public enum KeyStyle: String, Sendable {
    case normal
    case special
    case confirm
}

/// 键盘一行键位描述。
public struct RowDescriptor: Sendable {
    public let keys: [KeyDescriptor]
    public let leadingPadding: CGFloat

    public init(keys: [KeyDescriptor], leadingPadding: CGFloat = 0) {
        self.keys = keys
        self.leadingPadding = leadingPadding
    }
}

public struct LayoutDescriptor: Sendable {
    public let rows: [RowDescriptor]

    public init(rows: [RowDescriptor]) {
        self.rows = rows
    }
}
