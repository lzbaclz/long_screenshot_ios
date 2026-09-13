import XCTest
@testable import ScrollCapture

@MainActor
final class PurchaseQuotaTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "PurchaseQuotaTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    func testOnlySuccessfulFinalExportsConsumeQuotaAndRepeatDoesNot() {
        let store = PurchaseStore(defaults: defaults)
        let session = UUID()
        XCTAssertEqual(store.remainingExports, 3)
        // Previewing, requesting permission, or cancelling sharing calls no record method.
        XCTAssertTrue(store.canExport(sessionID: session))
        XCTAssertEqual(store.remainingExports, 3)
        store.recordSuccessfulExport(sessionID: session)
        XCTAssertEqual(store.remainingExports, 2)
        store.recordSuccessfulExport(sessionID: session)
        XCTAssertEqual(store.remainingExports, 2)
        let relaunched = PurchaseStore(defaults: defaults)
        XCTAssertEqual(relaunched.remainingExports, 2)
    }

    func testExportsFromPreviousWeekDoNotConsumeCurrentWeekQuota() {
        let previous = Calendar(identifier: .iso8601).date(byAdding: .weekOfYear, value: -1, to: Date())!
        defaults.set([UUID().uuidString: previous], forKey: "successfulCaptureExports.v1")
        let store = PurchaseStore(defaults: defaults)
        XCTAssertEqual(store.remainingExports, 3)
        for _ in 0..<5 { store.recordSuccessfulExport(sessionID: UUID()) }
        XCTAssertEqual(store.remainingExports, 0)
    }
}

final class CaptureNoticeTests: XCTestCase {
    func testOriginWarningSurvivesInterruptedRecoveryReason() {
        var session = CaptureSessionManifest()
        session.status = .interrupted
        session.stopReason = "捕捉意外中断，已保留画面。"
        session.startWarning = "画面变化后重新确定了起点，请检查图片开头是否完整。"
        XCTAssertTrue(session.noticeText?.contains("捕捉意外中断") == true)
        XCTAssertTrue(session.noticeText?.contains("请检查图片开头是否完整") == true)
    }

    func testCompletedOriginWarningIsVisibleAndNotRepeated() {
        var session = CaptureSessionManifest()
        session.status = .completed
        session.startWarning = "请检查图片开头是否完整。"
        XCTAssertEqual(session.stateLabel, "请检查开头")
        XCTAssertEqual(session.noticeText, session.startWarning)
        session.stopReason = "已停止。请检查图片开头是否完整。"
        XCTAssertEqual(session.noticeText, session.stopReason)
    }
}
