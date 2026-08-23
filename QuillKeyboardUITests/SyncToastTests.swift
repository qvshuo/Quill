import Testing
import Models

/// 同步 toast（`SyncToast`）的文案纯映射测试。收起时长由键盘控制器掌握，
/// 不属于模型语义（见 `InputController.scheduleToastDismissal`）。
struct SyncToastTests {
    @Test("同步 toast 文案映射")
    func mapsMessages() {
        #expect(SyncToast.started.message == "正在同步…")
        #expect(SyncToast.completed.message == "同步完成")
        #expect(SyncToast.timedOut.message == "同步超时，仍在后台进行")
        #expect(SyncToast.failed.message == "同步失败，请检查设置")
    }

    @Test("超时与失败的文案必须可区分（超时 ≠ 失败：竞速输家仍在后台完成）")
    func timedOutIsDistinctFromFailed() {
        #expect(SyncToast.timedOut.message != SyncToast.failed.message)
    }
}