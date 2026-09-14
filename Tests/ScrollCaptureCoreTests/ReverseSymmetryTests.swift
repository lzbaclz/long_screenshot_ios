import XCTest
import CoreGraphics
import CoreText
@testable import ScrollCaptureCore

/// Same-frame reversal and vertical mirroring isolate matching direction from
/// scrolling trajectory and automatic crop detection. All images are synthetic;
/// the text cases rasterize a real font, not private conversations or screenshots.
final class ReverseSymmetryTests: XCTestCase {
    private let width = 144
    private let nativeHeight = 2_556

    func testNativeFirstMoveAtAndBeyondOverlapLimitInBothDirections() throws {
        let canvas = textureCanvas(height: 7_000)
        // 2556 - ceil(2556 * 0.4) = 1533. No direction may bypass this limit.
        for displacement in [37, 379, 901, 1_255, 1_533, 1_534] {
            try verifyPair(canvas: canvas, origin: 1_800, displacement: displacement,
                           expectAccepted: displacement <= 1_533,
                           label: "native texture shift=\(displacement)")
        }
    }

    func testRasterizedSparseChatAndLargeImageFirstMovesUnderFrameSwapAndMirror() throws {
        for style in [DocumentStyle.sparseChat, .largeImageChat] {
            let canvas = try renderedCanvas(style: style, height: 7_000)
            for displacement in [379, 901, 1_533] {
                try verifyPair(canvas: canvas, origin: 2_113, displacement: displacement,
                               expectAccepted: nil, label: "\(style) shift=\(displacement)")
            }
        }
    }

    func testKnownAsymmetricInputBarAndKeyboardInsetsKeepCoreDirectionSymmetric() throws {
        let canvas = try renderedCanvas(style: .sparseChat, height: 7_000)
        for bottom in [169, 867] {
            // The larger stationary region represents an open keyboard. This
            // test supplies correct insets; it does NOT exercise automatic arming.
            let configuration = AlignmentConfiguration(topInset: 181, bottomInset: bottom)
            for displacement in [37, 661] {
                try verifyPair(canvas: canvas, origin: 3_507, displacement: displacement,
                               configuration: configuration, expectAccepted: nil,
                               label: "known input/keyboard bottom=\(bottom) shift=\(displacement)")
            }
        }
    }

    func testVerticalMirrorDoesNotLoseDistributedDetailAtNativeOverlapBoundary() throws {
        let displacement = 1_533
        let origin = 1_800
        // A unique row-varying background determines translation, while six
        // horizontally textured rows provide well-separated local detail. The
        // document is generated independently of decisions. These positions
        // expose floor-sampling asymmetry without any ambiguous blank overlap.
        var canvas = textureCanvas(height: 7_000, constantWithinRow: true)
        for row in [107, 311, 355, 430, 666, 710] {
            let documentY = origin + displacement + row
            for x in 0..<width { canvas[documentY * width + x] = hash(x: x, y: documentY) }
        }
        try verifyPair(canvas: canvas, origin: origin, displacement: displacement,
                       expectAccepted: true, label: "distributed six-row detail at native boundary")
    }

    /// All four trials see the same two physical viewports: A→B, B→A,
    /// mirrored(A)→mirrored(B), and the reversed mirrored pair. Ground truth
    /// pixels come from the canvas interval, never from reported offsets.
    private func verifyPair(canvas: [UInt8], origin: Int, displacement: Int,
                            configuration: AlignmentConfiguration = .init(), expectAccepted: Bool?,
                            label: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let bodyHeight = nativeHeight - configuration.topInset - configuration.bottomInset
        let a = try viewport(canvas, offset: origin, configuration: configuration)
        let b = try viewport(canvas, offset: origin + displacement, configuration: configuration)
        let expected = Array(canvas[(origin * width)..<((origin + displacement + bodyHeight) * width)])
        var mirroredConfiguration = configuration
        mirroredConfiguration.topInset = configuration.bottomInset
        mirroredConfiguration.bottomInset = configuration.topInset
        let mirrorA = try mirror(a)
        let mirrorB = try mirror(b)
        let trials: [(String, GrayFrame, GrayFrame, Int, AlignmentConfiguration, [UInt8])] = [
            ("A→B", a, b, displacement, configuration, expected),
            ("B→A", b, a, -displacement, configuration, expected),
            ("mirror A→B", mirrorA, mirrorB, -displacement, mirroredConfiguration, reverseRows(expected)),
            ("mirror B→A", mirrorB, mirrorA, displacement, mirroredConfiguration, reverseRows(expected))
        ]
        var decisions: [StitchDecision] = []
        for (name, first, second, shift, config, truth) in trials {
            var stitcher = StreamStitcher(configuration: config)
            var output: [UInt8] = []
            apply(stitcher.ingest(first), frame: first, output: &output, file: file, line: line)
            let initialPixels = output
            let decision = stitcher.ingest(second)
            decisions.append(decision)
            let detail = "\(label) \(name): \(decision.status.rawValue), rejection=\(decision.rejection?.rawValue ?? "none"), offset=\(decision.contentOffset), confidence=\(decision.confidence)"
            apply(decision, frame: second, output: &output, file: file, line: line)
            if let expectAccepted {
                XCTAssertEqual(decision.status, expectAccepted ? .advanced : .rejected, detail, file: file, line: line)
            }
            if decision.status == .advanced {
                XCTAssertEqual(decision.contentOffset, shift, detail, file: file, line: line)
                XCTAssertEqual(decision.earliestOffset, min(0, shift), detail, file: file, line: line)
                XCTAssertEqual(decision.furthestOffset, max(0, shift), detail, file: file, line: line)
                XCTAssertEqual(decision.placement, shift < 0 ? .prepend : .append, detail, file: file, line: line)
                XCTAssertTrue(output == truth, "\(detail): assembled pixels differ from independent document", file: file, line: line)
            } else {
                XCTAssertEqual(decision.status, .rejected, detail, file: file, line: line)
                XCTAssertNil(decision.sourceRows, detail, file: file, line: line)
                XCTAssertTrue(output == initialPixels, "\(detail): rejection changed pixels", file: file, line: line)
            }
        }
        XCTAssertEqual(decisions[0].status, decisions[1].status, "\(label): frame-swap status asymmetry", file: file, line: line)
        XCTAssertEqual(decisions[0].rejection, decisions[1].rejection, "\(label): frame-swap rejection asymmetry", file: file, line: line)
        XCTAssertEqual(decisions[0].confidence, decisions[1].confidence, accuracy: 0.000_000_001,
                       "\(label): frame-swap score asymmetry", file: file, line: line)
        XCTAssertEqual(decisions[2].status, decisions[3].status, "\(label): mirrored frame-swap asymmetry", file: file, line: line)
        XCTAssertEqual(decisions[0].status, decisions[2].status, "\(label): vertical-mirror acceptance asymmetry", file: file, line: line)
        XCTAssertEqual(decisions[0].rejection, decisions[2].rejection, "\(label): vertical-mirror rejection asymmetry", file: file, line: line)
        XCTAssertEqual(decisions[0].confidence, decisions[2].confidence, accuracy: 0.000_000_001,
                       "\(label): vertical-mirror score asymmetry", file: file, line: line)
    }

    private func apply(_ decision: StitchDecision, frame: GrayFrame, output: inout [UInt8],
                       file: StaticString, line: UInt) {
        guard let rows = decision.sourceRows else { return }
        guard rows.lowerBound >= 0, rows.upperBound <= frame.height, !rows.isEmpty else {
            return XCTFail("Source rows outside viewport: \(rows)", file: file, line: line)
        }
        let pixels = frame.pixels[(rows.lowerBound * width)..<(rows.upperBound * width)]
        switch decision.placement {
        case .append: output.append(contentsOf: pixels)
        case .prepend: output.insert(contentsOf: pixels, at: 0)
        }
    }

    private func viewport(_ canvas: [UInt8], offset: Int,
                          configuration: AlignmentConfiguration) throws -> GrayFrame {
        let top = configuration.topInset
        let bottom = configuration.bottomInset
        let bodyHeight = nativeHeight - top - bottom
        var pixels = [UInt8](repeating: 244, count: width * nativeHeight)
        for y in 0..<top {
            for x in 0..<width { pixels[y * width + x] = hash(x: x / 3, y: 90_000 + y) }
        }
        pixels.replaceSubrange((top * width)..<((top + bodyHeight) * width),
                               with: canvas[(offset * width)..<((offset + bodyHeight) * width)])
        for y in (nativeHeight - bottom)..<nativeHeight {
            for x in 0..<width {
                pixels[y * width + x] = x % 12 == 0 || y % 99 < 4 ? 92 : 231
            }
        }
        return try GrayFrame(width: width, height: nativeHeight, pixels: pixels)
    }

    private func mirror(_ frame: GrayFrame) throws -> GrayFrame {
        try GrayFrame(width: frame.width, height: frame.height, pixels: reverseRows(frame.pixels))
    }

    private func reverseRows(_ pixels: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(pixels.count)
        for row in stride(from: pixels.count / width - 1, through: 0, by: -1) {
            result.append(contentsOf: pixels[(row * width)..<((row + 1) * width)])
        }
        return result
    }

    private func textureCanvas(height: Int, constantWithinRow: Bool = false) -> [UInt8] {
        (0..<height).flatMap { y in
            (0..<width).map { x in hash(x: constantWithinRow ? 0 : x, y: y) }
        }
    }

    private enum DocumentStyle { case sparseChat, largeImageChat }

    private func renderedCanvas(style: DocumentStyle, height: Int) throws -> [UInt8] {
        let sourceWidth = 1_152
        let source = try XCTUnwrap(CGContext(data: nil, width: sourceWidth, height: height,
            bitsPerComponent: 8, bytesPerRow: sourceWidth, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        source.setFillColor(gray: 0.965, alpha: 1)
        source.fill(CGRect(x: 0, y: 0, width: sourceWidth, height: height))
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 37, nil)
        let attributes = [kCTFontAttributeName: font,
                          kCTForegroundColorAttributeName: CGColor(gray: 0.08, alpha: 1)] as CFDictionary
        for (index, y) in stride(from: 67, to: height - 50, by: 163).enumerated() {
            let left = index % 3 == 0 ? 293 : 79
            source.setFillColor(gray: index % 3 == 0 ? 0.86 : 1, alpha: 1)
            source.fill(CGRect(x: left - 21, y: height - y - 63, width: 723, height: 79))
            let message = "第\(index)条：公开合成消息 · 明天上午九点见 \(index * 17 + 13)"
            let string = try XCTUnwrap(CFAttributedStringCreate(nil, message as CFString, attributes))
            let line = CTLineCreateWithAttributedString(string)
            source.textPosition = CGPoint(x: left, y: height - y - 38)
            CTLineDraw(line, source)
        }
        if style == .largeImageChat {
            // Large deterministic geometric images; these are not real photos.
            for imageTop in [331, 2_617, 4_703] {
                for row in stride(from: 0, to: 1_130, by: 19) {
                    for column in stride(from: 0, to: 945, by: 27) {
                        let value = CGFloat(hash(x: column / 27, y: imageTop + row / 19)) / 255
                        source.setFillColor(gray: value, alpha: 1)
                        source.fill(CGRect(x: 97 + column, y: height - imageTop - row - 19, width: 27, height: 19))
                    }
                }
            }
        }
        let original = try XCTUnwrap(source.makeImage())
        let analysis = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        analysis.interpolationQuality = .high
        analysis.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = try XCTUnwrap(analysis.data)
        return Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: width * height))
    }

    private func hash(x: Int, y: Int) -> UInt8 {
        var value = UInt64(y) &* 0x9E3779B185EBCA87
        value ^= UInt64(x) &* 0xC2B2AE3D27D4EB4F
        value ^= value >> 30
        value &*= 0xBF58476D1CE4E5B9
        value ^= value >> 27
        return UInt8(truncatingIfNeeded: value)
    }
}
