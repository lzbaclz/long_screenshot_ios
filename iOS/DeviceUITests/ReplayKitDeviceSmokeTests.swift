import XCTest

/// This suite deliberately exercises real ReplayKit on a signed, unlocked iPhone.
/// Only Longlet and our separately installed synthetic FixtureReader are opened.
@MainActor
final class ReplayKitDeviceSmokeTests: XCTestCase {
    private var host: XCUIApplication!
    private var fixture: XCUIApplication!
    private var system: XCUIApplication!
    private var requestedBroadcast = false

    override func setUp() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Real cross-app capture requires a physical iPhone; simulator demo is not equivalent.")
        #else
        continueAfterFailure = false
        // Create XCUIApplication proxies after XCTest has established its driver
        // session; eager property initialization can request a device channel too early.
        host = XCUIApplication(bundleIdentifier: "dev.lzbaclz.longscreenshot")
        fixture = XCUIApplication(bundleIdentifier: "dev.lzbaclz.longscreenshot.fixtures")
        system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        host.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        fixture.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        #endif
    }

    override func tearDown() async throws {
        guard requestedBroadcast else { return }
        dismissKnownBroadcastNotice()
        host.activate()
        if element("capture.stop", in: host).exists {
            let stop = host.buttons["capture.stop"]
            for _ in 0..<3 where !stop.isHittable { host.swipeUp() }
            if stop.isHittable { stop.tap() }
        }
        dismissKnownBroadcastNotice()
        requestedBroadcast = false
    }

    func testRealReplayKitCapturesSyntheticRowsAndStopsAfterFiveSeconds() throws {
        let startedAt = Date()
        host.launch()
        XCTAssertTrue(host.buttons["home.settings"].waitForExistence(timeout: 15),
                      "Unlock the iPhone and allow developer UI testing before retrying.")
        guard !host.buttons["capture.stop"].exists else {
            throw XCTSkip("An existing capture is still active. Finish it before running this isolated device test.")
        }
        fixture.launch()
        XCTAssertTrue(element("fixture.scroll", in: fixture).waitForExistence(timeout: 15),
                      "Install our signed FixtureReader app before running this device test.")
        fixture.buttons["fixture.reset"].tap()
        attachScreenshot("device-fixture-start", app: fixture)

        host.activate()
        XCTAssertTrue(host.buttons["home.settings"].waitForExistence(timeout: 15),
                      "Unlock the iPhone and allow developer UI testing before retrying.")
        XCTAssertFalse(element("capture.simulatorNotice", in: host).exists)
        finishGuideIfNeeded()
        host.buttons["home.settings"].tap()
        let idlePicker = host.buttons["settings.idleStop"]
        XCTAssertTrue(idlePicker.waitForExistence(timeout: 5))
        idlePicker.tap()
        XCTAssertTrue(host.buttons["静止 5 秒"].waitForExistence(timeout: 5))
        host.buttons["静止 5 秒"].tap()
        attachScreenshot("device-settings-idle-five", app: host)
        host.navigationBars["设置"].buttons["完成"].tap()

        openGallery()
        let previousCaptureIDs = captureRowIDs()
        host.navigationBars["我的长图"].buttons["完成"].tap()
        let picker = element("capture.systemPicker", in: host)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        for _ in 0..<3 where !picker.isHittable { host.swipeDown() }
        attachScreenshot("device-capture-ready", app: host)
        picker.tap()

        let start = try waitForSystemStartButton()
        attachScreenshot("device-system-broadcast-picker", app: system)
        // preferredExtension is set by the host's public RPSystemBroadcastPickerView.
        // Use the actual system Start Broadcast control; no private APIs or fake frames.
        start.tap()
        requestedBroadcast = true
        Thread.sleep(forTimeInterval: 3.5)
        fixture.activate()
        XCTAssertTrue(element("fixture.scroll", in: fixture).waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        let scroll = element("fixture.scroll", in: fixture)
        attachScreenshot("device-fixture-broadcasting", app: fixture)
        for _ in 0..<7 {
            // A short, slow drag leaves substantial overlap between admitted frames.
            let lower = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.72))
            let upper = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.51))
            lower.press(forDuration: 0.12, thenDragTo: upper, withVelocity: .slow, thenHoldForDuration: 0.25)
            Thread.sleep(forTimeInterval: 0.3)
        }
        attachScreenshot("device-fixture-after-scroll", app: fixture)
        // Stay on the synthetic page while the configured five-second idle timer completes.
        Thread.sleep(forTimeInterval: 7)
        attachScreenshot("device-idle-completion", app: system)
        dismissKnownBroadcastNotice()
        host.activate()
        XCTAssertTrue(host.buttons["home.settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(host.buttons["capture.stop"].exists,
                       "Capture did not finish on idle; a manual stop in teardown does not count as success.")

        openGallery()
        let newCaptureID = try waitForNewCapture(excluding: previousCaptureIDs)
        host.buttons[newCaptureID].tap()
        XCTAssertTrue(host.navigationBars["长图预览"].waitForExistence(timeout: 10))
        XCTAssertFalse(host.navigationBars["长图示例"].exists)
        XCTAssertTrue(element("detail.preview", in: host).waitForExistence(timeout: 10),
                      "The real capture must contain a readable saved image.")
        attachScreenshot("device-real-capture-preview", app: host)
        host.buttons["detail.edit"].tap()
        host.segmentedControls["editor.mode"].buttons["接缝"].tap()
        XCTAssertTrue(host.sliders["editor.seamTrim"].waitForExistence(timeout: 10),
                      "At least two persisted image strips are required; a single still frame is insufficient.")
        attachScreenshot("device-real-capture-multiple-strips", app: host)
        host.navigationBars["编辑长图"].buttons["取消"].tap()
        requestedBroadcast = false

        let evidence: [String: Any] = [
            "captureRowIdentifier": newCaptureID,
            "testStartedAtUnix": startedAt.timeIntervalSince1970,
            "testFinishedAtUnix": Date().timeIntervalSince1970,
            "source": "FixtureReader synthetic numbered rows",
            "simulator": false,
            "demoLaunchArgument": false,
            "requestedIdleStopSeconds": 5,
            "slowScrollDrags": 7
        ]
        let data = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "device-real-capture-evidence.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func finishGuideIfNeeded() {
        if host.buttons["capture.startGuide"].exists {
            host.buttons["capture.startGuide"].tap()
            XCTAssertTrue(host.navigationBars["使用指南"].buttons["完成"].waitForExistence(timeout: 5))
            host.navigationBars["使用指南"].buttons["完成"].tap()
        }
    }

    private func openGallery() {
        let button = host.buttons["home.allCaptures"]
        for _ in 0..<4 where !button.isHittable { host.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(host.navigationBars["我的长图"].waitForExistence(timeout: 5))
    }

    private func captureRowIDs() -> Set<String> {
        Set(host.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "capture.row."))
            .allElementsBoundByIndex.map(\.identifier))
    }

    private func waitForNewCapture(excluding previous: Set<String>) throws -> String {
        for _ in 0..<10 {
            if let newID = captureRowIDs().subtracting(previous).first { return newID }
            Thread.sleep(forTimeInterval: 1)
        }
        attachHierarchy("device-missing-result")
        XCTFail("No new real capture appeared. Existing captures must not satisfy this test.")
        throw DeviceSmokeError.noNewCapture
    }

    private func waitForSystemStartButton() throws -> XCUIElement {
        let candidates = ["开始广播", "Start Broadcast", "开始屏幕广播"]
        for _ in 0..<10 {
            for application in [host, system].compactMap({ $0 }) {
                for title in candidates {
                    let button = application.buttons[title]
                    if button.exists && button.isHittable { return button }
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        attachHierarchy("device-broadcast-picker-unresolved")
        XCTFail("The system broadcast picker needs attention; inspect the attached system screenshot and hierarchy.")
        throw DeviceSmokeError.missingSystemStart
    }

    private func dismissKnownBroadcastNotice() {
        for application in [host, system].compactMap({ $0 }) {
            for alert in application.alerts.allElementsBoundByIndex {
                let text = alert.label + " " + alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
                guard text.contains("广播") || text.contains("broadcast") || text.contains("Longlet") || text.contains("续页") else { continue }
                for title in ["好", "好的", "确定", "OK"] where alert.buttons[title].exists {
                    alert.buttons[title].tap()
                    break
                }
            }
        }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachHierarchy(_ name: String) {
        attachScreenshot(name, app: system)
        let attachment = XCTAttachment(string: "HOST\n\(host.debugDescription)\nSYSTEM\n\(system.debugDescription)")
        attachment.name = name + "-hierarchy"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum DeviceSmokeError: Error { case missingSystemStart, noNewCapture }
}
