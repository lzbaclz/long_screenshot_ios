import XCTest
@testable import ScrollCaptureCore

final class ForegroundEvidenceRangeTests: XCTestCase {
    private let region = AlignmentConfiguration(topInset: 100, bottomInset: 100)

    func testExplicitContextPreservesLayerEvidenceAfterMatchingROINarrows() throws {
        let first = try frame(offset: 0), second = try frame(offset: 31)
        let original = ForegroundMotionRegistration.analyze(reference: first, current: second)
        XCTAssertEqual(original.status, .matched)
        XCTAssertEqual(original.displacement, 31)
        let roiOnly = ForegroundMotionRegistration.analyze(reference: first, current: second, configuration: region)
        XCTAssertEqual(roiOnly.status, .notLayered, "Body lacks distributed stationary texture once outer context is excluded")
        let explicit = ForegroundMotionRegistration.analyze(reference: first, current: second,
                                                              configuration: region, stationaryEvidenceRows: 0..<600)
        XCTAssertEqual(explicit.status, .matched)
        XCTAssertEqual(explicit.displacement, 31)
        let insets = try XCTUnwrap(explicit.matchingInsets)
        XCTAssertGreaterThanOrEqual(insets.top, region.topInset)
        XCTAssertGreaterThanOrEqual(insets.bottom, region.bottomInset)
    }

    func testScopedStreamKeepsExactDocumentOffsetsAndOnlyEmitsROIRowsInBothDirections() throws {
        for sign in [-1, 1] {
            var stream = StreamStitcher(configuration: region, stationaryEvidenceRows: 0..<600)
            for index in 0..<6 {
                let position = 500 + index * sign * 31
                let result = stream.ingest(try frame(offset: position))
                XCTAssertEqual(result.status, index == 0 ? .started : .advanced)
                XCTAssertEqual(result.contentOffset, index * sign * 31)
                let rows = try XCTUnwrap(result.sourceRows)
                XCTAssertGreaterThanOrEqual(rows.lowerBound, 100)
                XCTAssertLessThanOrEqual(rows.upperBound, 500)
            }
        }
    }

    func testExplicitSameROIMatchesDefaultAndDoesNotReintroduceIgnoredContext() throws {
        let first = try frame(offset: 0), second = try frame(offset: 31)
        let implicit = ForegroundMotionRegistration.analyze(reference: first, current: second, configuration: region)
        let explicit = ForegroundMotionRegistration.analyze(reference: first, current: second,
                                                              configuration: region, stationaryEvidenceRows: 100..<500)
        XCTAssertEqual(implicit.status, .notLayered)
        XCTAssertEqual(explicit.status, implicit.status)
        XCTAssertEqual(explicit.displacement, implicit.displacement)
        XCTAssertEqual(explicit.candidateCount, implicit.candidateCount)
    }

    func testEveryPairMustReestablishStationaryEvidenceWithoutStickyState() throws {
        let first = try frame(offset: 0), second = try frame(offset: 31)
        XCTAssertEqual(ForegroundMotionRegistration.analyze(reference: first, current: second,
            configuration: region, stationaryEvidenceRows: 0..<600).status, .matched)
        let changedContext = try frame(offset: 62, contextSeed: 731)
        let next = ForegroundMotionRegistration.analyze(reference: second, current: changedContext,
                                                        configuration: region, stationaryEvidenceRows: 0..<600)
        XCTAssertEqual(next.status, .notLayered)
    }

    func testFixedUIAloneCannotSupplyBodyMotion() throws {
        let first = try frame(offset: 0, body: .blank)
        let movedUI = try frame(offset: 0, contextSeed: 731, body: .blank)
        var stream = StreamStitcher(configuration: region, stationaryEvidenceRows: 0..<600)
        _ = stream.ingest(first)
        let result = stream.ingest(movedUI)
        XCTAssertEqual(result.status, .unchanged)
        XCTAssertNil(result.sourceRows)
        XCTAssertEqual(result.contentOffset, 0)
    }

    func testFixedUIWithUniformBodyFadeCannotBecomeScrolling() throws {
        let first = try frame(offset: 0, body: .blank)
        let second = try frame(offset: 0, body: .fade)
        var stream = StreamStitcher(configuration: region, stationaryEvidenceRows: 0..<600)
        _ = stream.ingest(first)
        let result = stream.ingest(second)
        XCTAssertNotEqual(result.status, .advanced)
        XCTAssertNil(result.sourceRows)
        XCTAssertEqual(result.contentOffset, 0)
    }

    func testFixedUIAndOneAnimatedPatchWithoutWallpaperCannotBecomeScrolling() throws {
        let first = try frame(offset: 0, body: .patch)
        let second = try frame(offset: 31, body: .patch)
        var stream = StreamStitcher(configuration: region, stationaryEvidenceRows: 0..<600)
        _ = stream.ingest(first)
        let result = stream.ingest(second)
        XCTAssertNotEqual(result.status, .advanced)
        XCTAssertNil(result.sourceRows)
        XCTAssertEqual(result.contentOffset, 0)
    }

    func testInvalidContextRangesAreRejectedBeforeSampling() throws {
        let first = try frame(offset: 0), second = try frame(offset: 31)
        for rows in [-1..<600, 0..<601, 101..<500, 100..<499, 100..<100, Int.min..<Int.max] {
            let result = ForegroundMotionRegistration.analyze(reference: first, current: second,
                                                               configuration: region, stationaryEvidenceRows: rows)
            XCTAssertEqual(result.status, .rejected)
            XCTAssertEqual(result.rejection, .invalidConfiguration)
            var stream = StreamStitcher(configuration: region, stationaryEvidenceRows: rows)
            let firstDecision = stream.ingest(first)
            XCTAssertEqual(firstDecision.status, .rejected)
            XCTAssertEqual(firstDecision.rejection, .invalidConfiguration)
            XCTAssertNil(firstDecision.sourceRows)
        }
    }

    private enum Body { case messages, blank, fade, patch }

    private func frame(offset: Int, contextSeed: Int = 17, body: Body = .messages) throws -> GrayFrame {
        let width = 144, height = 600
        var pixels = [UInt8](repeating: 90, count: width * height)
        func hash(_ x: Int, _ y: Int, _ seed: Int) -> UInt8 {
            var value = UInt64(x) &* 0x9E3779B185EBCA87 ^ UInt64(y) &* 0xC2B2AE3D27D4EB4F
            value ^= UInt64(seed) &* 0x165667B19E3779F9
            value ^= value >> 30; value &*= 0xBF58476D1CE4E5B9; value ^= value >> 27
            return UInt8(truncatingIfNeeded: value)
        }
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                if y < 100 || y >= 500 {
                    pixels[i] = hash(x, y, contextSeed)
                } else {
                    switch body {
                    case .messages:
                        let documentY = y - 100 + offset
                        if documentY % 80 < 50, (12..<56).contains(x) || (86..<130).contains(x) {
                            pixels[i] = hash(x / 2, documentY / 2, 93)
                        }
                    case .blank: break
                    case .fade: pixels[i] = 105
                    case .patch:
                        if (260..<(260 + 25)).contains(y - offset), (50..<80).contains(x) {
                            pixels[i] = hash(x, y - offset, 93)
                        }
                    }
                }
            }
        }
        return try GrayFrame(width: width, height: height, pixels: pixels)
    }
}
