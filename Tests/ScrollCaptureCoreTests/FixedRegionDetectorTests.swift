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
