import XCTest

/// Runs only in the dedicated permissions scheme after simctl resets real TCC.
/// Sample image content is generated, but the Photos permission flow is the OS flow.
@MainActor
final class PhotosPermissionUITests: XCTestCase {
    private var app: XCUIApplication!
    private var didDenySystemRequest = false

    override func setUp() async throws {
        #if !targetEnvironment(simulator)
        XCTFail("This destructive permission-state test is restricted to a dedicated simulator.")
        throw PermissionTestError.physicalDeviceNotAllowed
        #else
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--demo", "--uitesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        #endif
    }

    func testDeniedPhotoAddPreservesPreviewAndSystemSharing() {
        let allowanceBefore = remainingAllowance()
        let interruption = addUIInterruptionMonitor(withDescription: "Deny the actual system add-photos request") { [weak self] alert in
            let message = alert.label + " " + alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
            guard message.contains("照片") || message.localizedCaseInsensitiveContains("photo") else { return false }
            for label in ["不允许", "不允許", "Don’t Allow", "Don't Allow"] {
                let deny = alert.buttons[label]
                if deny.exists {
                    deny.tap()
                    self?.didDenySystemRequest = true
                    return true
                }
            }
            return false
        }
        defer { removeUIInterruptionMonitor(interruption) }

        let row = app.buttons["capture.row.D3E00000-0000-4000-8000-000000000002"]
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(element("detail.preview").waitForExistence(timeout: 10))
        app.buttons["detail.savePhotos"].tap()

        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(system.alerts.firstMatch.waitForExistence(timeout: 10),
                      "A genuine system permission prompt is required; a pre-denied or mocked state must not pass.")
        attachScreenshot("photos-add-system-permission-prompt", app: system)
        // A foreground interaction invokes XCTest's interruption monitor.
        app.tap()
        XCTAssertTrue(didDenySystemRequest, "The monitor must actually choose the system's Don't Allow action.")

        let expectedError = "续页需要“添加照片”权限才能保存。你仍可使用分享，也可在系统设置中允许添加照片。"
        XCTAssertTrue(app.alerts.staticTexts[expectedError].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.staticTexts["已保存到照片。"].exists)
        attachScreenshot("photos-add-denied-explanation", app: app)
        app.alerts.buttons["知道了"].tap()
        XCTAssertTrue(element("detail.preview").waitForExistence(timeout: 5))

        // A second save receives the real, persisted denied state without another prompt.
        app.buttons["detail.savePhotos"].tap()
        XCTAssertTrue(app.alerts.staticTexts[expectedError].waitForExistence(timeout: 10))
        app.alerts.buttons["知道了"].tap()
        XCTAssertTrue(element("detail.preview").exists)

        app.buttons["detail.share"].tap()
        XCTAssertTrue(element("ActivityListView").waitForExistence(timeout: 10))
        let copyAction = app.cells.matching(NSPredicate(format: "label == %@ OR label == %@", "拷贝", "Copy")).firstMatch
        XCTAssertTrue(copyAction.waitForExistence(timeout: 10),
                      "Wait for the system share extension to finish populating its real actions.")
        attachScreenshot("photos-denied-system-sharing-available", app: app)
        app.buttons["header.closeButton"].tap()
        XCTAssertTrue(element("detail.preview").waitForExistence(timeout: 5))
        attachScreenshot("photos-denied-original-still-available", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(remainingAllowance(), allowanceBefore,
                       "Denied saves and canceled system sharing must preserve the actual weekly allowance")
    }

    private func remainingAllowance() -> String {
        let settings = app.buttons["home.settings"]
        for _ in 0..<4 where !settings.isHittable { app.swipeDown() }
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let remaining = element("settings.remainingExports")
        for _ in 0..<3 where !remaining.isHittable { app.swipeUp() }
        XCTAssertTrue(remaining.waitForExistence(timeout: 5))
        let value = remaining.label
        XCTAssertTrue(value.contains("/ 50"))
        app.navigationBars["设置"].buttons["完成"].tap()
        return value
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum PermissionTestError: Error { case physicalDeviceNotAllowed }
}
