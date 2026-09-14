import XCTest
@testable import ScrollCaptureCore

final class FixedRegionDetectorTests: XCTestCase {
    func testTexturedFixedBarsResolveExactBodyBoundary() throws {
        let result = FixedRegionDetector.resolve(reference: try frame(offset: 0, top: 18, bottom: 26),
                                                 current: try frame(offset: 31, top: 18, bottom: 26),
                                                 downwardDisplacement: 31)
        guard case .resolved(let insets) = result else { return XCTFail("Expected exact fixed bands") }
        XCTAssertEqual(insets.top, 18)
        XCTAssertEqual(insets.bottom, 26)
    }

    func testMovingEdgeRowsArePreservedWithoutFixedBars() throws {
        let result = FixedRegionDetector.resolve(reference: try frame(offset: 0), current: try frame(offset: 31),
                                                 downwardDisplacement: 31)
        guard case .resolved(let insets) = result else { return XCTFail("Expected uncropped frame") }
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.bottom, 0)
    }

    func testLegitimateWhiteDocumentPaddingIsNotSilentlyRemoved() throws {
        let result = FixedRegionDetector.resolve(reference: try frame(offset: 0, whiteUntil: 70),
                                                 current: try frame(offset: 31, whiteUntil: 70),
                                                 downwardDisplacement: 31)
        XCTAssertEqual(result, .ambiguous)
    }

    func testWhiteBodyPaddingAfterChromeIsAmbiguousInsteadOfOvercropped() throws {
        let result = FixedRegionDetector.resolve(reference: try frame(offset: 0, top: 18, whiteUntil: 70),
                                                 current: try frame(offset: 31, top: 18, whiteUntil: 70),
                                                 downwardDisplacement: 31)
        XCTAssertEqual(result, .ambiguous)
    }

    func testGeometryAndInvalidDisplacementAreRejected() throws {
        let original = try frame(offset: 0)
        XCTAssertEqual(FixedRegionDetector.resolve(reference: original, current: original, downwardDisplacement: 0), .ambiguous)
        XCTAssertEqual(FixedRegionDetector.resolve(reference: original, current: original, downwardDisplacement: 100), .ambiguous)
        XCTAssertEqual(FixedRegionDetector.resolve(reference: original, current: original, downwardDisplacement: Int.min), .ambiguous)
        XCTAssertTrue(FixedRegionDetector.candidates(reference: original, current: original, displacement: Int.min).isEmpty)
        XCTAssertEqual(FixedRegionDetector.resolve(reference: original, current: try frame(offset: 1, top: 1),
                                                   downwardDisplacement: 1), .ambiguous)
    }

    func testSlightlyChangingWhiteFooterIsNotMistakenForMovingContent() throws {
        let a = try frame(offset: 0, bottom: 40), b = try frame(offset: 31, bottom: 40)
        var first = a.pixels, current = b.pixels
        first.replaceSubrange((160 * 48)..<first.count, with: repeatElement(UInt8(248), count: 40 * 48))
        current.replaceSubrange((160 * 48)..<current.count, with: repeatElement(UInt8(248), count: 40 * 48))
        current.replaceSubrange((199 * 48)..<current.count, with: repeatElement(UInt8(250), count: 48))
        XCTAssertEqual(FixedRegionDetector.resolve(
            reference: try GrayFrame(width: 48, height: 200, pixels: first),
            current: try GrayFrame(width: 48, height: 200, pixels: current), downwardDisplacement: 31), .ambiguous)
    }

    func testReverseScrollFindsSameFixedRegions() throws {
        let lower = try frame(offset: 31, top: 18, bottom: 26)
        let upper = try frame(offset: 0, top: 18, bottom: 26)
        XCTAssertEqual(FixedRegionDetector.resolve(reference: lower, current: upper,
                                                   downwardDisplacement: -31),
                       FixedRegionDetector.resolve(reference: upper, current: lower,
                                                   downwardDisplacement: 31))
    }

    func testChangingClockAndWhiteMarginProduceReplayCandidatesWithoutPretendingExactBoundary() throws {
        let a = try frame(offset: 0, top: 18, bottom: 26)
        let b = try frame(offset: 31, top: 18, bottom: 26)
        var pixels = b.pixels
        // A small clock change at the outer edge must not veto all body evidence.
        for x in 4..<12 { pixels[2 * 48 + x] = 255 - pixels[2 * 48 + x] }
        let changed = try GrayFrame(width: b.width, height: b.height, pixels: pixels)
        let candidates = FixedRegionDetector.candidates(reference: a, current: changed, displacement: 31)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertEqual(candidates.first?.top, 18)
        XCTAssertEqual(candidates.first?.bottom, 26)
    }

    func testBoundaryNearSearchLimitUsesSupportingRowsInsideBody() throws {
        // Moving content begins just before the 30% boundary-search limit.
        // Supporting features beyond that limit are valid evidence, not crop.
        let first = try frame(offset: 0, whiteUntil: 78)
        let moved = try frame(offset: 31, whiteUntil: 78)
        let candidate = FixedRegionDetector.candidates(reference: first, current: moved, displacement: 31).first
        XCTAssertEqual(candidate?.top, 47)
        XCTAssertEqual(candidate?.bottom, 0)
    }

    func testUninformativeWhiteScreenCannotProposeMotionRegion() throws {
        let white = try GrayFrame(width: 48, height: 160, pixels: [UInt8](repeating: 250, count: 48 * 160))
        XCTAssertTrue(FixedRegionDetector.candidates(reference: white, current: white, displacement: 31).isEmpty)
    }

    private func frame(offset: Int, top: Int = 0, bottom: Int = 0, whiteUntil: Int = 0) throws -> GrayFrame {
        let width = 48, body = 160, height = top + body + bottom
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let row = y < top || y >= top + body ? 9_003 + y : y - top + offset
                var value = UInt64(row) &* 0x9E3779B185EBCA87 ^ UInt64(x) &* 0xC2B2AE3D27D4EB4F
                value ^= value >> 30; value &*= 0xBF58476D1CE4E5B9; value ^= value >> 27
                pixels[y * width + x] = row < whiteUntil ? 248 : UInt8(truncatingIfNeeded: value)
            }
        }
        return try GrayFrame(width: width, height: height, pixels: pixels)
    }
}
