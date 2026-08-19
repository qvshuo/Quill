import Foundation

/// 候选词模型，用于 UI 与引擎之间传递。
/// 身份由视图层的位置（候选索引）提供，不再自持随机 UUID——否则每次敲键都会
/// 生成全新 id，导致 `LazyHStack`/`ForEach` 的身份每次都不稳定、整组重建。
public struct Candidate: Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}
