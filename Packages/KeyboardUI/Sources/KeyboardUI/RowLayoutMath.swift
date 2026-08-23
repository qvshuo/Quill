import Foundation
import Models
import Synchronization
import UIKit

/// 回车键文案宽度测量的进程级缓存：拼音组合期间每次敲键的行排版不再重复测量。
enum ReturnLabelWidth {
    private static let cache = Mutex<[String: CGFloat]>([:])

    static func measure(_ label: String, fontSize: CGFloat) -> CGFloat {
        let key = "\(fontSize)|\(label)"
        if let width = cache.withLock({ $0[key] }) {
            return width
        }
        let width = (label as NSString)
            .size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize)]).width + 12
        cache.withLock { $0[key] = width }
        return width
    }
}

/// 单行排版结果：`widths`/`gaps` 与键位一一对应（最终点宽 / 相邻键实际空隙），
/// `sideInset` 为左右留白。行视图用 `HStack(spacing: 0)` + 按 `gaps` 插 Spacer 渲染。
struct RowLayout {
    let keys: [KeyDescriptor]
    let widths: [CGFloat]
    let gaps: [CGFloat]
    let sideInset: CGFloat

    init(keys: [KeyDescriptor], widths: [CGFloat], gaps: [CGFloat], sideInset: CGFloat) {
        self.keys = keys
        self.widths = widths
        self.gaps = gaps
        self.sideInset = sideInset
    }
}

/// 行排版输入参数：随主题变化的几何常量，与具体行无关。
struct RowLayoutParameters {
    let keys: [KeyDescriptor]
    let totalWidth: CGFloat
    let sideInset: CGFloat
    let keyboardLeading: CGFloat
    let keyboardTrailing: CGFloat
    let keySpacing: CGFloat
    let keyHeight: CGFloat
    let minSpaceWidth: CGFloat
    let returnLabelWidth: CGFloat
}

/// 键盘行宽分配的纯逻辑（无视图依赖，可单测）。按行内动作组合分派：
/// - 含空格键 → 底行：左/右/中英键固定宽（`fixed`），空格吸走余量，回车键按文案增长
///   （文案过长时从空格让出，空格保底 `minSpaceWidth`）。
/// - 含 ⇧ 键 → 字母页第三行：⇧/⌫ 方形、中间字母为字母格 L，与首尾字母之间的空隙
///   g = 1.5L − 36，使 z 对齐 s、m 对齐 k，且左右贴边。
/// - 含数字/符号切换 + 退格 → 数字/符号页第三行：切换/退格方形，中间键弹性分摊。
/// - 纯字符行：10 键满宽、9 键居中（首尾留白 (L+keySpacing)/2）。
/// - 其余 → 按 `width` 权重分摊（兜底，含 `leadingPadding`）。
enum RowLayoutMath {
    static func layout(_ parameters: RowLayoutParameters) -> RowLayout {
        let keys = parameters.keys
        let totalWidth = parameters.totalWidth
        let sideInset = parameters.sideInset
        let keyboardLeading = parameters.keyboardLeading
        let keyboardTrailing = parameters.keyboardTrailing
        let keySpacing = parameters.keySpacing
        let keyHeight = parameters.keyHeight
        let minSpaceWidth = parameters.minSpaceWidth
        let returnLabelWidth = parameters.returnLabelWidth
        let gridWidth = totalWidth - keyboardLeading - keyboardTrailing
        // 字母格宽：以 10 键行推导，全键盘共用（对齐计算的基础单位）。
        // 退化窄宽度下可为负，clamp 到 0 避免产生负帧宽（weightedRow 同款防护）。
        let letter = max(0, (gridWidth - 9 * keySpacing) / 10)

        if keys.contains(where: { $0.action.isSpace }) {
            return bottomRow(
                keys: keys,
                gridWidth: gridWidth,
                sideInset: sideInset,
                keySpacing: keySpacing,
                keyHeight: keyHeight,
                minSpaceWidth: minSpaceWidth,
                returnLabelWidth: returnLabelWidth
            )
        }
        if keys.contains(where: { $0.action.isShift }) {
            return shiftRow(
                keys: keys,
                gridWidth: gridWidth,
                letter: letter,
                square: keyHeight,
                keySpacing: keySpacing
            )
        }
        if keys.contains(where: { $0.action.isToggle }),
           keys.contains(where: { $0.action.isBackspace }) {
            return toggleRow(keys: keys, gridWidth: gridWidth, square: keyHeight, keySpacing: keySpacing)
        }
        if keys.allSatisfy({ $0.action.isCharacter }) {
            return letterRow(keys: keys, letter: letter, keySpacing: keySpacing, sideInset: sideInset)
        }
        return weightedRow(keys: keys, gridWidth: gridWidth, sideInset: sideInset, keySpacing: keySpacing)
    }

    /// 底行：[123/ABC 宽键][空格 弹性][中/英 方形][⏎ ≥1.5×方形]。非空格/回车键必须都是固定宽，
    /// 否则退回权重分摊。回车默认宽 1.5×方形，文案更宽时从空格借宽（空格保底 minSpaceWidth）。
    private static func bottomRow(
        keys: [KeyDescriptor],
        gridWidth: CGFloat,
        sideInset: CGFloat,
        keySpacing: CGFloat,
        keyHeight: CGFloat,
        minSpaceWidth: CGFloat,
        returnLabelWidth: CGFloat
    ) -> RowLayout {
        guard let spaceIndex = keys.firstIndex(where: { $0.action.isSpace }),
              let returnIndex = keys.firstIndex(where: { $0.action.isReturn }),
              spaceIndex != returnIndex else { return weightedRow(keys: keys, gridWidth: gridWidth, sideInset: sideInset, keySpacing: keySpacing) }

        var otherFixed: CGFloat = 0
        for i in keys.indices where i != spaceIndex && i != returnIndex {
            guard let fixed = keys[i].fixedWidth else {
                return weightedRow(keys: keys, gridWidth: gridWidth, sideInset: sideInset, keySpacing: keySpacing)
            }
            otherFixed += fixed
        }

        let returnMin = keys[returnIndex].fixedWidth ?? keyHeight * 1.5
        var returnWidth = max(returnMin, returnLabelWidth)
        // 文案过长时以「空格保底」为上限让出，总量守恒。
        let maxReturn = max(0, gridWidth - CGFloat(keys.count - 1) * keySpacing - otherFixed - minSpaceWidth)
        returnWidth = min(returnWidth, maxReturn)
        let spaceWidth = max(0, gridWidth - CGFloat(keys.count - 1) * keySpacing - otherFixed - returnWidth)

        var widths = [CGFloat](repeating: 0, count: keys.count)
        for i in keys.indices {
            if i == spaceIndex {
                widths[i] = spaceWidth
            } else if i == returnIndex {
                widths[i] = returnWidth
            } else if let fixed = keys[i].fixedWidth {
                widths[i] = fixed
            }
        }
        return RowLayout(
            keys: keys,
            widths: widths,
            gaps: Array(repeating: keySpacing, count: max(0, keys.count - 1)),
            sideInset: sideInset
        )
    }

    /// 字母页第三行：[⇧ 方形][空隙 g][字母 ×L][空隙 g][⌫ 方形]，左右贴边。
    /// 行宽守恒给出 g = 1.5L − 36，恰好使 z 对齐 s、m 对齐 k（行内留白被对称空隙吃掉，
    /// 行宽恰好填满 gridWidth）。
    private static func shiftRow(
        keys: [KeyDescriptor],
        gridWidth: CGFloat,
        letter: CGFloat,
        square: CGFloat,
        keySpacing: CGFloat
    ) -> RowLayout {
        guard let shiftIndex = keys.firstIndex(where: { $0.action.isShift }),
              let backspaceIndex = keys.firstIndex(where: { $0.action.isBackspace }),
              shiftIndex != backspaceIndex,
              // 对齐空隙的计算假定 ⇧ 在行首、⌫ 在行尾；布局异常时退回权重分摊，
              // 避免 gaps[backspaceIndex - 1] 静默改错键位间隙。
              shiftIndex == 0,
              backspaceIndex == keys.count - 1 else {
            return weightedRow(keys: keys, gridWidth: gridWidth, sideInset: 0, keySpacing: keySpacing)
        }
        let middleCount = keys.count - 2
        // gridWidth = 2*square + middleCount*letter + (middleCount−1)*keySpacing + 2*g
        let letterGaps = CGFloat(max(0, middleCount - 1)) * keySpacing
        let gap = max(0, (gridWidth - 2 * square - CGFloat(middleCount) * letter - letterGaps) / 2)
        var widths = [CGFloat](repeating: letter, count: keys.count)
        widths[shiftIndex] = keys[shiftIndex].fixedWidth ?? square
        widths[backspaceIndex] = keys[backspaceIndex].fixedWidth ?? square
        var gaps = [CGFloat](repeating: keySpacing, count: max(0, keys.count - 1))
        // 空隙 g 取代 ⇧ 之后、⌫ 之前的默认 keySpacing。
        gaps[shiftIndex] = gap
        if backspaceIndex - 1 >= 0 { gaps[backspaceIndex - 1] = gap }
        return RowLayout(keys: keys, widths: widths, gaps: gaps, sideInset: 0)
    }

    /// 数字/符号页第三行：[#+=/123 方形][中间键 ×弹性][⌫ 方形]。切换/退格必须固定宽，
    /// 否则退回权重分摊。
    private static func toggleRow(
        keys: [KeyDescriptor],
        gridWidth: CGFloat,
        square: CGFloat,
        keySpacing: CGFloat
    ) -> RowLayout {
        let specials = keys.indices.filter { keys[$0].action.isToggle || keys[$0].action.isBackspace }
        guard specials.count == 2 else {
            return weightedRow(keys: keys, gridWidth: gridWidth, sideInset: 0, keySpacing: keySpacing)
        }
        var widths = [CGFloat](repeating: 0, count: keys.count)
        var fixedSum: CGFloat = 0
        for i in specials {
            let fixed = keys[i].fixedWidth ?? square
            widths[i] = fixed
            fixedSum += fixed
        }
        let middleCount = keys.count - specials.count
        let middleWidth = middleCount > 0
            ? max(0, (gridWidth - fixedSum - CGFloat(keys.count - 1) * keySpacing) / CGFloat(middleCount))
            : 0
        for i in keys.indices where !specials.contains(i) {
            widths[i] = middleWidth
        }
        return RowLayout(
            keys: keys,
            widths: widths,
            gaps: Array(repeating: keySpacing, count: max(0, keys.count - 1)),
            sideInset: 0
        )
    }

    /// 纯字符行：10 键满宽；9 键居中（首尾各留白 (L+keySpacing)/2），键宽恒为字母格 L。
    private static func letterRow(
        keys: [KeyDescriptor],
        letter: CGFloat,
        keySpacing: CGFloat,
        sideInset: CGFloat
    ) -> RowLayout {
        let padding: CGFloat
        if keys.count == 10 {
            padding = 0
        } else if keys.count == 9 {
            padding = (letter + keySpacing) / 2
        } else {
            padding = sideInset
        }
        return RowLayout(
            keys: keys,
            widths: Array(repeating: letter, count: keys.count),
            gaps: Array(repeating: keySpacing, count: max(0, keys.count - 1)),
            sideInset: padding
        )
    }

    /// 兜底：按 `width` 权重把可用宽度分摊到各键。
    private static func weightedRow(
        keys: [KeyDescriptor],
        gridWidth: CGFloat,
        sideInset: CGFloat,
        keySpacing: CGFloat
    ) -> RowLayout {
        let keyUnit = max(0, gridWidth - sideInset * 2 - CGFloat(keys.count - 1) * keySpacing)
        let totalWeight = keys.reduce(0) { $0 + $1.width }
        // 权重全为 0（异常布局）时避免除零产生 NaN 帧宽，退化为等宽分摊。
        guard totalWeight > 0 else {
            let equalWidth = keys.count > 0 ? keyUnit / CGFloat(keys.count) : 0
            return RowLayout(
                keys: keys,
                widths: [CGFloat](repeating: equalWidth, count: keys.count),
                gaps: [CGFloat](repeating: keySpacing, count: max(0, keys.count - 1)),
                sideInset: sideInset
            )
        }
        let widths = keys.map { keyUnit * $0.width / totalWeight }
        return RowLayout(
            keys: keys,
            widths: widths,
            gaps: Array(repeating: keySpacing, count: max(0, keys.count - 1)),
            sideInset: sideInset
        )
    }
}
