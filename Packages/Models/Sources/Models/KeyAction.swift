import Foundation

/// 按键动作，键盘 UI 产生后交给控制器处理。
public enum KeyAction: Sendable, Equatable {
    case character(String)
    case directInput(String)
    case backspace
    case space
    case startSync
    case `return`
    case shift
    case numbers
    case letters
    case symbols
    case toggleLanguage
    case selectCandidate(Int)
}

public extension KeyAction {
    public var isReturn: Bool {
        if case .return = self { return true }
        return false
    }

    public var isSpace: Bool {
        if case .space = self { return true }
        return false
    }

    public var isShift: Bool {
        if case .shift = self { return true }
        return false
    }

    public var isBackspace: Bool {
        if case .backspace = self { return true }
        return false
    }

    public var isToggle: Bool {
        switch self {
        case .numbers, .symbols: return true
        default: return false
        }
    }

    public var isCharacter: Bool {
        if case .character = self { return true }
        return false
    }
}
