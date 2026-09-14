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

    func testBetaStartsWithFiftyFiniteExportsBeforeStoreKitLoads() {
        let store = PurchaseStore(defaults: defaults)
        XCTAssertEqual(store.quotaPolicy, .beta(limit: 50))
        XCTAssertEqual(store.exportLimit, 50)
        XCTAssertEqual(store.remainingExports, 50)
        XCTAssertFalse(store.unlimited, "Debug and beta builds must exercise the actual finite allowance")
        XCTAssertTrue(store.canExport(sessionID: UUID()))
    }

    func testFortyNinthFiftiethAndFiftyFirstNewExports() {
        let store = PurchaseStore(defaults: defaults)
        let sessions = (0..<51).map { _ in UUID() }
        for session in sessions.prefix(49) {
            XCTAssertTrue(store.canExport(sessionID: session))
            store.recordSuccessfulExport(sessionID: session)
        }
        XCTAssertEqual(store.remainingExports, 1)
        XCTAssertTrue(store.canExport(sessionID: sessions[49]))
        store.recordSuccessfulExport(sessionID: sessions[49])
        XCTAssertEqual(store.remainingExports, 0)
        XCTAssertFalse(store.canExport(sessionID: sessions[50]))
        // Editing, saving again, or sharing any already-counted work stays available.
        for session in sessions.prefix(50) {
            XCTAssertTrue(store.canExport(sessionID: session))
            store.recordSuccessfulExport(sessionID: session)
        }
        XCTAssertEqual(store.remainingExports, 0)
        XCTAssertEqual(defaults.dictionary(forKey: "successfulCaptureExports.v1")?.count, 50)
        let relaunched = PurchaseStore(defaults: defaults)
        XCTAssertEqual(relaunched.remainingExports, 0)
        XCTAssertFalse(relaunched.canExport(sessionID: sessions[50]))
        XCTAssertTrue(relaunched.canExport(sessionID: sessions[0]))
    }

    func testFailedOrCancelledShareDoesNotConsumeAndSuccessfulRepeatCountsOnce() {
        let store = PurchaseStore(defaults: defaults)
        let session = UUID()
        // Both cancellation and a failed activity report completed == false.
        store.recordShareCompletion(sessionID: session, completed: false)
        store.recordShareCompletion(sessionID: session, completed: false)
        XCTAssertEqual(store.remainingExports, 50)
        XCTAssertNil(defaults.dictionary(forKey: "successfulCaptureExports.v1"))
        store.recordShareCompletion(sessionID: session, completed: true)
        XCTAssertEqual(store.remainingExports, 49)
        store.recordSuccessfulExport(sessionID: session)
        store.recordShareCompletion(sessionID: session, completed: true)
        XCTAssertEqual(store.remainingExports, 49)
        XCTAssertEqual(PurchaseStore(defaults: defaults).remainingExports, 49)
    }

    func testPreviousThreeExportLedgerSurvivesUpgradeAndOnlyCurrentWeekCounts() {
        let now = Date(timeIntervalSince1970: 1_789_387_200) // 2026-09-14, Monday.
        let oldSession = UUID()
        let currentSessions = (0..<3).map { _ in UUID() }
        var ledger = Dictionary(uniqueKeysWithValues: currentSessions.map { ($0.uuidString, now) })
        ledger[oldSession.uuidString] = now.addingTimeInterval(-604_800)
        defaults.set(ledger, forKey: "successfulCaptureExports.v1")
        let store = PurchaseStore(defaults: defaults, currentDate: { now })
        XCTAssertEqual(store.remainingExports, 47)
        XCTAssertEqual(defaults.dictionary(forKey: "successfulCaptureExports.v1") as? [String: Date], ledger)
        for session in currentSessions + [oldSession] {
            XCTAssertTrue(store.canExport(sessionID: session))
            store.recordSuccessfulExport(sessionID: session)
        }
        XCTAssertEqual(store.remainingExports, 47)
        let newSession = UUID()
        store.recordSuccessfulExport(sessionID: newSession)
        let upgraded = PurchaseStore(defaults: defaults, quotaPolicy: .beta(limit: 50), currentDate: { now })
        XCTAssertEqual(upgraded.remainingExports, 46)
        let persisted = defaults.dictionary(forKey: "successfulCaptureExports.v1") as? [String: Date]
        for (id, date) in ledger { XCTAssertEqual(persisted?[id], date) }
        XCTAssertTrue(upgraded.canExport(sessionID: newSession))
    }

    func testISOWeekBoundaryReplenishesAllowanceWithoutCountingRepeatedWorksAgain() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 23, minute: 59))!
        let store = PurchaseStore(defaults: defaults, calendar: calendar, currentDate: { now })
        let oldSession = UUID()
        store.recordSuccessfulExport(sessionID: oldSession)
        for _ in 0..<49 { store.recordSuccessfulExport(sessionID: UUID()) }
        XCTAssertEqual(store.remainingExports, 0)
        XCTAssertFalse(store.canExport(sessionID: UUID()))
        now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        XCTAssertEqual(store.remainingExports, 50)
        store.recordSuccessfulExport(sessionID: oldSession)
        XCTAssertEqual(store.remainingExports, 50, "Repeating last week's work must not consume this week's allowance")
        store.recordSuccessfulExport(sessionID: UUID())
        XCTAssertEqual(store.remainingExports, 49)
        XCTAssertEqual(PurchaseStore(defaults: defaults, calendar: calendar, currentDate: { now }).remainingExports, 49)
        XCTAssertEqual(defaults.dictionary(forKey: "successfulCaptureExports.v1")?.count, 51)
    }

    func testExistingLedgerAboveFiftyIsPreservedWithoutNegativeAllowance() {
        let ledger = Dictionary(uniqueKeysWithValues: (0..<51).map { _ in (UUID().uuidString, Date()) })
        defaults.set(ledger, forKey: "successfulCaptureExports.v1")
        let store = PurchaseStore(defaults: defaults)
        XCTAssertEqual(store.remainingExports, 0)
        XCTAssertFalse(store.canExport(sessionID: UUID()))
        XCTAssertEqual(defaults.dictionary(forKey: "successfulCaptureExports.v1") as? [String: Date], ledger)
        XCTAssertTrue(store.canExport(sessionID: UUID(uuidString: ledger.keys.first!)!))
    }

    func testWeeklyAllowanceUsesLocalMondayInsteadOfUTCMidnight() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 23, minute: 59))!
        let store = PurchaseStore(defaults: defaults, calendar: calendar, currentDate: { now })
        store.recordSuccessfulExport(sessionID: UUID())
        XCTAssertEqual(store.remainingExports, 49)
        now = now.addingTimeInterval(60)
        XCTAssertEqual(store.remainingExports, 50, "Local Monday starts while it is still Sunday in UTC")
    }

}

final class CaptureNoticeTests: XCTestCase {
    func testOriginWarningSurvivesInterruptedRecoveryReason() {
        var session = manifestWithImage()
        session.status = .interrupted
        session.stopReason = "捕捉意外中断，已保留画面。"
        session.startWarning = "画面变化后重新确定了起点，请检查图片开头是否完整。"
        XCTAssertTrue(session.noticeText?.contains("捕捉意外中断") == true)
        XCTAssertTrue(session.noticeText?.contains("请检查图片开头是否完整") == true)
    }

    func testCompletedOriginWarningIsVisibleAndNotRepeated() {
        var session = manifestWithImage()
        session.status = .completed
        session.startWarning = "请检查图片开头是否完整。"
        XCTAssertEqual(session.stateLabel, "请检查开头")
        XCTAssertEqual(session.noticeText, session.startWarning)
        session.stopReason = "已停止。请检查图片开头是否完整。"
        XCTAssertEqual(session.noticeText, session.stopReason)
    }

    func testEmptyTerminalCaptureIsFailureAndNeverRecoverable() {
        for status in [CaptureSessionStatus.partial, .interrupted, .completed] {
            var session = CaptureSessionManifest()
            session.status = status
            session.stopReason = "捕捉意外中断，已保留最后一次成功写入的画面。"
            XCTAssertTrue(session.isFailedCapture)
            XCTAssertFalse(session.isSavedPartialCapture)
            XCTAssertEqual(session.stateLabel, "未捕捉到可用画面")
            XCTAssertEqual(session.noticeText, "捕捉意外中断，未保存可用画面。请重新开始捕捉。")
            XCTAssertEqual(session.stopReason, "捕捉意外中断，已保留最后一次成功写入的画面。",
                           "Presenting a legacy failure must not rewrite its original record")
        }
    }

    func testEmptyCaptureKeepsActualActionableFailureReason() {
        var session = CaptureSessionManifest()
        session.status = .partial
        session.stopReason = "无法安全识别固定栏或页面留白。请手动设置顶部和底部忽略区域后重试。"
        XCTAssertEqual(session.noticeText, session.stopReason)
        XCTAssertEqual(session.stateLabel, "未捕捉到可用画面")
    }

    func testEmptyActiveCaptureIsStillPreparing() {
        let session = CaptureSessionManifest()
        XCTAssertFalse(session.isFailedCapture)
        XCTAssertFalse(session.isSavedPartialCapture)
        XCTAssertEqual(session.stateLabel, "捕捉中")
    }

    func testSingleFrameFallbackIsSavedButNeverLabelledCompletedLongImage() {
        var session = manifestWithImage()
        session.status = .partial
        session.outputKind = .singleFrame
        XCTAssertTrue(session.hasImage)
        XCTAssertTrue(session.isSavedPartialCapture)
        XCTAssertFalse(session.isFailedCapture)
        XCTAssertEqual(session.stateLabel, "仅保留单屏")
    }

    private func manifestWithImage() -> CaptureSessionManifest {
        var manifest = CaptureSessionManifest()
        manifest.pixelWidth = 100
        manifest.strips = [CaptureStrip(fileName: "fixture.png", pixelWidth: 100, pixelHeight: 200)]
        return manifest
    }
}
