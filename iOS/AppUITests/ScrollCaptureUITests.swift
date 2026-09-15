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
        XCTAssertTrue(app.staticTexts["切到目标应用，上下自然滑动"].waitForExistence(timeout: 5))
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

    func testSettingsShowsFiniteBetaAllowanceAndPrivacy() {
        app.buttons["home.settings"].tap()
        XCTAssertTrue(app.buttons["settings.idleStop"].waitForExistence(timeout: 5))
        app.swipeUp()
        let remaining = element("settings.remainingExports")
        XCTAssertTrue(remaining.waitForExistence(timeout: 5))
        XCTAssertTrue(remaining.label.contains("/ 50"), "Beta settings must show a finite 50-work allowance")
        XCTAssertFalse(app.buttons["settings.upgrade"].exists)
        XCTAssertTrue(app.buttons["purchase.restore"].exists)
        attachScreenshot("settings-beta-fifty")
        app.buttons["settings.privacy"].tap()
        XCTAssertTrue(app.staticTexts["只在你的设备上处理"].waitForExistence(timeout: 5))
    }

    func testEmptyLegacyCaptureShowsFailureWithoutExportOrEditing() {
        app.terminate()
        app.launchArguments.append("--demo-empty-capture")
        app.launch()
        let row = app.buttons["capture.row.D3E00000-0000-4000-8000-000000000004"]
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("未捕捉到可用画面"))
        XCTAssertFalse(row.label.contains("0 × 0"))
        XCTAssertFalse(row.label.contains("部分内容已保留"))
        row.tap()
        XCTAssertTrue(element("detail.noImage").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["画面无法可靠衔接，未保存可用画面。请让前后画面保留重叠，或调整捕捉区域后重试。"].exists)
        XCTAssertFalse(app.buttons["detail.savePhotos"].exists)
        XCTAssertFalse(app.buttons["detail.share"].exists)
        XCTAssertFalse(app.buttons["detail.edit"].exists)
        XCTAssertTrue(app.buttons["detail.delete"].exists)
        attachScreenshot("empty-capture-failure")
        app.buttons["返回首页"].tap()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
        // The failure remains available; displaying it must never delete its record.
        XCTAssertTrue(row.exists)
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
        // The remote system share view can appear before its actions load, and
        // its locale can follow the runner rather than this app's launch locale.
        let copyAction = app.cells.matching(NSPredicate(format: "label == %@ OR label == %@", "拷贝", "Copy")).firstMatch
        let shareActionsLoaded = copyAction.waitForExistence(timeout: 15)
        if !shareActionsLoaded {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "system-share-missing-actions"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(shareActionsLoaded, "The actual system Copy action must become available before dismissing sharing.")
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

    func testBoundedSeamDetailsScrollAndCloseWithoutHidingExportsInBothLanguages() {
        for language in ["zh-Hans", "en"] {
            app.terminate()
            app.launchArguments = ["--demo", "--uitesting", "--demo-seam-diagnostics",
                "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
            app.launch()
            openFirstCompletedCapture()
            XCTAssertTrue(element("detail.preview").waitForExistence(timeout: 10))
            let diagnostics = element("detail.diagnostics")
            XCTAssertTrue(diagnostics.waitForExistence(timeout: 5)); diagnostics.tap()
            let summary = language == "en" ? "Checked 40 seams · adjusted 10" : "已检查 40 处 · 已调整 10 处"
            XCTAssertTrue(app.staticTexts[summary].waitForExistence(timeout: 5))
            let open = app.buttons["detail.seams"]
            let found = open.waitForExistence(timeout: 5)
            if !found || !open.isHittable {
                attachScreenshot("seam-details-button-unreachable-\(language)")
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "seam-details-button-hierarchy-\(language)"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            }
            XCTAssertTrue(found)
            XCTAssertTrue(open.isHittable); open.tap()
            let list = element("detail.seams.list")
            XCTAssertTrue(list.waitForExistence(timeout: 5))
            let omitted = language == "en" ? "Showing the latest 32 seams; 8 earlier entries omitted." : "仅保留最近 32 处明细，较早 8 处已省略。"
            XCTAssertTrue(app.staticTexts[omitted].exists)
            let scoreExplanation = language == "en"
                ? "The seam score combines pixel differences and structure; lower is better."
                : "接缝评分综合像素差异和结构，越低越好。"
            XCTAssertTrue(app.staticTexts[scoreExplanation].exists)
            XCTAssertTrue(element("detail.seams.row.9").exists)
            let last = element("detail.seams.row.40")
            for _ in 0..<14 where !last.isHittable { list.swipeUp() }
            XCTAssertTrue(last.isHittable, "The final retained entry must be reachable without moving the preview")
            XCTAssertTrue(last.label.contains(language == "en"
                ? "Insufficient source evidence; kept the default seam" : "来源证据不足，保留默认接缝"))
            for rawReason in ["unavailable", "insufficientGain", "defaultAlreadyQuiet", "selectedRow"] {
                XCTAssertFalse(last.label.contains(rawReason), "Internal diagnostic codes must be translated")
            }
            if language == "en" { XCTAssertNil(last.label.range(of: #"\p{Han}"#, options: .regularExpression)) }
            attachScreenshot("seam-details-bottom-\(language)")
            let close = app.buttons["detail.seams.close"]
            XCTAssertTrue(close.isHittable); close.tap()
            XCTAssertFalse(list.exists)
            let preview = element("detail.preview")
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(preview.frame.height, 40)
            XCTAssertTrue(app.buttons["detail.savePhotos"].isEnabled)
            XCTAssertTrue(app.buttons["detail.savePhotos"].isHittable)
            XCTAssertTrue(app.buttons["detail.share"].isEnabled)
            XCTAssertTrue(app.buttons["detail.share"].isHittable)
            attachScreenshot("seam-details-closed-\(language)")
            app.buttons["detail.share"].tap()
            XCTAssertTrue(element("ActivityListView").waitForExistence(timeout: 10))
            let shareClose = app.buttons["header.closeButton"]
            XCTAssertTrue(shareClose.waitForExistence(timeout: 5)); shareClose.tap()
            XCTAssertTrue(app.buttons["detail.savePhotos"].waitForExistence(timeout: 5))
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openFirstCompletedCapture() {
        let row = app.buttons["capture.row.D3E00000-0000-4000-8000-000000000002"]
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
