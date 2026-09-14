import XCTest
@testable import ScrollCaptureCore

final class FixedStructureBandTests: XCTestCase {
    func testLaterRecordingIndicatorKeepsUpwardCandidatesOutsideHeader() throws {
        for distance in [300, 500, 1_000] {
            try assertChatReplay(displacement: -distance, firstPill: false, secondPill: true)
        }
    }

    func testRecordingIndicatorDisappearingAfterStartKeepsDownwardCandidatesOutsideHeader() throws {
        for distance in [300, 500, 1_000] {
            try assertChatReplay(displacement: distance, firstPill: true, secondPill: false)
        }
    }

    func testActuallyMovingTheOverlayBetweenFramesPreservesBothDirections() throws {
        // These are distinct pixels in four chronological pairs, not merely
        // two calls normalized into the same pair by the displacement sign.
        for displacement in [-500, 500] {
            for firstPill in [false, true] {
                try assertChatReplay(displacement: displacement, firstPill: firstPill, secondPill: !firstPill)
            }
        }
    }

    func testClockChangeAndLocationArrowDoNotBecomeUpwardMotionEvidence() throws {
        for displacement in [-300, -500] {
            let first = try FixedStructureChatFixture.frame(offset: 6_000, pill: false, arrow: true, minute: 24)
            let second = try FixedStructureChatFixture.frame(offset: 6_000 + displacement, pill: false, minute: 25)
            try assertReplay(first: first, second: second, displacement: displacement)
        }
    }

    func testFixedBandIsSymmetricDespiteAOneFrameOverlay() throws {
        let first = try FixedStructureChatFixture.frame(offset: 6_000, pill: false, arrow: true)
        let second = try FixedStructureChatFixture.frame(offset: 5_500, pill: true)
        let a = FixedRegionDetector.fixedStructureBand(reference: first, current: second)
        let b = FixedRegionDetector.fixedStructureBand(reference: second, current: first)
        XCTAssertEqual(a.top, b.top)
        XCTAssertEqual(a.bottom, b.bottom)
        XCTAssertGreaterThan(a.top, 114, "Shared navigation glyphs prove the transient row is inside the header")
        XCTAssertLessThanOrEqual(a.top, FixedStructureChatFixture.navBarEnd)
        XCTAssertGreaterThan(a.bottom, 0)
    }

    func testExactBoundaryInsideSharedStructureIsRejected() throws {
        let first = try texturedFrame(offset: 0)
        var pixels = try texturedFrame(offset: 31).pixels
        // The first changed row has an exact displaced match. The original
        // boundary algorithm resolved top=10, despite shared fixed rows 11...17.
        pixels.replaceSubrange((10 * 48)..<(11 * 48), with: first.pixels[(41 * 48)..<(42 * 48)])
        let second = try GrayFrame(width: 48, height: 204, pixels: pixels)
        XCTAssertEqual(FixedRegionDetector.fixedStructureBand(reference: first, current: second).top, 18)
        XCTAssertEqual(FixedRegionDetector.resolve(reference: first, current: second, downwardDisplacement: 31), .ambiguous)
        assertAllWholePageCandidatesOutsideBand(first: first, second: second, displacement: 31)
    }

    func testTwoPixelCandidatePaddingCannotReenterEitherFixedBand() throws {
        let first = try texturedFrame(offset: 0)
        var pixels = try texturedFrame(offset: 31).pixels
        for x in 4..<12 { pixels[2 * 48 + x] = 255 - pixels[2 * 48 + x] }
        let second = try GrayFrame(width: 48, height: 204, pixels: pixels)
        XCTAssertEqual(FixedRegionDetector.resolve(reference: first, current: second, downwardDisplacement: 31), .ambiguous)
        let band = FixedRegionDetector.fixedStructureBand(reference: first, current: second)
        XCTAssertEqual(band.top, 18)
        XCTAssertEqual(band.bottom, 26)
        let candidates = FixedRegionDetector.candidateSet(reference: first, current: second, displacement: 31)
        XCTAssertEqual(candidates.source, .wholePage)
        XCTAssertEqual(candidates.insets.first?.top, 18)
        XCTAssertEqual(candidates.insets.first?.bottom, 26)
        assertAllWholePageCandidatesOutsideBand(first: first, second: second, displacement: 31)
    }

    func testInvalidGeometryAndDisplacementsHaveNoCandidatesOrBand() throws {
        func solid(width: Int, height: Int) throws -> GrayFrame {
            try GrayFrame(width: width, height: height, pixels: .init(repeating: 237, count: width * height))
        }
        for (a, b) in [(try solid(width: 48, height: 80), try solid(width: 49, height: 80)),
                       (try solid(width: 48, height: 80), try solid(width: 48, height: 81)),
                       (try solid(width: 48, height: 39), try solid(width: 48, height: 39))] {
            let band = FixedRegionDetector.fixedStructureBand(reference: a, current: b)
            XCTAssertEqual(band.top, 0)
            XCTAssertEqual(band.bottom, 0)
            XCTAssertTrue(FixedRegionDetector.candidateSet(reference: a, current: b, displacement: 10).insets.isEmpty)
        }
        let narrow = try solid(width: 11, height: 80)
        XCTAssertEqual(FixedRegionDetector.fixedStructureBand(reference: narrow, current: narrow).top, 0)
        let frame = try texturedFrame(offset: 0)
        for displacement in [Int.min, Int.max, 0, frame.height - 12, -(frame.height - 12)] {
            XCTAssertTrue(FixedRegionDetector.candidateSet(reference: frame, current: frame, displacement: displacement).insets.isEmpty)
        }
    }

    func testLayeredCandidatesKeepTheirSourceAndBypassWholePageBand() throws {
        let fixture = LayeredForegroundRegistrationTests.Fixture(height: 2_556)
        let first = try fixture.frame(offset: 2_000), second = try fixture.frame(offset: 1_820)
        let band = FixedRegionDetector.fixedStructureBand(reference: first, current: second)
        for (a, b, displacement) in [(first, second, -180), (second, first, 180)] {
            // Negative candidates normalize to this orientation before registering.
            let registration = ForegroundMotionRegistration.analyze(reference: second, current: first)
            XCTAssertEqual(registration.status, .matched)
            let insets = try XCTUnwrap(registration.matchingInsets)
            let result = FixedRegionDetector.candidateSet(reference: a, current: b, displacement: displacement)
            XCTAssertEqual(result.source, .foreground)
            XCTAssertEqual(result.insets, [insets])
            XCTAssertTrue(insets.top < band.top || insets.bottom < band.bottom,
                          "The wallpaper must actually trigger the band to prove the exemption")
            XCTAssertEqual(FixedRegionDetector.candidates(reference: a, current: b, displacement: displacement), result.insets)
        }
        let wrongDisplacement = FixedRegionDetector.candidateSet(reference: first, current: second, displacement: -181)
        XCTAssertEqual(wrongDisplacement.source, .foreground)
        XCTAssertTrue(wrongDisplacement.insets.isEmpty)
    }

    func testRejectedLayeredSceneCannotFallBackToWholePageCandidates() throws {
        let a = LayeredForegroundRegistrationTests.Fixture(height: 1_920)
        let b = LayeredForegroundRegistrationTests.Fixture(height: 1_920, seed: 77_301)
        let first = try a.frame(offset: 2_000), second = try b.frame(offset: 1_820)
        let foreground = ForegroundMotionRegistration.analyze(reference: second, current: first)
        XCTAssertEqual(foreground.status, .rejected)
        let result = FixedRegionDetector.candidateSet(reference: first, current: second, displacement: -180)
        XCTAssertEqual(result.source, .foreground)
        XCTAssertTrue(result.insets.isEmpty)
    }

    private func assertChatReplay(displacement: Int, firstPill: Bool, secondPill: Bool,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let first = try FixedStructureChatFixture.frame(offset: 6_000, pill: firstPill, arrow: !firstPill)
        let second = try FixedStructureChatFixture.frame(offset: 6_000 + displacement, pill: secondPill, arrow: !secondPill)
        try assertReplay(first: first, second: second, displacement: displacement, file: file, line: line)
    }

    private func assertReplay(first: GrayFrame, second: GrayFrame, displacement: Int,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let candidates = FixedRegionDetector.candidateSet(reference: first, current: second, displacement: displacement)
        let insets = try XCTUnwrap(candidates.insets.first, file: file, line: line)
        XCTAssertGreaterThanOrEqual(insets.top, FixedStructureChatFixture.navBarEnd, file: file, line: line)
        XCTAssertGreaterThanOrEqual(insets.bottom, FixedStructureChatFixture.height - FixedStructureChatFixture.inputBarStart,
                                    file: file, line: line)
        assertAllWholePageCandidatesOutsideBand(first: first, second: second, displacement: displacement, file: file, line: line)
        var replay = StreamStitcher(configuration: .init(topInset: insets.top, bottomInset: insets.bottom))
        _ = replay.ingest(first)
        let decision = replay.ingest(second)
        XCTAssertEqual(decision.status, .advanced, "displacement=\(displacement), insets=\(insets)", file: file, line: line)
        XCTAssertEqual(decision.contentOffset, displacement, file: file, line: line)
    }

    private func assertAllWholePageCandidatesOutsideBand(first: GrayFrame, second: GrayFrame, displacement: Int,
                                                         file: StaticString = #filePath, line: UInt = #line) {
        let result = FixedRegionDetector.candidateSet(reference: first, current: second, displacement: displacement)
        guard result.source == .wholePage else { return }
        let band = FixedRegionDetector.fixedStructureBand(reference: first, current: second)
        XCTAssertFalse(result.insets.isEmpty, file: file, line: line)
        for insets in result.insets {
            XCTAssertGreaterThanOrEqual(insets.top, band.top, file: file, line: line)
            XCTAssertGreaterThanOrEqual(insets.bottom, band.bottom, file: file, line: line)
        }
    }

    private func texturedFrame(offset: Int) throws -> GrayFrame {
        let width = 48, height = 204, top = 18, bottom = 26
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let row = y < top || y >= height - bottom ? 9_003 + y : y - top + offset
                var value = UInt64(row) &* 0x9E3779B185EBCA87 ^ UInt64(x) &* 0xC2B2AE3D27D4EB4F
                value ^= value >> 30; value &*= 0xBF58476D1CE4E5B9; value ^= value >> 27
                pixels[y * width + x] = UInt8(truncatingIfNeeded: value)
            }
        }
        return try GrayFrame(width: width, height: height, pixels: pixels)
    }
}
