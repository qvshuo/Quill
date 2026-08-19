import Testing
import UIKit
import RimeEngine
import Models
@testable import KeyboardUI

/// 键盘布局切换 / 大写状态 / 语言 / 空格路由行为测试（`KeyboardViewModel.consume`）。
@MainActor
struct LayoutActionTests {
    @Test("切到数字页消耗一次性大写状态")
    func switchingToNumbersConsumesUppercaseOnce() {
        let model = KeyboardViewModel()
        model.shiftState = .uppercaseOnce
        #expect(model.consume(.numbers) == nil)
        #expect(model.currentLayout == .numbers)
        #expect(model.shiftState == .lowercase)
    }

    @Test("切到符号页消耗一次性大写状态")
    func switchingToSymbolsConsumesUppercaseOnce() {
        let model = KeyboardViewModel()
        model.shiftState = .uppercaseOnce
        #expect(model.consume(.symbols) == nil)
        #expect(model.currentLayout == .symbols)
        #expect(model.shiftState == .lowercase)
    }

    @Test("切回字母页不消耗大写状态")
    func switchingToLettersKeepsShiftState() {
        let model = KeyboardViewModel()
        model.currentLayout = .numbers
        model.shiftState = .uppercaseOnce
        #expect(model.consume(.letters) == nil)
        #expect(model.currentLayout == .qwerty)
        #expect(model.shiftState == .uppercaseOnce)
    }

    @Test("输入字母键消耗一次性大写状态")
    func typingCharacterConsumesUppercaseOnce() {
        let model = KeyboardViewModel()
        model.shiftState = .uppercaseOnce
        let result = model.consume(.character("a"))
        #expect(result == .character("A"))
        #expect(model.shiftState == .lowercase)
    }

    @Test("大写锁定时输入字母保持锁定")
    func lockedCapsKeepsLockOnCharacter() {
        let model = KeyboardViewModel()
        model.shiftState = .uppercaseLocked
        let result = model.consume(.character("a"))
        #expect(result == .character("A"))
        #expect(model.shiftState == .uppercaseLocked)
    }

    @Test("符号页输入也消耗一次性大写状态")
    func symbolInputConsumesUppercaseOnce() {
        let model = KeyboardViewModel()
        model.shiftState = .uppercaseOnce
        model.currentLayout = .symbols
        let result = model.consume(.character("←"))
        #expect(result == .directInput("←"))
        #expect(model.shiftState == .lowercase)
        #expect(model.currentLayout == .symbols)
    }

    @Test("符号页输入句末符号后回到字母页")
    func symbolsAutoReturnToLetters() {
        let model = KeyboardViewModel()
        model.currentLayout = .symbols
        let result = model.consume(.character("。"))
        #expect(result == .directInput("。"))
        #expect(model.currentLayout == .qwerty)
    }

    @Test("符号页输入非句末符号留在当前页")
    func symbolsNonTerminalStaysOnSymbolsPage() {
        let model = KeyboardViewModel()
        model.currentLayout = .symbols
        let result = model.consume(.character("←"))
        #expect(result == .directInput("←"))
        #expect(model.currentLayout == .symbols)
    }

    @Test("空格按语言路由：中文交 RIME，英文直接上屏字面空格")
    func spaceRoutesByLanguage() {
        let model = KeyboardViewModel()
        model.inputLanguage = .chinese
        #expect(model.consume(.space) == .space)

        model.inputLanguage = .english
        #expect(model.consume(.space) == .directInput(" "))
    }

    @Test("中文数字/符号页空格也交 RIME（双击转「。」）；英文页仍上屏字面空格")
    func spaceOnNonQwertyPagesRoutesByLanguage() {
        let model = KeyboardViewModel()
        model.inputLanguage = .chinese
        model.currentLayout = .numbers
        #expect(model.consume(.space) == .space)
        model.currentLayout = .symbols
        #expect(model.consume(.space) == .space)

        model.inputLanguage = .english
        model.currentLayout = .numbers
        #expect(model.consume(.space) == .directInput(" "))
        model.currentLayout = .symbols
        #expect(model.consume(.space) == .directInput(" "))
    }

    @Test("空格不消耗一次性大写状态")
    func spaceDoesNotConsumeUppercaseOnce() {
        let model = KeyboardViewModel()
        model.shiftState = .uppercaseOnce
        _ = model.consume(.space)
        #expect(model.shiftState == .uppercaseOnce)
    }

    @Test("退格不消耗一次性大写状态")
    func backspaceDoesNotConsumeUppercaseOnce() {
        let model = KeyboardViewModel()
        model.shiftState = .uppercaseOnce
        _ = model.consume(.backspace)
        #expect(model.shiftState == .uppercaseOnce)
    }

    @Test("切换语言：英文进入首字母大写，中文回到小写")
    func toggleLanguageSetsShiftState() {
        let model = KeyboardViewModel()
        model.inputLanguage = .chinese
        model.shiftState = .lowercase
        #expect(model.consume(.toggleLanguage) == .toggleLanguage)
        #expect(model.inputLanguage == .english)
        #expect(model.shiftState == .uppercaseOnce)

        #expect(model.consume(.toggleLanguage) == .toggleLanguage)
        #expect(model.inputLanguage == .chinese)
        #expect(model.shiftState == .lowercase)
    }
}

/// 宿主键盘上下文行为测试：键盘类型变化 / 回车键文案 / 回车动态标签。
@MainActor
struct KeyboardContextTests {
    @Test("asciiCapable 键类型切到英文并进入一次大写")
    func asciiCapableEntersEnglishUppercaseOnce() {
        let model = KeyboardViewModel()
        model.handleKeyboardTypeChange(.asciiCapable)
        #expect(model.inputLanguage == .english)
        #expect(model.shiftState == .uppercaseOnce)
    }

    @Test("default 键类型切回中文小写")
    func defaultEntersChineseLowercase() {
        let model = KeyboardViewModel()
        model.handleKeyboardTypeChange(.asciiCapable)
        model.handleKeyboardTypeChange(.default)
        #expect(model.inputLanguage == .chinese)
        #expect(model.shiftState == .lowercase)
    }

    @Test("相同键类型直接忽略，不重复处理")
    func sameTypeIsIgnored() {
        let model = KeyboardViewModel()
        model.handleKeyboardTypeChange(.asciiCapable)
        model.inputLanguage = .chinese
        model.shiftState = .lowercase
        model.currentLayout = .symbols
        model.handleKeyboardTypeChange(.asciiCapable)
        // 状态保持调用前的值，未被重复写入。
        #expect(model.inputLanguage == .chinese)
        #expect(model.shiftState == .lowercase)
        #expect(model.currentLayout == .symbols)
    }

    @Test("字段切换（键类型变化）回到字母页")
    func switchingFieldReturnsToQwerty() {
        let model = KeyboardViewModel()
        model.handleKeyboardTypeChange(.asciiCapable)
        model.currentLayout = .numbers
        model.handleKeyboardTypeChange(.default)
        #expect(model.currentLayout == .qwerty)
        #expect(model.inputLanguage == .chinese)
        #expect(model.shiftState == .lowercase)
    }

    @Test("回车键动态文案映射")
    func returnKeyLabelMapping() {
        let model = KeyboardViewModel()
        model.handleReturnKeyType(.go)
        #expect(model.returnKeyLabel == "前往")
        model.handleReturnKeyType(.search)
        #expect(model.returnKeyLabel == "搜索")
        model.handleReturnKeyType(.send)
        #expect(model.returnKeyLabel == "发送")
        model.handleReturnKeyType(.next)
        #expect(model.returnKeyLabel == "下一步")
        model.handleReturnKeyType(.done)
        #expect(model.returnKeyLabel == "完成")
        model.handleReturnKeyType(.emergencyCall)
        #expect(model.returnKeyLabel == "紧急呼叫")
        model.handleReturnKeyType(.continue)
        #expect(model.returnKeyLabel == "继续")
        model.handleReturnKeyType(.default)
        #expect(model.returnKeyLabel == "换行")
    }

    @Test("回车键动态标签：有 preedit 显示 ⏎，否则宿主文案")
    func effectiveReturnLabel() {
        #expect(KeyboardViewModel.effectiveReturnLabel(hasPreedit: true, hostLabel: "发送") == "⏎")
        #expect(KeyboardViewModel.effectiveReturnLabel(hasPreedit: false, hostLabel: "发送") == "发送")
    }
}