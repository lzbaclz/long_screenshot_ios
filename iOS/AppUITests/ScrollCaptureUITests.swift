import XCTest

@MainActor
final class ScrollCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--demo", "--uitesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
    }

    func testGuideExplainsPreparationAndSimulatorBoundary() {
        XCTAssertTrue(element("capture.simulatorNotice").waitForExistence(timeout: 15))
        attachScreenshot("home")
        app.buttons["home.guide"].tap()
        XCTAssertTrue(app.staticTexts["切到目标应用，慢慢向下滑"].waitForExistence(timeout: 5))
        attachScreenshot("guide")
        app.navigationBars["使用指南"].buttons["完成"].tap()
        XCTAssertTrue(app.buttons["home.settings"].exists)
    }

    func testDemoDetailCropAndPrivacyRedactionPersist() {
        openFirstCompletedCapture()
        XCTAssertTrue(element("detail.preview").waitForExistence(timeout: 10))
        app.buttons["detail.edit"].tap()
        let cropStart = app.sliders["editor.cropStart"]
        XCTAssertTrue(cropStart.waitForExistence(timeout: 5))
        let initialCropValue = cropStart.value as? String
        cropStart.adjust(toNormalizedSliderPosition: 0.1)
        let cropValue = cropStart.value as? String
        XCTAssertNotNil(cropValue)
        XCTAssertNotEqual(cropValue, initialCropValue, "Crop slider must change the selected source range")
        attachScreenshot("editor-crop")
        app.segmentedControls["editor.mode"].buttons["隐私遮挡"].tap()
        app.buttons["editor.selectRedaction"].tap()
        let canvas = element("editor.canvas")
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.025))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.07))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["已遮挡 1 处 · 导出前请检查隐私"].waitForExistence(timeout: 3))
        attachScreenshot("editor-redaction")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(element("detail.preview").waitForExistence(timeout: 5))
        app.buttons["detail.edit"].tap()
        XCTAssertEqual(app.sliders["editor.cropStart"].value as? String, cropValue)
        app.segmentedControls["editor.mode"].buttons["隐私遮挡"].tap()
        XCTAssertTrue(app.staticTexts["已遮挡 1 处 · 导出前请检查隐私"].waitForExistence(timeout: 3))
        app.navigationBars["编辑长图"].buttons["取消"].tap()
    }

    func testSettingsPurchaseUnavailableAndPrivacy() {
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.buttons["settings.idleStop"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.buttons["settings.upgrade"].tap()
        XCTAssertTrue(element("purchase.unavailable").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["purchase.restore"].exists)
        attachScreenshot("purchase-unavailable")
        app.navigationBars["无限导出"].buttons["完成"].tap()
        app.buttons["settings.privacy"].tap()
        XCTAssertTrue(app.staticTexts["只在你的设备上处理"].waitForExistence(timeout: 5))
    }

    func testRecoverableDraftAndConfirmedDeletion() {
        let drafts = element("home.drafts")
        if !drafts.isHittable { app.swipeUp() }
        let recovery = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "待恢复")).firstMatch
        XCTAssertTrue(recovery.waitForExistence(timeout: 5))
        recovery.tap()
        XCTAssertTrue(app.staticTexts["detail.recoveredNotice"].waitForExistence(timeout: 5))
        app.buttons["detail.delete"].tap()
        app.buttons["删除长图与原始画面"].tap()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("home.drafts").exists)
    }

    func testSavePNGAndJPEGThenOpenSystemShare() {
        openFirstCompletedCapture()
        XCTAssertTrue(element("detail.preview").waitForExistence(timeout: 10))
        attachScreenshot("detail")
        app.buttons["detail.savePhotos"].tap()
        XCTAssertTrue(app.alerts.staticTexts["已保存到照片。"].waitForExistence(timeout: 15))
        app.alerts.buttons["知道了"].tap()
        app.segmentedControls["detail.format"].buttons["JPEG · 较小文件"].tap()
        app.buttons["detail.savePhotos"].tap()
        XCTAssertTrue(app.alerts.staticTexts["已保存到照片。"].waitForExistence(timeout: 15))
        app.alerts.buttons["知道了"].tap()
        app.buttons["detail.share"].tap()
        XCTAssertTrue(element("ActivityListView").waitForExistence(timeout: 10))
        XCTAssertTrue(app.cells["拷贝"].exists)
        attachScreenshot("system-share")
        app.buttons["header.closeButton"].tap()
        XCTAssertTrue(app.buttons["detail.savePhotos"].waitForExistence(timeout: 5))
    }

    func testEnglishBrandGuideSettingsAndEditor() {
        app.terminate()
        app.launchArguments = ["--demo", "--uitesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Longlet"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("capture.simulatorNotice").exists)
        attachScreenshot("home-en")
        app.buttons["home.guide"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Done"].waitForExistence(timeout: 5))
        attachScreenshot("guide-en")
        app.navigationBars.buttons["Done"].tap()
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.buttons["settings.idleStop"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(element("settings.support").waitForExistence(timeout: 5))
        attachScreenshot("settings-en")
        app.navigationBars.buttons["Done"].tap()
        openFirstCompletedCapture()
        XCTAssertTrue(element("detail.preview").waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["detail.edit"].label, "Edit")
        attachScreenshot("detail-en")
        app.buttons["detail.edit"].tap()
        XCTAssertTrue(app.sliders["editor.cropStart"].waitForExistence(timeout: 5))
        let toolTitles = app.segmentedControls["editor.mode"].buttons.allElementsBoundByIndex.map(\.label).joined()
        XCTAssertFalse(toolTitles.range(of: #"\p{Han}"#, options: .regularExpression) != nil)
        attachScreenshot("editor-en")
        app.navigationBars.buttons["Cancel"].tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openFirstCompletedCapture() {
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "capture.row.")).firstMatch
        for _ in 0..<3 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
