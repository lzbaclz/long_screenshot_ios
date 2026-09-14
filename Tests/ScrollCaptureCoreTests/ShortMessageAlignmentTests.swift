import XCTest
import CoreGraphics
import CoreText
@testable import ScrollCaptureCore

/// Public synthetic messages rendered at phone width before horizontal-only
/// reduction. No private conversations or application screenshots are used.
final class ShortMessageAlignmentTests: XCTestCase {
    private let width = 144
    private let height = 2_556
    private let top = 221
    private let bottom = 133

    func testUnevenShortChineseMessagesHaveUniqueOverlapAndAlignInBothDirections() throws {
        try verifyShortMessages(layout: .left, label: "narrow left bubbles")
    }

    func testUnevenShortChineseMessagesOnRightAlignInBothDirections() throws {
        try verifyShortMessages(layout: .right, label: "narrow right bubbles")
    }

    func testUnevenAlternatingShortChineseMessagesAlignInBothDirections() throws {
        try verifyShortMessages(layout: .alternating, label: "alternating narrow bubbles")
    }

    func testAlternatingShortMessagesWithSmallOverlapNoiseAlignBothDirections() throws {
        try verifyShortMessages(layout: .alternating, overlapNoise: true,
                                label: "alternating narrow bubbles with overlap noise")
    }

    func testSameWordsAndPositionsWithWiderAvatarSeparationControl() throws {
        // Only horizontal placement changes: same font, words, heights and avatar.
        // This control distinguishes weak horizontal support from word periodicity.
        try verifyShortMessages(layout: .wideControl, label: "wider avatar/bubble separation control")
    }

    func testPeriodicIdenticalShortMessagesRemainAmbiguous() throws {
        let canvas = try renderDocument(layout: .left, periodic: true)
        let a = try viewport(canvas, offset: 1_260)
        let b = try viewport(canvas, offset: 1_297)
        for (first, second) in [(a, b), (b, a)] {
            XCTAssertGreaterThan(exactOverlaps(first, second).count, 1)
            var stitcher = StreamStitcher(configuration: .init(topInset: top, bottomInset: bottom))
            var output: [UInt8] = []
            append(stitcher.ingest(first), from: first, to: &output)
            let trusted = output
            let decision = stitcher.ingest(second)
            XCTAssertEqual(decision.status, .rejected)
            XCTAssertEqual(decision.rejection, .ambiguous)
            append(decision, from: second, to: &output)
            XCTAssertTrue(output == trusted)
        }
    }

    func testSingleLongThinIndicatorCannotAuthorizeScrolling() throws {
        for columns in [51..<55, 140..<144] {
            func indicator(at start: Int) throws -> GrayFrame {
                var pixels = [UInt8](repeating: 244, count: width * height)
                for y in start..<(start + 1_200) {
                    for x in columns { pixels[y * width + x] = 61 }
                }
                return try GrayFrame(width: width, height: height, pixels: pixels)
            }
            let a = try indicator(at: 650)
            let b = try indicator(at: 613)
            for (first, second) in [(a, b), (b, a)] {
                var stitcher = StreamStitcher()
                var output: [UInt8] = []
                append(stitcher.ingest(first), from: first, to: &output)
                let decision = stitcher.ingest(second)
                XCTAssertEqual(decision.status, .rejected)
                append(decision, from: second, to: &output)
                XCTAssertTrue(output == first.pixels)
            }
        }
    }

    func testInternalOneTwoAndThreePixelNonperiodicIndicatorsRemainRejected() throws {
        for thickness in 1...3 {
            func indicator(at start: Int) throws -> GrayFrame {
                var pixels = [UInt8](repeating: 244, count: width * height)
                var state: UInt64 = 913
                for row in 0..<1_200 {
                    for column in 0..<thickness {
                        state = state &* 6_364_136_223_846_793_005 &+ 1
                        pixels[(start + row) * width + 61 + column] = UInt8(truncatingIfNeeded: state >> 32)
                    }
                }
                return try GrayFrame(width: width, height: height, pixels: pixels)
            }
            let a = try indicator(at: 650)
            let b = try indicator(at: 613)
            for (first, second) in [(a, b), (b, a)] {
                var stitcher = StreamStitcher()
                var output: [UInt8] = []
                append(stitcher.ingest(first), from: first, to: &output)
                let decision = stitcher.ingest(second)
                XCTAssertEqual(decision.status, .rejected, "Internal \(thickness)px nonperiodic indicator")
                append(decision, from: second, to: &output)
                XCTAssertTrue(output == first.pixels)
            }
        }
    }

    func testDetailCacheIsBoundedByReferenceHistoryAndReleasedOnReset() throws {
        let canvas = try renderDocument(layout: .alternating)
        for historyLimit in [1, 3, 8] {
            var stitcher = StreamStitcher(configuration: .init(topInset: top, bottomInset: bottom,
                                                               maxHistory: historyLimit))
            for index in 0..<12 {
                let decision = stitcher.ingest(try viewport(canvas, offset: 1_260 + index * 37))
                XCTAssertNotEqual(decision.status, .rejected, "history=\(historyLimit), step=\(index)")
                XCTAssertEqual(stitcher.referenceCount, min(historyLimit, index + 1))
                XCTAssertEqual(stitcher.cachedDetailRowCount, stitcher.referenceCount * height)
            }
            let retainedRows = stitcher.cachedDetailRowCount
            let blank = try GrayFrame(width: width, height: height,
                                      pixels: .init(repeating: 244, count: width * height))
            XCTAssertEqual(stitcher.ingest(blank).status, .rejected)
            XCTAssertEqual(stitcher.cachedDetailRowCount, retainedRows)
            stitcher.reset()
            XCTAssertEqual(stitcher.cachedDetailRowCount, 0)
        }
        print("DETAIL-CACHE rowStride=\(MemoryLayout<Range<Int>?>.stride) defaultBytes=\(3 * height * MemoryLayout<Range<Int>?>.stride) maximumBytes=\(8 * height * MemoryLayout<Range<Int>?>.stride)")
    }

    private func verifyShortMessages(layout: MessageLayout, overlapNoise: Bool = false, label: String,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let canvas = try renderDocument(layout: layout)
        let bodyHeight = height - top - bottom
        let origin = 1_260
        for displacement in [37, 180] {
            let earlier = try viewport(canvas, offset: origin)
            let later = try viewport(canvas, offset: origin + displacement)
            let truth = Array(canvas[(origin * width)..<((origin + displacement + bodyHeight) * width)])
            for (name, first, second, shift) in [("down", earlier, later, displacement),
                                               ("up", later, earlier, -displacement)] {
                let exactPositions = exactOverlaps(first, second)
                XCTAssertEqual(exactPositions, [shift], "\(label) \(name): no unique exact overlap", file: file, line: line)
                // The independent document establishes translation. Noise stays
                // inside existing overlap, away from either emitted head/tail.
                let observedSecond = overlapNoise ? try withOverlapNoise(second) : second
                var stitcher = StreamStitcher(configuration: .init(topInset: top, bottomInset: bottom))
                var output: [UInt8] = []
                append(stitcher.ingest(first), from: first, to: &output)
                let decision = stitcher.ingest(observedSecond)
                let span = maximumHorizontalDetailSpan(first)
                let detail = "\(label) \(name) \(shift): exact=\(exactPositions), maxDetailSpan=\(span), legacyWidthGate=\(width / 6), status=\(decision.status.rawValue), rejection=\(decision.rejection?.rawValue ?? "none")"
                XCTAssertEqual(decision.status, .advanced, detail, file: file, line: line)
                if decision.status == .advanced {
                    XCTAssertEqual(decision.contentOffset, shift, detail, file: file, line: line)
                    append(decision, from: observedSecond, to: &output)
                    XCTAssertTrue(output == truth, "\(detail): pixels differ from independent document", file: file, line: line)
                } else {
                    XCTAssertNil(decision.sourceRows, detail, file: file, line: line)
                }
            }
        }
    }

    private func withOverlapNoise(_ frame: GrayFrame) throws -> GrayFrame {
        var pixels = frame.pixels
        for y in (top + 600)..<(top + 620) {
            for x in 0..<width {
                let delta = (x + y) % 5 - 2
                pixels[y * width + x] = UInt8(clamping: Int(pixels[y * width + x]) + delta)
            }
        }
        return try GrayFrame(width: width, height: height, pixels: pixels)
    }

    /// Exhaustive full-pixel equality is independent of coarse/fine samples,
    /// confidence thresholds, inferred offsets and the local-detail gate.
    private func exactOverlaps(_ a: GrayFrame, _ b: GrayFrame) -> [Int] {
        let bodyHeight = height - top - bottom
        let maximumShift = bodyHeight - Int(ceil(Double(bodyHeight) * 0.4))
        return (-maximumShift...maximumShift).filter { shift in
            let overlap = bodyHeight - abs(shift)
            let aStart = (top + max(0, shift)) * width
            let bStart = (top + max(0, -shift)) * width
            return a.pixels[aStart..<(aStart + overlap * width)]
                .elementsEqual(b.pixels[bStart..<(bStart + overlap * width)])
        }
    }

    /// Measure all columns, giving an upper bound on any sparse sampler's span.
    /// A bound below width/6 proves no sampled information row can pass that gate.
    private func maximumHorizontalDetailSpan(_ frame: GrayFrame) -> Int {
        var maximum = 0
        let edge = max(1, width / 24)
        for y in top..<(height - bottom) {
            var first: Int?
            var last = 0
            for x in edge..<(width - edge) {
                let center = Int(frame.pixels[y * width + x])
                let gradient = max(abs(center - Int(frame.pixels[y * width + x - 1])),
                                   abs(center - Int(frame.pixels[y * width + x + 1])))
                if gradient >= 16 {
                    if first == nil { first = x }
                    last = x
                }
            }
            if let first { maximum = max(maximum, last - first) }
        }
        return maximum
    }

    private func append(_ decision: StitchDecision, from frame: GrayFrame, to output: inout [UInt8]) {
        guard let rows = decision.sourceRows else { return }
        let pixels = frame.pixels[(rows.lowerBound * width)..<(rows.upperBound * width)]
        if decision.placement == .prepend { output.insert(contentsOf: pixels, at: 0) }
        else { output.append(contentsOf: pixels) }
    }

    private func viewport(_ canvas: [UInt8], offset: Int) throws -> GrayFrame {
        let bodyHeight = height - top - bottom
        var pixels = [UInt8](repeating: 200, count: top * width)
        pixels.append(contentsOf: canvas[(offset * width)..<((offset + bodyHeight) * width)])
        pixels.append(contentsOf: repeatElement(UInt8(226), count: bottom * width))
        return try GrayFrame(width: width, height: height, pixels: pixels)
    }

    private enum MessageLayout { case left, right, alternating, wideControl }

    private func renderDocument(layout: MessageLayout, periodic: Bool = false) throws -> [UInt8] {
        let sourceWidth = 1_179
        let documentHeight = 6_000
        let context = try XCTUnwrap(CGContext(data: nil, width: sourceWidth, height: documentHeight,
            bitsPerComponent: 8, bytesPerRow: sourceWidth, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        context.setFillColor(gray: 0.95, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: sourceWidth, height: documentHeight))
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 36, nil)
        let attributes = [kCTFontAttributeName: font,
                          kCTForegroundColorAttributeName: CGColor(gray: 0.04, alpha: 1)] as CFDictionary
        let words = ["嗯", "好", "到了", "可以", "收到", "行", "在", "好的", "等等", "走吧", "谢谢"]
        var y = 73
        var index = 0
        while y < documentHeight - 100 {
            let word = periodic ? "好" : words[index % words.count]
            let attributed = try XCTUnwrap(CFAttributedStringCreate(nil, word as CFString, attributes))
            let textLine = CTLineCreateWithAttributedString(attributed)
            let textWidth = CTLineGetTypographicBounds(textLine, nil, nil, nil)
            let onRight = layout == .right || (layout == .alternating && index % 2 != 0)
            let avatarLeft = onRight ? sourceWidth - 66 : 18
            let bubbleLeft = onRight ? CGFloat(sourceWidth - 82) - textWidth - 36
                : CGFloat(layout == .wideControl ? 320 : 82)
            // Every message has the same 48px avatar; differences come from the
            // words and nonuniform vertical spacing, not random avatar identity.
            for row in 0..<6 {
                for column in 0..<6 {
                    context.setFillColor(gray: (row + column * 3) % 5 < 2 ? 0.16 : 0.71, alpha: 1)
                    context.fill(CGRect(x: avatarLeft + column * 8, y: documentHeight - y - (row + 1) * 8,
                                        width: 8, height: 8))
                }
            }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: CGFloat(bubbleLeft), y: CGFloat(documentHeight - y - 64),
                                width: textWidth + 36, height: 64))
            context.textPosition = CGPoint(x: bubbleLeft + 18, y: CGFloat(documentHeight - y - 44))
            CTLineDraw(textLine, context)
            y += periodic ? 163 : 124 + (index * 73 + index * index * 19) % 133
            index += 1
        }
        let source = try XCTUnwrap(context.makeImage())
        let analysis = try XCTUnwrap(CGContext(data: nil, width: width, height: documentHeight,
            bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        analysis.interpolationQuality = .high
        analysis.draw(source, in: CGRect(x: 0, y: 0, width: width, height: documentHeight))
        let bytes = try XCTUnwrap(analysis.data)
        return Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: width * documentHeight))
    }
}
