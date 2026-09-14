import XCTest
@testable import ScrollCaptureCore

/// The oracle is a document generated before ingesting any viewport. It does
/// not derive coverage, row order or expected pixels from stitcher decisions.
final class BidirectionalStitcherTests: XCTestCase {
    func testUpwardStartPrependsCroppedPixelsInNaturalReadingOrder() throws {
        try verifyDocument(positions: [600, 557, 508, 461, 408, 365, 310, 267], top: 17, bottom: 23)
    }

    func testRepeatedCrossingsExpandBothEndsWithoutDuplicates() throws {
        try verifyDocument(positions: [600, 551, 510, 560, 605, 654, 610, 566, 517, 468,
                                       514, 562, 608, 655, 704, 655, 610, 564, 520, 475, 427],
                           top: 11, bottom: 19)
    }

    func testSingleReferenceCanTraverseCapturedRangeAndExtendEvictedBoundaries() throws {
        let positions = Array(stride(from: 600, through: 1_000, by: 50))
            + Array(stride(from: 950, through: 250, by: -50))
            + Array(stride(from: 300, through: 1_200, by: 50))
            + Array(stride(from: 1_150, through: 150, by: -50))
        try verifyDocument(positions: positions, history: 1)
    }

    func testOnePixelAndMinimumOverlapBoundaryExtensionsAtEitherEnd() throws {
        try verifyDocument(positions: [601, 600, 504, 408, 504, 600, 601, 602, 698, 794, 793])
    }

    func testTextWhitespaceAndAnimatedEdgeInOverlapRemainPixelExact() throws {
        try verifyDocument(positions: [500, 463, 426, 463, 500, 537, 574, 537, 500, 463, 426, 389],
                           top: 13, bottom: 17, text: true, animatedOverlap: true)
    }

    func testSparseTextWithLargeWhitespaceAndAnimatedIndicatorMatchesBothDirections() throws {
        try verifyDocument(positions: [700, 663, 626, 589, 626, 663, 700, 737, 774, 811, 774, 737],
                           text: true, sparse: true, animatedOverlap: true)
    }

    func testMixedPhotosAndTextSurvivePausesLocalLoadingAndIndicatorAnimation() throws {
        try verifyDocument(positions: [700, 700, 700, 737, 737, 774, 774, 737, 700, 663, 663, 626],
                           mixedMedia: true, animatedOverlap: true, loadingPatch: true)
    }

    func testUnrelatedSparsePagesCannotUseSharedWhiteBackgroundAsOverlap() throws {
        let firstPage = Document(text: true, sparse: true)
        let otherPage = Document(seed: 99_301, text: true, sparse: true)
        var stitcher = StreamStitcher()
        let first = try firstPage.viewport(at: 700)
        var output: [UInt8] = []
        apply(stitcher.ingest(first), frame: first, output: &output)
        let other = try otherPage.viewport(at: 663, animationIndex: 1)
        let decision = stitcher.ingest(other)
        XCTAssertEqual(decision.status, .rejected)
        XCTAssertNil(decision.sourceRows)
        apply(decision, frame: other, output: &output)
        XCTAssertTrue(output == firstPage.pixels(in: 700..<860))
    }

    func testIsolatedMovingMarkerAndBlankOverlapCannotAuthorizeAJoin() throws {
        func markerFrame(y: Int, wide: Bool) throws -> GrayFrame {
            var pixels = [UInt8](repeating: 248, count: 96 * 160)
            let columns = wide ? 24..<72 : 92..<96
            for row in y..<(y + 8) {
                for column in columns { pixels[row * 96 + column] = UInt8(30 + row - y) }
            }
            return try GrayFrame(width: 96, height: 160, pixels: pixels)
        }
        for wide in [false, true] {
            var stitcher = StreamStitcher()
            let first = try markerFrame(y: 80, wide: wide)
            var output: [UInt8] = []
            apply(stitcher.ingest(first), frame: first, output: &output)
            let second = try markerFrame(y: 117, wide: wide)
            let decision = stitcher.ingest(second)
            XCTAssertEqual(decision.status, .rejected)
            apply(decision, frame: second, output: &output)
            XCTAssertTrue(output == first.pixels)
        }

        let document = Document()
        var first = try document.viewport(at: 600).pixels
        var second = try document.viewport(at: 1_000).pixels
        first.replaceSubrange((40 * 96)..<(160 * 96), with: repeatElement(UInt8(248), count: 120 * 96))
        second.replaceSubrange(0..<(120 * 96), with: repeatElement(UInt8(248), count: 120 * 96))
        var stitcher = StreamStitcher()
        let firstFrame = try GrayFrame(width: 96, height: 160, pixels: first)
        var output: [UInt8] = []
        apply(stitcher.ingest(firstFrame), frame: firstFrame, output: &output)
        let secondFrame = try GrayFrame(width: 96, height: 160, pixels: second)
        let decision = stitcher.ingest(secondFrame)
        XCTAssertEqual(decision.status, .rejected)
        apply(decision, frame: secondFrame, output: &output)
        XCTAssertTrue(output == first)
    }

    func testUpwardGapAndUnrelatedScenePreservePixelsAndBothBoundariesThenRecover() throws {
        let document = Document()
        var stitcher = StreamStitcher()
        var output: [UInt8] = []
        for offset in [600, 557, 514] {
            let frame = try document.viewport(at: offset)
            apply(stitcher.ingest(frame), frame: frame, output: &output)
        }
        let trusted = output
        let unrelated = Document(seed: 99_301)
        let blank = try GrayFrame(width: document.width, height: document.viewportHeight,
                                  pixels: .init(repeating: 248, count: document.width * document.viewportHeight))
        for frame in [try document.viewport(at: 210), try unrelated.viewport(at: 477), blank] {
            let decision = stitcher.ingest(frame)
            XCTAssertEqual(decision.status, .rejected)
            XCTAssertNil(decision.sourceRows)
            XCTAssertEqual(decision.placement, .append)
            XCTAssertEqual(decision.contentOffset, -86)
            XCTAssertEqual(decision.earliestOffset, -86)
            XCTAssertEqual(decision.furthestOffset, 0)
            apply(decision, frame: frame, output: &output)
            XCTAssertTrue(output == trusted, "A rejected frame must not alter already captured pixels")
        }
        let frame = try document.viewport(at: 477)
        let recovered = stitcher.ingest(frame)
        XCTAssertEqual(recovered.status, .advanced)
        XCTAssertEqual(recovered.placement, .prepend)
        apply(recovered, frame: frame, output: &output)
        XCTAssertTrue(output == document.pixels(in: 477..<(600 + document.viewportHeight)))
    }

    func testLostHistoryCannotInventContinuityAcrossAlreadyCapturedArea() throws {
        let document = Document()
        var stitcher = StreamStitcher(configuration: .init(maxHistory: 1))
        var output: [UInt8] = []
        for position in stride(from: 600, through: 200, by: -50) {
            let frame = try document.viewport(at: position)
            apply(stitcher.ingest(frame), frame: frame, output: &output)
        }
        let trusted = output
        // This view was captured, but no retained reference overlaps enough to
        // place it safely. Coverage alone must never authorize a guessed join.
        let decision = stitcher.ingest(try document.viewport(at: 600))
        XCTAssertEqual(decision.status, .rejected)
        XCTAssertNil(decision.sourceRows)
        XCTAssertEqual(decision.earliestOffset, -400)
        XCTAssertEqual(decision.furthestOffset, 0)
        XCTAssertEqual(stitcher.referenceCount, 1)
        XCTAssertTrue(output == trusted)
        XCTAssertTrue(output == document.pixels(in: 200..<(600 + document.viewportHeight)))
    }

    func testPeriodicAndBlankContentNeverInventEarlierRows() throws {
        let periodic = Document(period: 24)
        var stitcher = StreamStitcher()
        var output: [UInt8] = []
        let first = try periodic.viewport(at: 600)
        apply(stitcher.ingest(first), frame: first, output: &output)
        let shifted = try periodic.viewport(at: 589)
        let result = stitcher.ingest(shifted)
        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(result.rejection, .ambiguous)
        apply(result, frame: shifted, output: &output)
        XCTAssertTrue(output == periodic.pixels(in: 600..<760))
        XCTAssertEqual(stitcher.earliestOffset, 0)

        let blank = try GrayFrame(width: 96, height: 160, pixels: .init(repeating: 248, count: 96 * 160))
        stitcher.reset()
        output.removeAll()
        apply(stitcher.ingest(blank), frame: blank, output: &output)
        for _ in 0..<5 {
            let unchanged = stitcher.ingest(blank)
            XCTAssertEqual(unchanged.status, .unchanged)
            apply(unchanged, frame: blank, output: &output)
        }
        XCTAssertTrue(output == blank.pixels)
        XCTAssertEqual(stitcher.earliestOffset, 0)
        XCTAssertEqual(stitcher.furthestOffset, 0)
    }

    func testResetDiscardsNegativeCoverageAndStartsWholeRegion() throws {
        let document = Document()
        var stitcher = StreamStitcher(configuration: .init(topInset: 17, bottomInset: 23))
        _ = stitcher.ingest(try document.viewport(at: 600, top: 17, bottom: 23))
        _ = stitcher.ingest(try document.viewport(at: 557, top: 17, bottom: 23))
        XCTAssertEqual(stitcher.earliestOffset, -43)
        stitcher.reset()
        XCTAssertEqual(stitcher.earliestOffset, 0)
        XCTAssertEqual(stitcher.furthestOffset, 0)
        let frame = try document.viewport(at: 1_000, top: 17, bottom: 23)
        let decision = stitcher.ingest(frame)
        XCTAssertEqual(decision.status, .started)
        XCTAssertEqual(decision.placement, .append)
        var output: [UInt8] = []
        apply(decision, frame: frame, output: &output)
        XCTAssertTrue(output == document.pixels(in: 1_000..<1_160))
    }

    private func verifyDocument(positions: [Int], top: Int = 0, bottom: Int = 0,
                                history: Int = 3, text: Bool = false, sparse: Bool = false,
                                mixedMedia: Bool = false, animatedOverlap: Bool = false, loadingPatch: Bool = false,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let document = Document(text: text, sparse: sparse, mixedMedia: mixedMedia)
        let first = try XCTUnwrap(positions.first, file: file, line: line)
        var minimum = first
        var maximum = first
        var previous = first
        var stitcher = StreamStitcher(configuration: .init(topInset: top, bottomInset: bottom, maxHistory: history))
        var output: [UInt8] = []
        for (index, position) in positions.enumerated() {
            let frame = try document.viewport(at: position, top: top, bottom: bottom,
                                              animationIndex: animatedOverlap && index > 0 ? index : nil,
                                              loadingPatch: loadingPatch)
            let extendsHead = position < minimum
            let extendsTail = position > maximum
            let expectedStatus: StitchDecision.Status = index == 0 ? .started
                : (extendsHead || extendsTail ? .advanced : (position == previous ? .unchanged : .backtracked))
            let decision = stitcher.ingest(frame)
            XCTAssertEqual(decision.status, expectedStatus, "step \(index) at \(position)", file: file, line: line)
            XCTAssertEqual(decision.placement, extendsHead ? .prepend : .append, file: file, line: line)
            if !extendsHead && !extendsTail && index != 0 {
                XCTAssertNil(decision.sourceRows, file: file, line: line)
            }
            minimum = min(minimum, position)
            maximum = max(maximum, position)
            XCTAssertEqual(decision.contentOffset, position - first, file: file, line: line)
            XCTAssertEqual(decision.earliestOffset, minimum - first, file: file, line: line)
            XCTAssertEqual(decision.furthestOffset, maximum - first, file: file, line: line)
            XCTAssertLessThanOrEqual(stitcher.referenceCount, history, file: file, line: line)
            apply(decision, frame: frame, output: &output, file: file, line: line)
            let expected = document.pixels(in: minimum..<(maximum + document.viewportHeight))
            XCTAssertEqual(output.count, expected.count, file: file, line: line)
            XCTAssertTrue(output == expected, "Pixels/order must match independent document after step \(index)",
                          file: file, line: line)
            previous = position
        }
    }

    private func apply(_ decision: StitchDecision, frame: GrayFrame, output: inout [UInt8],
                       file: StaticString = #filePath, line: UInt = #line) {
        guard let rows = decision.sourceRows else { return }
        guard rows.lowerBound >= 0, rows.upperBound <= frame.height, !rows.isEmpty else {
            XCTFail("Invalid source rows \(rows)", file: file, line: line)
            return
        }
        let pixels = frame.pixels[(rows.lowerBound * frame.width)..<(rows.upperBound * frame.width)]
        switch decision.placement {
        case .append: output.append(contentsOf: pixels)
        case .prepend: output.insert(contentsOf: pixels, at: 0)
        }
    }

    private struct Document {
        let width = 96
        let viewportHeight = 160
        let canvas: [UInt8]

        init(seed: Int = 773, period: Int? = nil, text: Bool = false, sparse: Bool = false,
             mixedMedia: Bool = false) {
            var pixels: [UInt8] = []
            pixels.reserveCapacity(96 * 1_600)
            for y in 0..<1_600 {
                for x in 0..<96 {
                    let sourceY = period.map { y % $0 } ?? y
                    let usesText = text || (mixedMedia && y % 113 >= 67)
                    let lineHeight = sparse ? 43 : 13
                    let lineY = sourceY % lineHeight
                    let value = Self.hash(x: usesText ? x / 7 : x, y: usesText ? sourceY / lineHeight : sourceY, seed: seed)
                    let ink = x >= 8 && x < (sparse ? 63 : 88) && x % 7 < 5 && lineY < 8
                        && (Int(value) + lineY * 3 + x % 7) % 7 < 4
                    pixels.append(usesText ? (ink ? 20 + value % 45 : 248) : value)
                }
            }
            canvas = pixels
        }

        func pixels(in rows: Range<Int>) -> [UInt8] {
            Array(canvas[(rows.lowerBound * width)..<(rows.upperBound * width)])
        }

        func viewport(at offset: Int, top: Int = 0, bottom: Int = 0,
                      animationIndex: Int? = nil, loadingPatch: Bool = false) throws -> GrayFrame {
            var pixels = [UInt8](repeating: 19, count: width * top)
            pixels.append(contentsOf: self.pixels(in: offset..<(offset + viewportHeight)))
            pixels.append(contentsOf: [UInt8](repeating: 43, count: width * bottom))
            if let animationIndex {
                // A narrow indicator moves inside the overlap. Newly emitted
                // head/tail strips remain independently comparable to the canvas.
                let start = 70 + animationIndex % 9
                for y in start..<(start + 12) {
                    for x in (width - 4)..<width {
                        pixels[(top + y) * width + x] = UInt8(30 + animationIndex % 20)
                    }
                }
                if loadingPatch {
                    for y in 80..<88 {
                        for x in 24..<48 {
                            pixels[(top + y) * width + x] = UInt8(110 + animationIndex % 40)
                        }
                    }
                }
            }
            return try GrayFrame(width: width, height: top + viewportHeight + bottom, pixels: pixels)
        }

        private static func hash(x: Int, y: Int, seed: Int) -> UInt8 {
            var value = UInt64(y) &* 0x9E3779B185EBCA87
            value ^= UInt64(x) &* 0xC2B2AE3D27D4EB4F
            value ^= UInt64(seed) &* 0x165667B19E3779F9
            value ^= value >> 30
            value &*= 0xBF58476D1CE4E5B9
            value ^= value >> 27
            return UInt8(truncatingIfNeeded: value)
        }
    }
}
