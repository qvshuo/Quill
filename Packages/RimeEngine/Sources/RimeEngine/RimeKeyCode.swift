import Foundation

/// X11 keysyms librime expects for special keys. ASCII printable characters map
/// to their own code point (which is also their X11 keysym).
public let XK_BackSpace: Int32 = 0xff08
public let XK_Return: Int32 = 0xff0d
public let XK_space: Int32 = 0x0020

/// Translates a Unicode scalar into the keycode librime expects.
public func rimeKeyCode(forCharacter character: String) -> Int32? {
    guard let scalar = character.unicodeScalars.first else { return nil }
    let value = scalar.value
    // printable ASCII → keysym == code point
    if value < 0x80 {
        return Int32(value)
    }
    return Int32(bitPattern: value)
}
