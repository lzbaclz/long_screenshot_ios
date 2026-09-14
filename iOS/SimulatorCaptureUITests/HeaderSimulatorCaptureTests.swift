import XCTest
import UIKit
import CoreImage
import ScrollCaptureCore

/// Real UIScrollView gestures and simulator screenshots are injected into the
/// production Shared pipeline. This does not exercise ReplayKit on a device.
@MainActor
final class HeaderSimulatorCaptureTests: XCTestCase {
    private struct Rect: Decodable {
        let x: Double, y: Double, width: Double, height: Double
        var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }
    private struct Point: Decodable { let x: Double, y: Double }
    private struct Message: Decodable {
        let id: String
        let bubbleRect: Rect
        let opaqueInnerRect: Rect
    }
    private struct Layout: Decodable {
        let formatVersion: Int
        let source: String
        let indicatorVisible: Bool
        let contentOffset: Point
        let viewport: Rect
        let contentHeight: Double
        let screenScale: Double
        let messages: [Message]
    }
    private struct Pose {
        let image: CGImage
        let layout: Layout
        let metadata: String
    }

    func testSameColorHeaderAppearingIndicatorReadsEarlierMessages() throws {
        try verify(route: Array(repeating: -1, count: 10))
    }

    func testSameColorHeaderDisappearingIndicatorReadsLaterMessages() throws {
        try verify(route: Array(repeating: 1, count: 10), initiallyVisible: true)
    }

    func testSameColorHeaderReversesWithoutDuplicatingMessagesOrFixedBars() throws {
        try verify(route: Array(repeating: -1, count: 5)
                   + Array(repeating: 1, count: 10) + Array(repeating: -1, count: 12))
    }

    private func verify(route: [Int], initiallyVisible: Bool = false) throws {
        continueAfterFailure = false
        let fixture = XCUIApplication(bundleIdentifier: "dev.lzbaclz.longscreenshot.fixtures")
        // IDs exist only in UIKit metadata; the matcher sees ordinary message
        // pixels, not artificial numbered labels that could make alignment easy.
        fixture.launchArguments = ["--same-color-header-chat", "--wallpaper-hide-identifiers",
                                   initiallyVisible ? "--recording-indicator-in-first-frame"
                                       : "--recording-indicator-after-first-frame"]
        fixture.launch()
        defer { fixture.terminate() }
        let metadata = fixture.staticTexts["fixture.wallpaper.metadata"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 15))
        let scroll = fixture.scrollViews["fixture.wallpaper.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HeaderSimulator-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try CaptureSessionRepository(rootURL: root)
        var manifest = try repository.createSession(configuration: .init())
        let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: manifest.id)
        let context = CIContext(options: [.cacheIntermediates: false])
        var poses: [Pose] = []
        var frameResults: [[String: Any]] = []

        func ingest() throws {
            let json = try XCTUnwrap(metadata.value as? String)
            let layout = try JSONDecoder().decode(Layout.self, from: Data(json.utf8))
            XCTAssertEqual(layout.source, "synthetic-same-color-header-chat")
            let image = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
            let pose = Pose(image: image, layout: layout, metadata: json)
            let began = ProcessInfo.processInfo.systemUptime
            let gray = try CaptureFrameConversion.grayFrame(CIImage(cgImage: image), context: context,
                                                           width: 144, height: image.height)
            let result = try pipeline.ingest(gray) { image }
            // Geometry is provided by UIKit, independently of detector insets.
            // Every emitted body strip must be entirely inside the real scroll
            // viewport, including the delayed initial strip from the first pose.
            for strip in result.strips {
                let source: Pose
                if strip.isInitial { source = try XCTUnwrap(poses.first) }
                else { source = pose }
                let scale = Double(source.image.width) / source.layout.viewport.width
                let bodyTop = Int((source.layout.viewport.y * scale).rounded())
                let bodyBottom = Int(((source.layout.viewport.y + source.layout.viewport.height) * scale).rounded())
                XCTAssertGreaterThanOrEqual(strip.sourceTopPixel, bodyTop,
                                             "Body strip includes status/navigation bar rows")
                XCTAssertLessThanOrEqual(strip.sourceTopPixel + strip.image.height, bodyBottom,
                                          "Body strip includes fixed footer rows")
            }
            _ = try repository.commit(result, maximumBodyHeight: 24_000, to: &manifest)
            if !result.strips.isEmpty { pipeline.confirmCommit() }
            poses.append(pose)
            attach(image: image, name: String(format: "pose-%02d", poses.count - 1))
            attach(data: Data(gray.pixels), name: String(format: "gray-144x%d-%02d.bin", gray.height, poses.count - 1),
                   type: "public.data")
            frameResults.append(["offsetPoints": layout.contentOffset.y,
                                 "indicatorVisible": layout.indicatorVisible,
                                 "status": String(describing: result.status),
                                 "strips": result.strips.count,
                                 "topInset": pipeline.effectiveConfiguration.topInset,
                                 "bottomInset": pipeline.effectiveConfiguration.bottomInset,
                                 "foregroundStatus": pipeline.diagnostics.foregroundStatus ?? "unrecorded",
                                 "foregroundSupport": pipeline.diagnostics.foregroundSupportCount ?? 0,
                                 "milliseconds": (ProcessInfo.processInfo.systemUptime - began) * 1000])
        }

        try ingest()
        XCTAssertEqual(poses.first?.layout.indicatorVisible, initiallyVisible)
        let toggle = fixture.buttons["fixture.header.toggle-indicator"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        let toggledValue = initiallyVisible ? "hidden" : "visible"
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", toggledValue), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        try ingest() // The overlay changes at the original, unscrolled anchor.
        XCTAssertEqual(poses.last?.layout.indicatorVisible, !initiallyVisible)
        XCTAssertEqual(poses.last?.layout.contentOffset.y, poses.first?.layout.contentOffset.y)
        let beforeToggle = try XCTUnwrap(poses.first)
        let afterToggle = try XCTUnwrap(poses.last)
        let initialScale = Double(beforeToggle.image.width) / beforeToggle.layout.viewport.width
        let headerRect = CGRect(x: 0, y: 0, width: beforeToggle.image.width,
                                height: Int((beforeToggle.layout.viewport.y * initialScale).rounded()))
        let beforeHeader = try XCTUnwrap(beforeToggle.image.cropping(to: headerRect))
        let afterHeader = try XCTUnwrap(afterToggle.image.cropping(to: headerRect))
        let togglePixelError = meanAbsoluteError(beforeHeader, afterHeader)
        attach(image: beforeHeader, name: "header-before-indicator-toggle")
        attach(image: afterHeader, name: "header-after-indicator-toggle")
        attach(data: try JSONSerialization.data(withJSONObject: ["headerTogglePixelMAE": togglePixelError],
                                               options: [.prettyPrinted]),
               name: "visible-header-toggle-pixel-difference.json", type: "public.json")
        XCTAssertGreaterThan(togglePixelError, 1,
                             "The two input screenshots must visibly differ in the fixed header, even with the Dynamic Island")
        for direction in route {
            let startY = direction < 0 ? 0.44 : 0.68
            let endY = direction < 0 ? 0.68 : 0.44
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: startY))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: endY))
            // Holding at the end avoids fling inertia; contentOffset remains
            // actual UIKit geometry and never comes from matcher output.
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            try ingest()
        }
        let report = try JSONSerialization.data(withJSONObject: frameResults, options: [.prettyPrinted, .sortedKeys])
        attach(data: report, name: "actual-scroll-offsets-and-pipeline-results.json", type: "public.json")
        let first = try XCTUnwrap(poses.first)
        let last = try XCTUnwrap(poses.last)
        attach(image: first.image, name: "same-color-header-chat-start")
        attach(image: last.image, name: "same-color-header-chat-last")
        attach(data: Data(first.metadata.utf8), name: "UIKit-layout-oracle.json", type: "public.json")

        XCTAssertTrue(pipeline.hasStarted, "Transient header UI must not prevent real message motion from starting capture")
        let minimum = try XCTUnwrap(poses.map { $0.layout.contentOffset.y }.min())
        let maximum = try XCTUnwrap(poses.map { $0.layout.contentOffset.y }.max())
        let scale = CGFloat(first.image.width) / first.layout.viewport.width
        XCTAssertGreaterThan(maximum - minimum, first.layout.viewport.height * 2,
                             "The gestures must cover several screens, not just add one small strip")
        manifest.finalizeCapture(reason: "Simulator screenshot injection finished", partial: false)
        try repository.saveManifest(manifest)
        let outputURL = try CaptureImageRenderer(repository: repository).export(sessionID: manifest.id)
        let output = try XCTUnwrap(UIImage(contentsOfFile: outputURL.path)?.cgImage)
        attach(image: output, name: "same-color-header-chat-complete-export")
        let expectedHeight = Double(first.image.height) + (maximum - minimum) * scale
        XCTAssertEqual(Double(output.height), expectedHeight, accuracy: Double(route.count + 2),
                       "Output range must equal the independent UIScrollView range")

        // Preserve the complete fixed edges from the independently determined
        // earliest and latest document positions, not from matcher diagnostics.
        let earliest = try XCTUnwrap(poses.first(where: { $0.layout.contentOffset.y == minimum }))
        let latest = try XCTUnwrap(poses.first(where: { $0.layout.contentOffset.y == maximum }))
        let headerHeight = Int((first.layout.viewport.y * scale).rounded())
        let footerStart = Int(((first.layout.viewport.y + first.layout.viewport.height) * scale).rounded())
        let footerHeight = first.image.height - footerStart
        let expectedHeader = try XCTUnwrap(earliest.image.cropping(to: CGRect(x: 0, y: 0,
                                                                           width: first.image.width, height: headerHeight)))
        let actualHeader = try XCTUnwrap(output.cropping(to: CGRect(x: 0, y: 0,
                                                                  width: output.width, height: headerHeight)))
        XCTAssertEqual(meanAbsoluteError(actualHeader, expectedHeader), 0, "Earliest source header must remain pixel exact")
        let expectedFooter = try XCTUnwrap(latest.image.cropping(to: CGRect(x: 0, y: footerStart,
                                                                           width: first.image.width, height: footerHeight)))
        let actualFooter = try XCTUnwrap(output.cropping(to: CGRect(x: 0, y: output.height - footerHeight,
                                                                  width: output.width, height: footerHeight)))
        XCTAssertEqual(meanAbsoluteError(actualFooter, expectedFooter), 0, "Latest source footer must remain pixel exact")
        // Search ordinary title + back-arrow pixels throughout the final PNG.
        // This verifies a single visible fixed header independently of both
        // output height and the diagnostic/matching inset values.
        let titleRect = CGRect(x: 10 * scale, y: 55 * scale,
                               width: (first.layout.viewport.width - 20) * scale, height: 27 * scale).integral
        let title = try XCTUnwrap(expectedHeader.cropping(to: titleRect))
        XCTAssertEqual(templateOccurrences(template: title, in: earliest.image, x: Int(titleRect.minX)).count, 1,
                       "The ordinary title template must first locate its source header")
        let occurrences = templateOccurrences(template: title, in: output, x: Int(titleRect.minX))
        XCTAssertEqual(occurrences.count, 1, "Fixed title/back arrow repeated at output rows \(occurrences)")
        attach(data: try JSONSerialization.data(withJSONObject: ["titleTemplateRows": occurrences], options: [.prettyPrinted]),
               name: "header-template-occurrences.json", type: "public.json")

        // An opaque bubble's pixels are independent of the background. Check
        // every complete covered message in natural document order, using the
        // clearest actual screenshot containing it as the independent oracle.
        var verifiedMessages: [String] = []
        for message in first.layout.messages {
            let body = message.bubbleRect.cgRect
            guard body.minY >= minimum, body.maxY <= maximum + first.layout.viewport.height else { continue }
            let interior = message.opaqueInnerRect.cgRect.insetBy(dx: 2, dy: 2)
            let candidates = poses.filter { pose in
                let offset = pose.layout.contentOffset.y
                return interior.minY >= offset + 2 && interior.maxY <= offset + pose.layout.viewport.height - 2
            }
            let source = try XCTUnwrap(candidates.first, "No source pose fully contains \(message.id)")
            let sourceRect = CGRect(x: interior.minX * scale,
                                    y: (source.layout.viewport.y + interior.minY - source.layout.contentOffset.y) * scale,
                                    width: interior.width * scale, height: interior.height * scale).integral
            let expected = try XCTUnwrap(source.image.cropping(to: sourceRect))
            let outputY = (first.layout.viewport.y + interior.minY - minimum) * scale
            // Subpixel UIKit offsets and horizontal analysis downsampling can
            // round a native row. Search only ±2 px, never a different message.
            var bestError = Double.infinity
            for adjustment in -2...2 {
                let rectangle = CGRect(x: sourceRect.minX, y: outputY.rounded(.down) + CGFloat(adjustment),
                                       width: CGFloat(expected.width), height: CGFloat(expected.height))
                if let actual = output.cropping(to: rectangle) {
                    bestError = min(bestError, meanAbsoluteError(actual, expected))
                }
            }
            XCTAssertLessThan(bestError, 2.5, "Message \(message.id) is missing, duplicated, damaged, or out of order (pixel MAE \(bestError))")
            verifiedMessages.append(message.id)
        }
        XCTAssertGreaterThanOrEqual(verifiedMessages.count, 12, "Verify enough separate messages across the complete export")
        attach(data: Data(verifiedMessages.joined(separator: "\n").utf8), name: "verified-message-order.txt", type: "public.plain-text")
    }

    private func attach(image: CGImage, name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func attach(data: Data, name: String, type: String) {
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: type)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func meanAbsoluteError(_ actual: CGImage, _ expected: CGImage) -> Double {
        guard actual.width == expected.width, actual.height == expected.height else { return .infinity }
        let left = bytes(actual), right = bytes(expected)
        var sum = 0
        for index in left.indices where index % 4 != 3 { sum += abs(Int(left[index]) - Int(right[index])) }
        return Double(sum) / Double(actual.width * actual.height * 3)
    }

    /// A bounded sample of dark glyph and surrounding light pixels avoids an
    /// expensive full cross-correlation. Adjacent matching rows form one hit.
    private func templateOccurrences(template: CGImage, in output: CGImage, x: Int) -> [Int] {
        let reference = bytes(template), actual = bytes(output)
        struct Sample { let x: Int; let y: Int; let value: Int }
        var dark: [Sample] = [], light: [Sample] = []
        for y in 0..<template.height {
            for column in 0..<template.width {
                let index = (y * template.width + column) * 4
                let value = (Int(reference[index]) + Int(reference[index + 1]) + Int(reference[index + 2])) / 3
                if value < 80 { dark.append(Sample(x: column, y: y, value: value)) }
                else if value > 220 { light.append(Sample(x: column, y: y, value: value)) }
            }
        }
        guard dark.count >= 40, light.count >= 40, output.height >= template.height else { return [] }
        var samples: [Sample] = []
        samples.reserveCapacity(80)
        for index in 0..<40 {
            let sampleIndex = index * (dark.count - 1) / 39
            samples.append(dark[sampleIndex])
        }
        for index in 0..<40 {
            let sampleIndex = index * (light.count - 1) / 39
            samples.append(light[sampleIndex])
        }
        var occurrences: [Int] = []
        var lastMatchingRow = -10
        for row in 0...(output.height - template.height) {
            var total = 0
            for sample in samples {
                let index = ((row + sample.y) * output.width + x + sample.x) * 4
                let value = (Int(actual[index]) + Int(actual[index + 1]) + Int(actual[index + 2])) / 3
                total += abs(value - sample.value)
                if total > samples.count * 4 { break }
            }
            if total <= samples.count * 4 {
                if row - lastMatchingRow > 2 { occurrences.append(row) }
                lastMatchingRow = row
            }
        }
        return occurrences
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
        result.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return result
    }

}
