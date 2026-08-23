import Testing
import Models

/// 同步 toast（`SyncToast`）的文案纯映射测试。收起时长由键盘控制器掌握，
/// 不属于模型语义（见 `InputController.scheduleToastDismissal`）。
struct SyncToastTests {
    @Test("同步 toast 文案映射")
    func mapsMessages() {
        #expect(SyncToast.started.message == "正在同步…")
        #expect(SyncToast.completed.message == "同步完成")
        #expect(SyncToast.failed.message == "同步失败，请检查设置")
    }
}