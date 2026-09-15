import XCTest
import UIKit
import CoreImage
import ScrollCaptureCore

/// Capture actual UIScrollView gestures once, then replay those same screenshots
/// through the production pipeline/transaction/export with seam selection on/off.
@MainActor
final class GlassSeamSimulatorCaptureTests: XCTestCase {
    private struct Rect: Decodable {
        let x: Double, y: Double, width: Double, height: Double
        var cg: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }
    private struct Card: Decodable { let id: String; let rect: Rect }
    private struct Icon: Decodable { let id: String; let opaqueInnerRect: Rect }
    private struct Layout: Decodable {
        let source: String, variant: String
        let glassOpacity: Double, screenScale: Double, contentOffset: Double, contentHeight: Double
        let viewport: Rect
        let cards: [Card]
        let icons: [Icon]
    }
    private struct Pose { let image: CGImage; let layout: Layout }

    func testLightGlassReadingEarlierUsesActualRetainedPixels() throws { try verify(dark: false, direction: -1) }
    func testLightGlassReadingLaterUsesActualRetainedPixels() throws { try verify(dark: false, direction: 1) }
    func testDarkGlassReadingEarlierUsesActualRetainedPixels() throws { try verify(dark: true, direction: -1) }
    func testDarkGlassReadingLaterUsesActualRetainedPixels() throws { try verify(dark: true, direction: 1) }

    private func verify(dark: Bool, direction: Int) throws {
        // Keep all failure assertions, but collect every frame/cut and export
        // before the route finishes so one rejection cannot hide its evidence.
        continueAfterFailure = true
        let app = XCUIApplication(bundleIdentifier: "dev.lzbaclz.longscreenshot.fixtures")
        app.launchArguments = ["--glass-grid"] + (dark ? ["--glass-dark"] : [])
        app.launch()
        defer { app.terminate() }
        let metadata = app.staticTexts["fixture.glass.metadata"]
        let scroll = app.scrollViews["fixture.glass.scroll"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 15))
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        var poses: [Pose] = []
        func capturePose() throws {
            let json = try XCTUnwrap(metadata.value as? String)
            let layout = try JSONDecoder().decode(Layout.self, from: Data(json.utf8))
            XCTAssertEqual(layout.source, "synthetic-glass-grid")
            XCTAssertEqual(layout.variant, dark ? "dark" : "light")
            let image = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
            attach(image, name: String(format: "glass-pose-%02d", poses.count))
            attach(Data(json.utf8), name: String(format: "glass-layout-%02d.json", poses.count), type: "public.json")
            poses.append(Pose(image: image, layout: layout))
        }
        try capturePose()
        try capturePose() // A pause supplies the same intended starting anchor.
        for _ in 0..<10 {
            let startY = direction < 0 ? 0.44 : 0.68
            let endY = direction < 0 ? 0.68 : 0.44
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            try capturePose()
        }
        // No metadata, card rectangles or offsets enter either matcher/scorer.
        let first = try XCTUnwrap(poses.first)
        let minimum = try XCTUnwrap(poses.map { $0.layout.contentOffset }.min())
        let maximum = try XCTUnwrap(poses.map { $0.layout.contentOffset }.max())
        XCTAssertGreaterThan(maximum - minimum, first.layout.viewport.height * 2,
                             "Ten real drags must cover more than two body screens")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassSeam-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let selectedRepository = try CaptureSessionRepository(rootURL: root.appendingPathComponent("selected"))
        let defaultRepository = try CaptureSessionRepository(rootURL: root.appendingPathComponent("default"))
        var selectedManifest = try selectedRepository.createSession(configuration: .init())
        var defaultManifest = try defaultRepository.createSession(configuration: .init())
        let selectedPipeline = CaptureFramePipeline(configuration: .init(), repository: selectedRepository, sessionID: selectedManifest.id)
        let defaultPipeline = CaptureFramePipeline(configuration: .init(), repository: defaultRepository, sessionID: defaultManifest.id)
        let context = CIContext(options: [.cacheIntermediates: false])
        var report: [[String: Any]] = []
        var reportPublished = false
        func publishReport() {
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                attach(data, name: "glass-actual-cuts-and-rejections.json", type: "public.json")
                reportPublished = true
            }
        }
        defer { if !reportPublished { publishReport() } }
        var defaultCutsInsideCards = 0, movedCutsOutsideCards = 0
        var rejectedAfterStart = 0
        for (index, pose) in poses.enumerated() {
            let gray = try CaptureFrameConversion.grayFrame(CIImage(cgImage: pose.image), context: context,
                                                           width: 144, height: pose.image.height)
            attach(Data(gray.pixels), name: String(format: "glass-gray-144x%d-%02d.bin", gray.height, index), type: "public.data")
            let optimized = try selectedPipeline.ingest(gray) { pose.image }
            let baseline = try defaultPipeline.ingest(gray) { pose.image }
            XCTAssertEqual(optimized.status, baseline.status, "Choosing source rows cannot alter matching decisions")
            XCTAssertEqual(optimized.strips.map { $0.image.height }, baseline.strips.map { $0.image.height })
            let previousCount = selectedManifest.diagnostics?.seams?.totalCount ?? 0
            let retainedBodyRows = selectedManifest.bodyPixelHeight
                + optimized.strips.filter { $0.isInitial }.reduce(0) { $0 + $1.image.height }
            _ = try selectedRepository.commit(optimized, maximumBodyHeight: 24_000, to: &selectedManifest)
            _ = try defaultRepository.commit(baseline, maximumBodyHeight: 24_000,
                                               seamSelectionEnabled: false, to: &defaultManifest)
            if !optimized.strips.isEmpty { selectedPipeline.confirmCommit() }
            if !baseline.strips.isEmpty { defaultPipeline.confirmCommit() }
            XCTAssertEqual(selectedManifest.pixelHeight, defaultManifest.pixelHeight,
                           "Replacement must not add or remove a document row")
            if selectedPipeline.hasStarted, optimized.status == .rejected { rejectedAfterStart += 1 }
            var item: [String: Any] = ["frame": index, "UIKitOffset": pose.layout.contentOffset,
                                       "status": String(describing: optimized.status),
                                       "foregroundStatus": selectedPipeline.diagnostics.foregroundStatus ?? "unrecorded",
                                       "outputHeight": selectedManifest.pixelHeight,
                                       "hasStarted": selectedPipeline.hasStarted,
                                       "matchingTopInset": selectedPipeline.effectiveConfiguration.topInset,
                                       "matchingBottomInset": selectedPipeline.effectiveConfiguration.bottomInset,
                                       "pendingAcceptedHeights": optimized.strips.map { $0.image.height },
                                       "pendingSourceTopPixels": optimized.strips.map { $0.sourceTopPixel },
                                       "pendingPlacements": optimized.strips.map { $0.placement.rawValue }]
            if (selectedManifest.diagnostics?.seams?.totalCount ?? 0) > previousCount {
                let seam = try XCTUnwrap(selectedManifest.diagnostics?.seams?.recent.last)
                let defaultSeam = try XCTUnwrap(defaultManifest.diagnostics?.seams?.recent.last)
                XCTAssertEqual(seam.defaultRow, defaultSeam.selectedRow)
                XCTAssertEqual(defaultSeam.replacedBodyRows, 0)
                let scale = Double(pose.image.width) / pose.layout.viewport.width
                func documentRow(_ pixel: Int) -> Double {
                    pose.layout.contentOffset + Double(pixel) / scale - pose.layout.viewport.y
                }
                let defaultDocumentRow = documentRow(seam.defaultRow)
                let selectedDocumentRow = documentRow(seam.selectedRow)
                let region = selectedPipeline.effectiveConfiguration
                let available = seam.direction == "prepend"
                    ? pose.image.height - region.bottomInset - seam.defaultRow : seam.defaultRow - region.topInset
                let overlap = min(available, retainedBodyRows)
                let searchLimit = max(0, min(480, overlap * 35 / 100, min(486, overlap) - 6))
                var geometricallyClearCandidates = 0
                if searchLimit > 0 {
                    for shift in 1...searchLimit {
                        let pixel = seam.defaultRow + (seam.direction == "prepend" ? shift : -shift)
                        let y0 = documentRow(pixel - 6), y1 = documentRow(pixel + 6)
                        if !pose.layout.cards.contains(where: { y0 < $0.rect.y + $0.rect.height && y1 > $0.rect.y }) {
                            geometricallyClearCandidates += 1
                        }
                    }
                }
                let defaultInside = insideCard(defaultDocumentRow, cards: pose.layout.cards)
                let selectedInside = insideCard(selectedDocumentRow, cards: pose.layout.cards)
                if defaultInside { defaultCutsInsideCards += 1 }
                let body = selectedManifest.strips.filter {
                    $0.id != selectedManifest.leadingEdgeStripID && $0.id != selectedManifest.trailingEdgeStripID
                }
                let incomingStrip = try XCTUnwrap(seam.direction == "prepend" ? body.first : body.last)
                let actualCut = seam.direction == "prepend"
                    ? incomingStrip.sourceTopPixel + incomingStrip.pixelHeight : incomingStrip.sourceTopPixel
                XCTAssertEqual(actualCut, seam.selectedRow, "Check the cut actually published, not just its planned diagnostic")
                let defaultBody = defaultManifest.strips.filter {
                    $0.id != defaultManifest.leadingEdgeStripID && $0.id != defaultManifest.trailingEdgeStripID
                }
                let defaultIncomingStrip = try XCTUnwrap(seam.direction == "prepend" ? defaultBody.first : defaultBody.last)
                let defaultActualCut = seam.direction == "prepend"
                    ? defaultIncomingStrip.sourceTopPixel + defaultIncomingStrip.pixelHeight : defaultIncomingStrip.sourceTopPixel
                XCTAssertEqual(defaultActualCut, defaultSeam.selectedRow)
                let stored = try selectedRepository.readCaptureStrip(incomingStrip, sessionID: selectedManifest.id)
                let original = try XCTUnwrap(pose.image.cropping(to: CGRect(x: 0, y: incomingStrip.sourceTopPixel,
                                                                            width: incomingStrip.pixelWidth, height: incomingStrip.pixelHeight)))
                XCTAssertEqual(rgba(stored), rgba(original), "Incoming side of each seam must be original source pixels")
                if seam.applied {
                    XCTAssertFalse(selectedInside, "Applied cut passes through a glass card")
                    XCTAssertEqual(seam.reason, "selected")
                    if defaultInside { movedCutsOutsideCards += 1 }
                } else {
                    XCTAssertEqual(seam.selectedRow, seam.defaultRow)
                    XCTAssertNotEqual(seam.reason, "selected")
                }
                // This is an independent geometric observation, not evidence
                // supplied to the selector. Labels or texture can still make a
                // geometrically clear row unsuitable, so fallback is explicit.
                item["geometricallyClearCandidates"] = geometricallyClearCandidates
                item["searchLimit"] = searchLimit
                item["defaultDocumentRow"] = defaultDocumentRow
                item["actualDocumentRow"] = selectedDocumentRow
                item["defaultInsideCard"] = defaultInside
                item["actualInsideCard"] = selectedInside
                item["replacedBodyRows"] = seam.replacedBodyRows
                item["reason"] = seam.reason
                item["defaultScore"] = seam.defaultScore ?? -1
                item["selectedScore"] = seam.selectedScore ?? -1
            }
            report.append(item)
        }
        publishReport() // Evidence exists before any aggregate assertion/export.
        XCTAssertTrue(selectedPipeline.hasStarted, "Real matcher must establish motion; no supplied oracle displacement")
        XCTAssertEqual(rejectedAfterStart, 0, "Record rejected frames; do not silently reduce the required route")
        XCTAssertGreaterThan(defaultCutsInsideCards, 0, "This route must exercise the original in-card seam problem")
        XCTAssertGreaterThan(movedCutsOutsideCards, 0, "At least one problematic default must actually move to a gap")
        selectedManifest.finalizeCapture(reason: "Synthetic glass simulator screenshots", partial: false)
        defaultManifest.finalizeCapture(reason: "Same screenshots, default seam comparison", partial: false)
        try selectedRepository.saveManifest(selectedManifest)
        try defaultRepository.saveManifest(defaultManifest)
        let selectedURL = try CaptureImageRenderer(repository: selectedRepository).export(sessionID: selectedManifest.id)
        let defaultURL = try CaptureImageRenderer(repository: defaultRepository).export(sessionID: defaultManifest.id)
        let selectedImage = try XCTUnwrap(UIImage(contentsOfFile: selectedURL.path)?.cgImage)
        let defaultImage = try XCTUnwrap(UIImage(contentsOfFile: defaultURL.path)?.cgImage)
        attach(selectedImage, name: "glass-selected-export")
        attach(defaultImage, name: "glass-default-export-same-inputs")
        XCTAssertEqual(selectedImage.height, defaultImage.height)
        let scale = Double(first.image.width) / first.layout.viewport.width
        XCTAssertEqual(Double(selectedImage.height), Double(first.image.height) + (maximum - minimum) * scale,
                       accuracy: Double(poses.count), "Independent UIKit range must remain unchanged")
        do {
            try verifyOriginalSources(repository: selectedRepository, manifest: selectedManifest, poses: poses,
                                      minimum: minimum, scale: scale)
        } catch { XCTFail("Original source oracle could not finish: \(error)") }
        do {
            try verifyIcons(output: selectedImage, poses: poses, minimum: minimum, maximum: maximum, scale: scale)
        } catch { XCTFail("Icon oracle could not finish: \(error)") }
        do {
            try verifyEdges(output: selectedImage, poses: poses, minimum: minimum, maximum: maximum, scale: scale)
        } catch { XCTFail("Outer edge oracle could not finish: \(error)") }
    }

    private func insideCard(_ y: Double, cards: [Card]) -> Bool {
        cards.contains { y > $0.rect.y && y < $0.rect.y + $0.rect.height }
    }

    private func verifyOriginalSources(repository: CaptureSessionRepository, manifest: CaptureSessionManifest,
                                       poses: [Pose], minimum: Double, scale: Double) throws {
        let first = try XCTUnwrap(poses.first)
        var outputY = 0
        for strip in manifest.strips {
            defer { outputY += strip.pixelHeight }
            let stored = try repository.readCaptureStrip(strip, sessionID: manifest.id)
            let bytes = rgba(stored)
            let isBody = strip.id != manifest.leadingEdgeStripID && strip.id != manifest.trailingEdgeStripID
            let expectedDocumentY = minimum * scale + Double(outputY) - first.layout.viewport.y * scale
            let source = poses.first { pose in
                // A fixed-background-only strip can be byte-identical in
                // several poses. Its legitimate source must satisfy BOTH the
                // original document-coordinate oracle and exact pixel equality.
                if isBody {
                    let candidateDocumentY = pose.layout.contentOffset * scale + Double(strip.sourceTopPixel)
                        - pose.layout.viewport.y * scale
                    guard abs(candidateDocumentY - expectedDocumentY) <= 2 else { return false }
                }
                guard strip.sourceTopPixel + strip.pixelHeight <= pose.image.height,
                      let original = pose.image.cropping(to: CGRect(x: 0, y: strip.sourceTopPixel,
                                                                   width: strip.pixelWidth, height: strip.pixelHeight)) else { return false }
                return rgba(original) == bytes
            }
            let found = try XCTUnwrap(source, "Every retained strip must match one actual source in both pixels and document coordinates, including trimmed old strips")
            if isBody {
                XCTAssertGreaterThanOrEqual(strip.sourceTopPixel, Int((found.layout.viewport.y * scale).rounded()),
                                             "Fixed header pixels cannot recur inside a retained body strip")
                XCTAssertLessThanOrEqual(strip.sourceTopPixel + strip.pixelHeight,
                                          Int(((found.layout.viewport.y + found.layout.viewport.height) * scale).rounded()),
                                          "Fixed footer pixels cannot recur inside a retained body strip")
                let actualDocumentY = found.layout.contentOffset * scale + Double(strip.sourceTopPixel) - found.layout.viewport.y * scale
                XCTAssertEqual(actualDocumentY, expectedDocumentY, accuracy: 2,
                               "Retained source interval must occupy its real document coordinates")
            }
        }
        XCTAssertEqual(outputY, manifest.pixelHeight)
        XCTAssertEqual(manifest.strips.filter { $0.id == manifest.leadingEdgeStripID }.count, 1)
        XCTAssertEqual(manifest.strips.filter { $0.id == manifest.trailingEdgeStripID }.count, 1)
    }

    private func verifyIcons(output: CGImage, poses: [Pose], minimum: Double, maximum: Double, scale: Double) throws {
        let first = try XCTUnwrap(poses.first)
        var verified: [String] = []
        for icon in first.layout.icons {
            let inner = icon.opaqueInnerRect.cg.insetBy(dx: 2, dy: 2)
            guard inner.minY >= minimum, inner.maxY <= maximum + first.layout.viewport.height else { continue }
            let source = try XCTUnwrap(poses.first {
                inner.minY >= $0.layout.contentOffset + 2 && inner.maxY <= $0.layout.contentOffset + $0.layout.viewport.height - 2
            }, "No captured pose fully contains icon \(icon.id)")
            let sourceRect = CGRect(x: inner.minX * scale,
                                    y: (source.layout.viewport.y + inner.minY - source.layout.contentOffset) * scale,
                                    width: inner.width * scale, height: inner.height * scale).integral
            let original = try XCTUnwrap(source.image.cropping(to: sourceRect))
            let outputY = (first.layout.viewport.y + inner.minY - minimum) * scale
            var error = Double.infinity
            for dy in -2...2 {
                let rect = CGRect(x: sourceRect.minX, y: CGFloat(outputY.rounded(.down) + Double(dy)),
                                  width: CGFloat(original.width), height: CGFloat(original.height))
                if let actual = output.cropping(to: rect) { error = min(error, mae(actual, original)) }
            }
            XCTAssertLessThan(error, 2.5, "Icon \(icon.id) is missing, repeated, damaged or misplaced")
            verified.append(icon.id)
        }
        XCTAssertGreaterThanOrEqual(verified.count, 24)
        attach(Data(verified.joined(separator: "\n").utf8), name: "glass-verified-icon-order.txt", type: "public.plain-text")
    }

    private func verifyEdges(output: CGImage, poses: [Pose], minimum: Double, maximum: Double, scale: Double) throws {
        let first = try XCTUnwrap(poses.first)
        let earliest = try XCTUnwrap(poses.first { $0.layout.contentOffset == minimum })
        let latest = try XCTUnwrap(poses.first { $0.layout.contentOffset == maximum })
        let headerHeight = Int((first.layout.viewport.y * scale).rounded())
        let footerStart = Int(((first.layout.viewport.y + first.layout.viewport.height) * scale).rounded())
        let footerHeight = first.image.height - footerStart
        let header = try XCTUnwrap(earliest.image.cropping(to: CGRect(x: 0, y: 0, width: first.image.width, height: headerHeight)))
        let outputHeader = try XCTUnwrap(output.cropping(to: CGRect(x: 0, y: 0, width: output.width, height: headerHeight)))
        let footer = try XCTUnwrap(latest.image.cropping(to: CGRect(x: 0, y: footerStart, width: first.image.width, height: footerHeight)))
        let outputFooter = try XCTUnwrap(output.cropping(to: CGRect(x: 0, y: output.height - footerHeight, width: output.width, height: footerHeight)))
        XCTAssertEqual(rgba(header), rgba(outputHeader))
        XCTAssertEqual(rgba(footer), rgba(outputFooter))
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    private func mae(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height else { return .infinity }
        let left = rgba(a), right = rgba(b)
        var sum = 0
        for index in left.indices where index % 4 != 3 { sum += abs(Int(left[index]) - Int(right[index])) }
        return Double(sum) / Double(a.width * a.height * 3)
    }

    private func attach(_ image: CGImage, name: String) {
        let value = XCTAttachment(image: UIImage(cgImage: image))
        value.name = name; value.lifetime = .keepAlways; add(value)
    }

    private func attach(_ data: Data, name: String, type: String) {
        let value = XCTAttachment(data: data, uniformTypeIdentifier: type)
        value.name = name; value.lifetime = .keepAlways; add(value)
    }
}
