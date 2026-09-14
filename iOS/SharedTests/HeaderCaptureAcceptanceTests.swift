import XCTest
import UIKit
import CoreImage
import ScrollCaptureCore
@testable import ScrollCapture

/// Synthetic source pixels only. The expected image uses known document
/// coordinates and complete original bars, never the inferred matching insets.
final class HeaderCaptureAcceptanceTests: XCTestCase {
    func testNative1179HeaderChangesWhileStartingUpwardPreserveEveryPixel() throws {
        try assertHeaderCapture(width: 1_179, height: 2_556, upward: true)
    }

    func testNative886HeaderChangesWhileStartingUpwardPreserveEveryPixel() throws {
        try assertHeaderCapture(width: 886, height: 1_920, upward: true)
    }

    func testNative1179DisappearingIndicatorWhileStartingDownwardPreservesEveryPixel() throws {
        try assertHeaderCapture(width: 1_179, height: 2_556, upward: false)
    }

    func testManualRegionRecordsInsetsButNeverAppliesFixedStructureGuard() throws {
        try assertHeaderCapture(width: 144, height: 2_556, upward: true, manual: true)
    }

    func testUnacceptedStartDoesNotReportMatchingOrGuardValues() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let first = try GrayFrame(width: 144, height: 800, pixels: [UInt8](repeating: 237, count: 144 * 800))
        let changed = try GrayFrame(width: 144, height: 800, pixels: [UInt8](repeating: 80, count: 144 * 800))
        _ = try pipeline.ingest(first) { self.image(first.pixels, width: 144, height: 800) }
        let result = try pipeline.ingest(changed) { self.image(changed.pixels, width: 144, height: 800) }
        XCTAssertTrue(result.strips.isEmpty)
        XCTAssertFalse(pipeline.hasStarted)
        XCTAssertNil(pipeline.diagnostics.matchingTopInset)
        XCTAssertNil(pipeline.diagnostics.matchingBottomInset)
        XCTAssertNil(pipeline.diagnostics.matchingFrameHeight)
        XCTAssertNil(pipeline.diagnostics.matchingRegionSource)
        XCTAssertNil(pipeline.diagnostics.fixedBandTop)
        XCTAssertNil(pipeline.diagnostics.fixedBandBottom)
    }

    func testOldSchemaOneDiagnosticsRemainUnknownInsteadOfZero() throws {
        var manifest = CaptureSessionManifest(configuration: .init())
        manifest.diagnostics = CaptureDiagnostics()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any])
        var diagnostics = try XCTUnwrap(json["diagnostics"] as? [String: Any])
        for key in ["matchingTopInset", "matchingBottomInset", "matchingFrameHeight", "matchingRegionSource", "fixedBandTop", "fixedBandBottom"] {
            diagnostics.removeValue(forKey: key)
        }
        json["diagnostics"] = diagnostics
        let decoded = try JSONDecoder().decode(CaptureSessionManifest.self,
            from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.schemaVersion, 1)
        let old = try XCTUnwrap(decoded.diagnostics)
        XCTAssertNil(old.matchingTopInset); XCTAssertNil(old.matchingBottomInset)
        XCTAssertNil(old.matchingFrameHeight); XCTAssertNil(old.matchingRegionSource)
        XCTAssertNil(old.fixedBandTop); XCTAssertNil(old.fixedBandBottom)
        XCTAssertNil(old.fixedBandIsApplicable)
        XCTAssertEqual(old.matchingRegionSourceLabel, "未记录")
    }

    func testWallpaperForegroundStartIsExemptFromFixedStructureGuard() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        for offset in [700, 663, 620] {
            let frame = try wallpaper(offset: offset)
            let result = try pipeline.ingest(frame) { self.image(frame.pixels, width: frame.width, height: frame.height) }
            XCTAssertNotEqual(result.status, .rejected)
        }
        XCTAssertTrue(pipeline.hasStarted)
        XCTAssertEqual(pipeline.diagnostics.matchingRegionSource, "foreground")
        XCTAssertNotNil(pipeline.diagnostics.matchingTopInset)
        XCTAssertNotNil(pipeline.diagnostics.matchingBottomInset)
        XCTAssertNil(pipeline.diagnostics.fixedBandTop)
        XCTAssertNil(pipeline.diagnostics.fixedBandBottom)
        XCTAssertEqual(pipeline.diagnostics.fixedBandIsApplicable, false)
    }

    private func assertHeaderCapture(width: Int, height: Int, upward: Bool, manual: Bool = false,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let fixture = HeaderFixture(width: width, height: height)
        let sourceOffsets = upward ? [6_000, 5_700, 5_380, 5_100, 4_700, 4_300, 4_000]
                                   : [4_000, 4_500, 4_820, 5_100, 5_500, 5_900, 6_200]
        let offsets = sourceOffsets.map { $0 * height / 2_556 }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try CaptureSessionRepository(rootURL: folder)
        var manifest = try repository.createSession(configuration: .init())
        let configuration = manual ? AlignmentConfiguration(topInset: fixture.top, bottomInset: fixture.bottom) : .init()
        let pipeline = CaptureFramePipeline(configuration: configuration, repository: repository, sessionID: manifest.id)
        let conversion = CIContext(options: [.cacheIntermediates: false])
        var firstPixels: [UInt8] = [], lastPixels: [UInt8] = []
        var acceptedDiagnostics: CaptureDiagnostics?
        for (index, offset) in offsets.enumerated() {
            let values = fixture.frame(offset: offset, pill: upward ? index > 0 : index == 0,
                                       arrow: index == 0, minute: 24 + index)
            if index == 0 { firstPixels = values }; lastPixels = values
            let source = image(values, width: width, height: height)
            let gray = try CaptureFrameConversion.grayFrame(CIImage(cgImage: source), context: conversion,
                                                            width: 144, height: height)
            let result = try pipeline.ingest(gray) { source }
            if index == 0 {
                XCTAssertNil(pipeline.diagnostics.matchingTopInset, file: file, line: line)
                XCTAssertNil(pipeline.diagnostics.fixedBandTop, file: file, line: line)
            } else {
                XCTAssertEqual(result.status, .advanced, "frame \(index), stage \(pipeline.diagnostics.lastStage)", file: file, line: line)
                XCTAssertEqual(result.strips.last?.placement, upward ? .prepend : .append, file: file, line: line)
            }
            manifest.provisionalFrame = pipeline.provisionalFrame
            if !result.strips.isEmpty {
                try repository.commit(result, maximumBodyHeight: 30_000, to: &manifest)
                pipeline.confirmCommit()
                if acceptedDiagnostics == nil { acceptedDiagnostics = pipeline.diagnostics }
            }
        }
        XCTAssertTrue(pipeline.hasStarted, file: file, line: line)
        let diagnostics = pipeline.diagnostics
        XCTAssertEqual(diagnostics.matchingFrameHeight, height, file: file, line: line)
        XCTAssertEqual(diagnostics.matchingRegionSource, manual ? "manual" : "wholePage", file: file, line: line)
        XCTAssertEqual(diagnostics.matchingTopInset, acceptedDiagnostics?.matchingTopInset, file: file, line: line)
        XCTAssertEqual(diagnostics.matchingBottomInset, acceptedDiagnostics?.matchingBottomInset, file: file, line: line)
        if manual {
            XCTAssertEqual(diagnostics.matchingTopInset, fixture.top, file: file, line: line)
            XCTAssertEqual(diagnostics.matchingBottomInset, fixture.bottom, file: file, line: line)
            XCTAssertNil(diagnostics.fixedBandTop, file: file, line: line)
            XCTAssertNil(diagnostics.fixedBandBottom, file: file, line: line)
            XCTAssertEqual(diagnostics.fixedBandIsApplicable, false, file: file, line: line)
        } else {
            let top = try XCTUnwrap(diagnostics.matchingTopInset), bottom = try XCTUnwrap(diagnostics.matchingBottomInset)
            XCTAssertGreaterThanOrEqual(top, try XCTUnwrap(diagnostics.fixedBandTop), file: file, line: line)
            XCTAssertGreaterThanOrEqual(bottom, try XCTUnwrap(diagnostics.fixedBandBottom), file: file, line: line)
            XCTAssertGreaterThanOrEqual(top, fixture.top, file: file, line: line)
        }
        // Once accepted, a rejected scene cannot overwrite the selected region
        // with either a failed candidate or nil.
        let unrelated = try GrayFrame(width: 144, height: height, pixels: [UInt8](repeating: 0, count: 144 * height))
        let rejected = try pipeline.ingest(unrelated) { self.image([UInt8](repeating: 0, count: width * height), width: width, height: height) }
        XCTAssertEqual(rejected.status, .rejected, file: file, line: line)
        XCTAssertEqual(pipeline.diagnostics.matchingTopInset, diagnostics.matchingTopInset, file: file, line: line)
        XCTAssertEqual(pipeline.diagnostics.fixedBandTop, diagnostics.fixedBandTop, file: file, line: line)
        manifest.diagnostics = pipeline.diagnostics
        manifest.finalizeCapture(reason: "已手动结束捕捉。", partial: false)
        try repository.saveManifest(manifest)
        XCTAssertEqual(try repository.loadSession(id: manifest.id).diagnostics, manifest.diagnostics, file: file, line: line)
        let exported = try CaptureImageRenderer(repository: repository).export(sessionID: manifest.id, format: .png)
        let actual = try XCTUnwrap(UIImage(contentsOfFile: exported.path)?.cgImage)
        let earliest = try XCTUnwrap(offsets.min()), latest = try XCTUnwrap(offsets.max())
        let body = fixture.documentRows(earliest..<(latest + fixture.bodyHeight))
        let headerSource = upward ? lastPixels : firstPixels
        let footerSource = upward ? firstPixels : lastPixels
        let expected = manual ? body : Array(headerSource.prefix(fixture.top * width)) + body + Array(footerSource.suffix(fixture.bottom * width))
        XCTAssertEqual(actual.width, width, file: file, line: line)
        XCTAssertEqual(actual.height, (manual ? fixture.bodyHeight : height) + latest - earliest, file: file, line: line)
        let output = pixels(actual)
        XCTAssertEqual(output.count, expected.count, file: file, line: line)
        if output != expected {
            let mismatch = zip(output, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? -1
            XCTFail("Independent source oracle differs at byte \(mismatch), row \(mismatch / width); fixed bars and every document pixel must occur exactly once", file: file, line: line)
        }
    }

    private func image(_ values: [UInt8], width: Int, height: Int) -> CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
            provider: CGDataProvider(data: Data(values) as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
    private let width = 144, height = 800, top = 70, bottom = 90

    private func wallpaper(offset: Int, seed: Int = 0) throws -> GrayFrame {
        var values = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var value = UInt8(50 + Int(hash(x: x / 4, y: y / 6, seed: seed)) % 160)
                if y < top { value = 226 }
                else if y >= height - bottom { value = 212 }
                else if let foreground = foregroundPixel(x: x, documentY: y - top + offset, seed: seed) { value = foreground }
                values[y * width + x] = value
            }
        }
        return try GrayFrame(width: width, height: height, pixels: values)
    }

    private func foregroundPixel(x: Int, documentY: Int, seed: Int) -> UInt8? {
        let block = documentY / 113, localY = documentY % 113
        let left = block % 2 == 0 ? 18 : 42, cardWidth = 84
        guard (10..<84).contains(localY), x >= left, x < left + cardWidth else { return nil }
        let localX = x - left
        guard (7..<(cardWidth - 7)).contains(localX), (18..<76).contains(localY) else { return 242 }
        let cell = hash(x: localX / 4, y: localY / 5, seed: block + seed * 17)
        return cell % 5 < 3 ? UInt8(20 + Int(cell) % 145) : 242
    }

    private func hash(x: Int, y: Int, seed: Int) -> UInt8 {
        var value = UInt64(x + 1) &* 0x9E3779B185EBCA87 ^ UInt64(y + 1) &* 0xC2B2AE3D27D4EB4F
        value ^= UInt64(seed + 1) &* 0x165667B19E3779F9
        value ^= value >> 30; value &*= 0xBF58476D1CE4E5B9; value ^= value >> 27
        return UInt8(truncatingIfNeeded: value)
    }

}

private struct HeaderFixture {
    let width: Int
    let height: Int
    var top: Int { 300 * height / 2_556 }
    var bottom: Int { height - 2_406 * height / 2_556 }
    var bodyHeight: Int { height - top - bottom }
    private static let background: UInt8 = 237

    func documentRows(_ rows: Range<Int>) -> [UInt8] {
        var pixels = [UInt8](repeating: Self.background, count: width * rows.count)
        for (row, y) in rows.enumerated() {
            let reduced = (0..<144).map { Self.documentPixel(x: $0, documentY: y * 2_556 / height) }
            for x in 0..<width { pixels[row * width + x] = reduced[x * 144 / width] }
        }
        return pixels
    }

    func frame(offset: Int, pill: Bool, arrow: Bool, minute: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: Self.background, count: width * height)
        let body = documentRows(offset..<(offset + bodyHeight))
        pixels.replaceSubrange((top * width)..<((height - bottom) * width), with: body)
        for y in 0..<height where y < top || y >= height - bottom {
            let sy = y * 2_556 / height
            for x in 0..<width {
                let sx = x * 144 / width
                var value = Self.background
                if y < top {
                    if sy < 162 {
                        if (66..<114).contains(sy), (14..<30).contains(sx), (sx + sy / 6 + minute) % 3 != 0 { value = 20 }
                        if (70..<110).contains(sy), (103..<134).contains(sx), (sx / 3 + sy / 5) % 4 != 0 { value = 20 }
                        if arrow, (78..<100).contains(sy), (33..<38).contains(sx) { value = 40 }
                        if pill, (49..<128).contains(sy), (38..<103).contains(sx) {
                            value = (80..<98).contains(sy) && (43..<48).contains(sx) ? 76 : 0
                        }
                    } else {
                        if (205..<255).contains(sy), (6..<11).contains(sx) { value = 30 }
                        if (200..<252).contains(sy), (56..<88).contains(sx), (sx / 2 + sy / 7) % 3 != 0 { value = 30 }
                        if (225..<235).contains(sy), (130..<137).contains(sx), sx % 3 == 0 { value = 30 }
                    }
                } else {
                    value = 247
                    if (2_440..<2_510).contains(sy), (18..<115).contains(sx) { value = 255 }
                    if (2_450..<2_500).contains(sy), ((4..<15).contains(sx) || (120..<131).contains(sx) || (133..<141).contains(sx)) { value = 60 }
                }
                pixels[y * width + x] = value
            }
        }
        return pixels
    }

    static func documentPixel(x: Int, documentY: Int) -> UInt8 {
        // 900-row repeating "message period" with per-period variation so the
        // content is not vertically periodic within one screen.
        let period = 1_000
        let block = documentY / period
        let row = documentY % period
        func hash(_ a: Int, _ b: Int) -> Int {
            var v = UInt64(bitPattern: Int64(a)) &* 0x9E3779B185EBCA87 ^ UInt64(bitPattern: Int64(b)) &* 0xC2B2AE3D27D4EB4F
            v ^= v >> 29; v &*= 0xBF58476D1CE4E5B9; v ^= v >> 32
            return Int(v & 0xFFFF)
        }
        // Message slots inside one period: (startRow, height, side, kind)
        let slots: [(Int, Int, Int, Int)] = [
            (40, 90, 0, 0), (170, 70, 1, 0), (280, 60, 1, 0), (380, 250, 0, 1),
            (680, 120, 1, 2), (840, 70, 0, 0)
        ]
        for (index, slot) in slots.enumerated() {
            let (start, slotHeight, side, kind) = slot
            // Vary each block a little so no two screens repeat exactly.
            let jitter = hash(block, index) % 23
            let s = start + jitter, e = s + slotHeight
            guard row >= s, row < e else { continue }
            let local = row - s
            // Avatar: 18 analysis px square with 2D texture.
            let avatarRange = side == 0 ? 4..<22 : 122..<140
            if avatarRange.contains(x), local < 18 {
                return UInt8(90 + hash(x / 3 + block * 7, local / 3 + index) % 120)
            }
            let bubbleRange = side == 0 ? 27..<(27 + 30 + hash(block, index + 50) % 60)
                                        : (118 - 30 - hash(block, index + 50) % 60)..<118
            guard bubbleRange.contains(x) else { return background }
            switch kind {
            case 1: // picture card: textured
                return UInt8(40 + hash(x / 2 + block, local / 2 + index * 3) % 170)
            case 2: // sticker: mostly white with dark strokes
                return hash(x / 2, local / 2 + block) % 7 == 0 ? 60 : 250
            default: // text bubble: white/green with glyph rows
                let bubble: UInt8 = side == 0 ? 255 : 205
                let textRow = local % 46
                if textRow >= 12, textRow < 34, x > bubbleRange.lowerBound + 4, x < bubbleRange.upperBound - 4 {
                    if hash(x / 2 + block * 3, textRow / 4 + index * 11 + local / 46) % 3 == 0 { return 40 }
                }
                return bubble
            }
        }
        return background
    }

}
