import XCTest
@testable import ScrollCaptureCore

final class SeamSelectorTests: XCTestCase {
    func testGlassCardsChooseQuietGapAcrossPhasesAndBothDirections() throws {
        for phase in [0.0, 0.7, 1.4, 2.2, 3.8, 5.0] {
            for direction in [SeamSelector.Direction.prepend, .append] {
                let pair = try GlassSeamFixture.pair(phase: phase, direction: direction)
                let result = SeamSelector.select(retained: pair.retained, incoming: pair.incoming, direction: direction)
                print("GLASS-SEAM phase=\(phase) direction=\(direction) shift=\(result.shift) reason=\(result.reason.rawValue) score=\(result.defaultScore)->\(result.selectedScore) MAE=\(result.defaultMetrics.pixelDifference)->\(result.selectedMetrics.pixelDifference)")
                XCTAssertEqual(result.reason, .selected, "phase=\(phase), direction=\(direction)")
                XCTAssertFalse(pair.cardRows.contains { $0.contains(result.selectedRow) }, "Selected seam must be outside independently defined cards")
                XCTAssertGreaterThan(result.shift, 240, "This scenario needs more than the original proposed 240-row window")
                XCTAssertLessThanOrEqual(result.shift, 480)
                XCTAssertLessThan(result.selectedScore, result.defaultScore)
                XCTAssertLessThanOrEqual(result.candidateCount, 481)
            }
        }
    }

    func testLightAndDarkGlassPalettesStillChooseUnoccupiedRows() throws {
        for (background, material) in [(55.0, 210.0), (140.0, 250.0), (175.0, 45.0)] {
            for direction in [SeamSelector.Direction.prepend, .append] {
                let pair = try GlassSeamFixture.pair(phase: 0.7, backgroundBase: background,
                                                     materialTone: material, direction: direction)
                let result = SeamSelector.select(retained: pair.retained, incoming: pair.incoming, direction: direction)
                XCTAssertEqual(result.reason, .selected)
                XCTAssertFalse(pair.cardRows.contains { $0.contains(result.selectedRow) })
            }
        }
    }

    func testQuantizationNoiseInTexturedDocumentDoesNotJustifyReplacement() throws {
        let pair = try GlassSeamFixture.pair()
        let noisy = try GrayFrame(width: pair.retained.width, height: pair.retained.height,
                                  pixels: pair.retained.pixels.map { UInt8(clamping: Int($0) + 1) })
        let result = SeamSelector.select(retained: pair.retained, incoming: noisy, direction: .prepend)
        XCTAssertEqual(result.shift, 0)
        XCTAssertEqual(result.reason, .insufficientGain)
    }

    func testFirstSafeGapRowAtExactWindowBoundaryIsIncluded() throws {
        let pair = try GlassSeamFixture.pair()
        let excluded = SeamSelector.select(retained: pair.retained, incoming: pair.incoming,
                                            direction: .prepend, maximumShift: 282)
        let included = SeamSelector.select(retained: pair.retained, incoming: pair.incoming,
                                            direction: .prepend, maximumShift: 283)
        XCTAssertEqual(excluded.reason, .noSafeCandidate)
        XCTAssertEqual(included.reason, .selected)
        XCTAssertEqual(included.shift, 283)
    }

    func testOpaqueIconHasLowerPixelErrorThanChosenGapButCannotAttractSeam() throws {
        let pair = try GlassSeamFixture.pair(phase: 0.7, startWithinCard: 75)
        let result = SeamSelector.select(retained: pair.retained, incoming: pair.incoming, direction: .prepend)
        XCTAssertEqual(result.reason, .selected)
        XCTAssertFalse(pair.cardRows.contains { $0.contains(result.selectedRow) })
        // Compare only opaque pixels from independent icon geometry: naive
        // error minimization would prefer them over the imperfect background.
        XCTAssertEqual(pair.retained.pixels[15], pair.incoming.pixels[15])
        XCTAssertGreaterThan(result.selectedMetrics.pixelDifference, 1)
        XCTAssertGreaterThan(result.defaultMetrics.structureOccupancy, result.selectedMetrics.structureOccupancy)
    }

    func testMatchedOrdinaryDocumentKeepsDefaultDespiteTexture() throws {
        let pair = try GlassSeamFixture.pair()
        for direction in [SeamSelector.Direction.prepend, .append] {
            let result = SeamSelector.select(retained: pair.retained, incoming: pair.retained, direction: direction)
            XCTAssertEqual(result.shift, 0)
            XCTAssertEqual(result.reason, .identicalOverlap)
            XCTAssertEqual(result.defaultRow, result.selectedRow)
        }
    }

    func testDifferentSmoothBackgroundKeepsAlreadyQuietDefault() throws {
        let a = try solid(80), b = try solid(120)
        let result = SeamSelector.select(retained: a, incoming: b, direction: .prepend)
        XCTAssertEqual(result.shift, 0)
        XCTAssertEqual(result.reason, .defaultAlreadyQuiet)
    }

    func testNoGapInsideSearchWindowFallsBackWithoutBorrowingOuterCaps() throws {
        let pair = try GlassSeamFixture.pair(cardHeight: 1_000)
        for direction in [SeamSelector.Direction.prepend, .append] {
            let oriented = direction == .prepend ? pair : try GlassSeamFixture.pair(cardHeight: 1_000, direction: direction)
            let result = SeamSelector.select(retained: oriented.retained, incoming: oriented.incoming, direction: direction)
            XCTAssertEqual(result.shift, 0)
            XCTAssertEqual(result.reason, .noSafeCandidate)
        }
    }

    func testLowGainKeepsDefaultEvenWithAvailableQuietRows() throws {
        let width = 144, height = 1_400
        var a = [UInt8](repeating: 10, count: width * height)
        var b = [UInt8](repeating: 250, count: width * height)
        for y in 0..<80 { a[y * width + 40] = 130; b[y * width + 40] = 130 }
        let result = SeamSelector.select(retained: try GrayFrame(width: width, height: height, pixels: a),
                                         incoming: try GrayFrame(width: width, height: height, pixels: b), direction: .prepend)
        XCTAssertEqual(result.shift, 0)
        XCTAssertEqual(result.reason, .insufficientGain)
    }

    func testSmallTrimCapacityAndOverlapFractionCannotReachFarGap() throws {
        let pair = try GlassSeamFixture.pair()
        let limited = SeamSelector.select(retained: pair.retained, incoming: pair.incoming,
                                           direction: .prepend, maximumShift: 240)
        XCTAssertEqual(limited.shift, 0)
        XCTAssertEqual(limited.reason, .noSafeCandidate)
        XCTAssertEqual(limited.candidateCount, 241)
        let short = try GlassSeamFixture.pair(height: 600)
        let fraction = SeamSelector.select(retained: short.retained, incoming: short.incoming, direction: .prepend)
        XCTAssertEqual(fraction.shift, 0)
        XCTAssertEqual(fraction.candidateCount, 211)
    }

    func testBoundedPatchUsesActualOverlapWithoutLoadingAllOverlapRows() throws {
        for direction in [SeamSelector.Direction.prepend, .append] {
            let full = try GlassSeamFixture.pair(direction: direction)
            let range = direction == .prepend ? 0..<486 : (full.retained.height - 486)..<full.retained.height
            func patch(_ frame: GrayFrame) throws -> GrayFrame {
                try GrayFrame(width: frame.width, height: range.count,
                              pixels: Array(frame.pixels[(range.lowerBound * frame.width)..<(range.upperBound * frame.width)]))
            }
            let bounded = SeamSelector.select(retained: try patch(full.retained), incoming: try patch(full.incoming),
                                               direction: direction, overlapLength: full.retained.height)
            let complete = SeamSelector.select(retained: full.retained, incoming: full.incoming, direction: direction)
            XCTAssertEqual(bounded.reason, .selected)
            XCTAssertEqual(bounded.shift, complete.shift)
            XCTAssertEqual(bounded.selectedScore, complete.selectedScore)
            XCTAssertEqual(bounded.candidateCount, 481)
        }
    }

    func testAlternatingTextureCannotAliasIntoAQuietGap() throws {
        let width = 144, height = 500
        let a = (0..<(width * height)).map { UInt8($0 % width % 2 == 0 ? 0 : 220) }
        let b = a.map { UInt8(clamping: Int($0) + 10) }
        let result = SeamSelector.select(retained: try GrayFrame(width: width, height: height, pixels: a),
                                         incoming: try GrayFrame(width: width, height: height, pixels: b), direction: .prepend)
        XCTAssertEqual(result.reason, .noSafeCandidate)
        XCTAssertEqual(result.shift, 0)
    }

    func testGeometryAndInvalidCapacityFailConservatively() throws {
        let base = try solid(100)
        let mismatched = try GrayFrame(width: 143, height: 1_400, pixels: .init(repeating: 110, count: 143 * 1_400))
        XCTAssertEqual(SeamSelector.select(retained: base, incoming: mismatched, direction: .prepend).reason, .invalidGeometry)
        XCTAssertEqual(SeamSelector.select(retained: base, incoming: base, direction: .append, overlapLength: 100).reason, .invalidGeometry)
        for maximum in [0, -1, Int.min] {
            XCTAssertEqual(SeamSelector.select(retained: base, incoming: base, direction: .prepend, maximumShift: maximum).shift, 0)
        }
        let small = try GrayFrame(width: 144, height: 12, pixels: .init(repeating: 100, count: 144 * 12))
        XCTAssertEqual(SeamSelector.select(retained: small, incoming: small, direction: .append).reason, .insufficientOverlap)
        let huge = SeamSelector.select(retained: base, incoming: base, direction: .prepend,
                                        overlapLength: Int.max, maximumShift: Int.max)
        XCTAssertEqual(huge.reason, .identicalOverlap)
    }

    private func solid(_ value: UInt8) throws -> GrayFrame {
        try GrayFrame(width: 144, height: 1_400, pixels: .init(repeating: value, count: 144 * 1_400))
    }
}
