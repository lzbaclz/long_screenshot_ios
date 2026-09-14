import XCTest
@testable import ScrollCaptureCore

final class StreamStitcherTests: XCTestCase {
    func testFirstFrameAndStaticFramesDoNotDuplicate() throws {
        var stitcher = StreamStitcher()
        let first = try frame(offset: 0)
        let start = stitcher.ingest(first)
        XCTAssertEqual(start.status, .started)
        XCTAssertEqual(start.sourceRows, 0..<160)
        XCTAssertEqual(start.furthestOffset, 0)
        for _ in 0..<20 {
            let result = stitcher.ingest(first)
            XCTAssertEqual(result.status, .unchanged)
            XCTAssertNil(result.sourceRows)
        }
        XCTAssertEqual(stitcher.referenceCount, 1)
    }

    func testOddPixelScrollAppendsExactlyTheNewRows() throws {
        var stitcher = StreamStitcher()
        _ = stitcher.ingest(try frame(offset: 0))
        let result = stitcher.ingest(try frame(offset: 37))
        XCTAssertEqual(result.status, .advanced)
        XCTAssertEqual(result.contentOffset, 37)
        XCTAssertEqual(result.furthestOffset, 37)
        XCTAssertEqual(result.sourceRows, 123..<160)
        XCTAssertGreaterThan(result.confidence, 0.9)
    }

    func testCroppedStationaryHeaderAndFooterNeverEnterOutput() throws {
        var stitcher = StreamStitcher(configuration: .init(topInset: 20, bottomInset: 30))
        let start = stitcher.ingest(try frame(offset: 0, top: 20, bottom: 30))
        XCTAssertEqual(start.sourceRows, 20..<180)
        let result = stitcher.ingest(try frame(offset: 51, top: 20, bottom: 30))
        XCTAssertEqual(result.status, .advanced)
        XCTAssertEqual(result.contentOffset, 51)
        XCTAssertEqual(result.sourceRows, 129..<180)
    }

    func testBacktrackingAndReturnNeverAppendAlreadySeenRows() throws {
        var stitcher = StreamStitcher()
        var capturedRows = 0
        let positions = [0, 43, 87, 54, 20, 63, 100, 150]
        var decisions: [StitchDecision] = []
        for position in positions {
            let result = stitcher.ingest(try frame(offset: position))
            decisions.append(result)
            capturedRows += result.sourceRows?.count ?? 0
            XCTAssertEqual(result.contentOffset, position)
            XCTAssertLessThanOrEqual(stitcher.referenceCount, 3)
        }
        XCTAssertEqual(decisions.map(\.status), [.started, .advanced, .advanced, .backtracked,
                                                 .backtracked, .backtracked, .advanced, .advanced])
        XCTAssertNil(decisions[5].sourceRows)
        XCTAssertEqual(decisions[6].sourceRows, 147..<160)
        XCTAssertEqual(decisions[6].furthestOffset, 100)
        XCTAssertEqual(capturedRows, 160 + 150)
    }

    func testScrollingAboveStartPrependsOnlyUnseenHeadRows() throws {
        var stitcher = StreamStitcher()
        _ = stitcher.ingest(try frame(offset: 80))
        let back = stitcher.ingest(try frame(offset: 30))
        XCTAssertEqual(back.status, .advanced)
        XCTAssertEqual(back.contentOffset, -50)
        XCTAssertEqual(back.earliestOffset, -50)
        XCTAssertEqual(back.furthestOffset, 0)
        XCTAssertEqual(back.sourceRows, 0..<50)
        XCTAssertEqual(back.placement, .prepend)
        let forward = stitcher.ingest(try frame(offset: 100))
        XCTAssertEqual(forward.status, .advanced)
        XCTAssertEqual(forward.contentOffset, 20)
        XCTAssertEqual(forward.sourceRows, 140..<160)
        XCTAssertEqual(forward.placement, .append)
        XCTAssertEqual(forward.earliestOffset, -50)
    }

    func testOverlargeJumpRejectsThenRecoversFromTrustedFrame() throws {
        var stitcher = StreamStitcher()
        _ = stitcher.ingest(try frame(offset: 0))
        _ = stitcher.ingest(try frame(offset: 30))
        let gap = stitcher.ingest(try frame(offset: 260))
        XCTAssertEqual(gap.status, .rejected)
        XCTAssertEqual(gap.rejection, .insufficientOverlap)
        XCTAssertNil(gap.sourceRows)
        XCTAssertEqual(gap.contentOffset, 30)
        XCTAssertEqual(gap.furthestOffset, 30)
        XCTAssertEqual(stitcher.referenceCount, 2)

        let recovered = stitcher.ingest(try frame(offset: 75))
        XCTAssertEqual(recovered.status, .advanced)
        XCTAssertEqual(recovered.contentOffset, 75)
        XCTAssertEqual(recovered.sourceRows, 115..<160)
    }

    func testPeriodicContentRejectsCompetingOffsets() throws {
        var stitcher = StreamStitcher()
        _ = stitcher.ingest(try frame(offset: 0, period: 24))
        let result = stitcher.ingest(try frame(offset: 11, period: 24))
        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(result.rejection, .ambiguous)
        XCTAssertEqual(result.furthestOffset, 0)
        XCTAssertNil(result.sourceRows)
    }

    func testLowContrastGradientRejectsUncertainSingleRowPosition() throws {
        func gradient(offset: Int) throws -> GrayFrame {
            let pixels = (0..<160).flatMap { y in [UInt8](repeating: UInt8(40 + y + offset), count: 96) }
            return try GrayFrame(width: 96, height: 160, pixels: pixels)
        }
        var stitcher = StreamStitcher()
        _ = stitcher.ingest(try gradient(offset: 0))
        let result = stitcher.ingest(try gradient(offset: 7))
        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(result.rejection, .ambiguous)
        XCTAssertNil(result.sourceRows)
    }

    func testBlankScreenIsUnchangedAndNewUnrelatedSceneIsRejected() throws {
        var stitcher = StreamStitcher()
        let white = try GrayFrame(width: 96, height: 160, pixels: .init(repeating: 255, count: 96 * 160))
        _ = stitcher.ingest(white)
        XCTAssertEqual(stitcher.ingest(white).status, .unchanged)
        let newScene = stitcher.ingest(try frame(offset: 0))
        XCTAssertEqual(newScene.status, .rejected)
        XCTAssertNil(newScene.sourceRows)
    }

    func testSmallDynamicRegionDoesNotPreventCorrectScroll() throws {
        var stitcher = StreamStitcher()
        _ = stitcher.ingest(try frame(offset: 0))
        let clean = try frame(offset: 41)
        var pixels = clean.pixels
        for y in 50..<60 {
            for x in 0..<clean.width {
                pixels[y * clean.width + x] = texture(x: x + 713, y: y + 971)
            }
        }
        let noisy = try GrayFrame(width: clean.width, height: clean.height, pixels: pixels)
        let result = stitcher.ingest(noisy)
        XCTAssertEqual(result.status, .advanced)
        XCTAssertEqual(result.contentOffset, 41)
        XCTAssertEqual(result.sourceRows, 119..<160)
        XCTAssertGreaterThan(result.confidence, 0.65)
    }

    func testTextLikeScreensAlignDespiteWhiteSpace() throws {
        var stitcher = StreamStitcher()
        _ = stitcher.ingest(try textFrame(offset: 0))
        for position in [27, 70, 118, 96, 142] {
            let result = stitcher.ingest(try textFrame(offset: position))
            XCTAssertNotEqual(result.status, .rejected)
            XCTAssertEqual(result.contentOffset, position)
        }
        XCTAssertEqual(stitcher.furthestOffset, 142)
    }

    func testGeometryChangePreservesTrustedStateAndResetStartsFresh() throws {
        var stitcher = StreamStitcher()
        _ = stitcher.ingest(try frame(offset: 0))
        _ = stitcher.ingest(try frame(offset: 23))
        let changed = stitcher.ingest(try frame(offset: 42, width: 100))
        XCTAssertEqual(changed.rejection, .geometryChanged)
        XCTAssertEqual(changed.contentOffset, 23)
        XCTAssertNil(changed.sourceRows)
        stitcher.reset()
        XCTAssertEqual(stitcher.referenceCount, 0)
        XCTAssertEqual(stitcher.contentOffset, 0)
        XCTAssertEqual(stitcher.earliestOffset, 0)
        XCTAssertEqual(stitcher.furthestOffset, 0)
        XCTAssertEqual(stitcher.ingest(try frame(offset: 42, width: 100)).status, .started)
    }

    func testInvalidFramesAndConfigurationsFailSafely() throws {
        XCTAssertThrowsError(try GrayFrame(width: 0, height: 10, pixels: []))
        XCTAssertThrowsError(try GrayFrame(width: Int.max, height: 2, pixels: []))
        XCTAssertThrowsError(try GrayFrame(width: -10, height: -10, pixels: []))
        XCTAssertThrowsError(try GrayFrame(width: 10, height: 10, pixels: [0])) { error in
            XCTAssertEqual(error as? GrayFrame.ValidationError, .pixelCountMismatch(expected: 100, actual: 1))
        }
        let configurations: [AlignmentConfiguration] = [
            .init(topInset: -1), .init(topInset: Int.max), .init(bottomInset: 160),
            .init(minimumOverlap: .nan), .init(minimumOverlap: 0),
            .init(maximumMeanAbsoluteError: .infinity), .init(ambiguityMargin: 0), .init(maxHistory: 0),
            .init(maxHistory: 1_000)
        ]
        for configuration in configurations {
            var stitcher = StreamStitcher(configuration: configuration)
            let result = stitcher.ingest(try frame(offset: 0))
            XCTAssertEqual(result.rejection, .invalidConfiguration)
            XCTAssertNil(result.sourceRows)
            XCTAssertEqual(stitcher.referenceCount, 0)
        }
    }

    func testLongStreamRetainsBoundedReferencesAndExactOutputHeight() throws {
        var stitcher = StreamStitcher(configuration: .init(maxHistory: 2))
        var outputHeight = 0
        for position in stride(from: 0, through: 480, by: 24) {
            let result = stitcher.ingest(try frame(offset: position))
            XCTAssertEqual(result.contentOffset, position)
            XCTAssertNotEqual(result.status, .rejected)
            outputHeight += result.sourceRows?.count ?? 0
            XCTAssertLessThanOrEqual(stitcher.referenceCount, 2)
        }
        XCTAssertEqual(outputHeight, 160 + 480)
    }

    func testReconstructedCroppedOutputIsPixelExactAfterBacktracking() throws {
        var stitcher = StreamStitcher(configuration: .init(topInset: 17, bottomInset: 23))
        var output: [UInt8] = []
        for position in [0, 31, 65, 40, 72, 120, 89, 142] {
            let input = try frame(offset: position, top: 17, bottom: 23)
            let result = stitcher.ingest(input)
            XCTAssertNotEqual(result.status, .rejected)
            if let rows = result.sourceRows {
                let pixels = input.pixels[(rows.lowerBound * input.width)..<(rows.upperBound * input.width)]
                switch result.placement {
                case .append: output.append(contentsOf: pixels)
                case .prepend: output.insert(contentsOf: pixels, at: 0)
                }
            }
        }
        let expected = try frame(offset: 0, bodyHeight: 160 + 142)
        XCTAssertEqual(output, expected.pixels)
    }

    func testConfiguredMinimumOverlapIsRespected() throws {
        var boundary = StreamStitcher()
        _ = boundary.ingest(try frame(offset: 0))
        XCTAssertEqual(boundary.ingest(try frame(offset: 96)).contentOffset, 96)

        var beyondBoundary = StreamStitcher()
        _ = beyondBoundary.ingest(try frame(offset: 0))
        let result = beyondBoundary.ingest(try frame(offset: 100))
        XCTAssertEqual(result.status, .rejected)
        XCTAssertNil(result.sourceRows)
        XCTAssertEqual(beyondBoundary.furthestOffset, 0)
    }

    func testFullHeightAnalysisRetainsSingleRowPrecision() throws {
        // Downsample horizontally only in the capture layer to avoid scaling
        // one analysis row back to several original-resolution image rows.
        var stitcher = StreamStitcher()
        _ = stitcher.ingest(try frame(offset: 0, width: 144, bodyHeight: 2_532))
        let result = stitcher.ingest(try frame(offset: 379, width: 144, bodyHeight: 2_532))
        XCTAssertEqual(result.status, .advanced)
        XCTAssertEqual(result.contentOffset, 379)
        XCTAssertEqual(result.sourceRows, 2_153..<2_532)
        let next = stitcher.ingest(try frame(offset: 802, width: 144, bodyHeight: 2_532))
        XCTAssertEqual(next.contentOffset, 802)
        XCTAssertEqual(next.sourceRows, 2_109..<2_532)
    }

    private func frame(offset: Int, width: Int = 96, bodyHeight: Int = 160,
                       top: Int = 0, bottom: Int = 0, period: Int? = nil) throws -> GrayFrame {
        let height = bodyHeight + top + bottom
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                if y < top || y >= top + bodyHeight {
                    pixels[y * width + x] = texture(x: x, y: y + 8_000)
                } else {
                    let documentY = y - top + offset
                    pixels[y * width + x] = texture(x: x, y: period.map { documentY % $0 } ?? documentY)
                }
            }
        }
        return try GrayFrame(width: width, height: height, pixels: pixels)
    }

    private func textFrame(offset: Int) throws -> GrayFrame {
        let width = 144
        let height = 216
        var pixels = [UInt8](repeating: 248, count: width * height)
        for y in 0..<height {
            let documentY = y + offset
            let line = documentY / 13
            let lineY = documentY % 13
            for x in 8..<(width - 8) where lineY < 8 {
                let letterX = x % 7
                let letter = x / 7
                let glyph = texture(x: letter, y: line)
                if letterX < 5 && Int(glyph) % 9 != 0 && ((Int(glyph) + lineY * 3 + letterX) % 7 < 4) {
                    pixels[y * width + x] = UInt8(25 + Int(glyph) % 45)
                }
            }
        }
        return try GrayFrame(width: width, height: height, pixels: pixels)
    }

    private func texture(x: Int, y: Int) -> UInt8 {
        var value = UInt64(truncatingIfNeeded: y) &* 0x9E3779B185EBCA87
        value ^= UInt64(truncatingIfNeeded: x) &* 0xC2B2AE3D27D4EB4F
        value ^= value >> 30
        value &*= 0xBF58476D1CE4E5B9
        value ^= value >> 27
        return UInt8(truncatingIfNeeded: value)
    }
}
