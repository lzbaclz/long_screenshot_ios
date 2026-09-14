import XCTest
@testable import ScrollCaptureCore

/// The wallpaper stays in screen coordinates. Only opaque synthetic message
/// pixels move. No private messages or real screenshots enter these fixtures.
final class LayeredForegroundRegistrationTests: XCTestCase {
    func testFixedWallpaperAndMovingMessagesReconstructBothEndsAtNativeHeights() throws {
        for height in [1_920, 2_556] {
            let fixture = Fixture(height: height)
            var stitcher = StreamStitcher(configuration: fixture.configuration)
            var actual: [UInt8] = [], expected: [UInt8] = []
            let positions = [2_000, 1_963, 1_783, 1_783, 1_926, 2_143, 2_323, 2_106, 1_926, 1_709]
            var minimum = positions[0], maximum = positions[0], previous = positions[0]
            var times: [Double] = []
            for (index, position) in positions.enumerated() {
                let frame = try fixture.frame(offset: position)
                let clock = ContinuousClock.now
                let decision = stitcher.ingest(frame)
                let elapsed = clock.duration(to: .now).components
                if index > 0 { times.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15) }
                let expectedStatus: StitchDecision.Status = index == 0 ? .started
                    : (position < minimum || position > maximum ? .advanced : (position == previous ? .unchanged : .backtracked))
                XCTAssertEqual(decision.status, expectedStatus, "height=\(height), step=\(index), rejection=\(String(describing: decision.rejection))")
                XCTAssertEqual(decision.contentOffset, position - positions[0])
                if let rows = decision.sourceRows {
                    insert(Array(frame.pixels[(rows.lowerBound * fixture.width)..<(rows.upperBound * fixture.width)]),
                           atHead: decision.placement == .prepend, into: &actual)
                }
                let oracleRows: Range<Int>?
                let prepend = position < minimum
                if index == 0 { oracleRows = fixture.top..<(height - fixture.bottom) }
                else if prepend { oracleRows = fixture.top..<(fixture.top + minimum - position) }
                else if position > maximum { oracleRows = (height - fixture.bottom - position + maximum)..<(height - fixture.bottom) }
                else { oracleRows = nil }
                if let rows = oracleRows {
                    insert(Array(frame.pixels[(rows.lowerBound * fixture.width)..<(rows.upperBound * fixture.width)]),
                           atHead: prepend, into: &expected)
                }
                minimum = min(minimum, position); maximum = max(maximum, position); previous = position
                XCTAssertTrue(actual == expected, "Raw source-strip pixel oracle, height=\(height), step=\(index)")
                if actual.count == expected.count {
                    var differingForegroundPixels = 0
                    for row in minimum..<(maximum + fixture.bodyHeight) {
                        for x in 0..<fixture.width where fixture.opaque[row * fixture.width + x] {
                            if actual[(row - minimum) * fixture.width + x] != fixture.document[row * fixture.width + x] {
                                differingForegroundPixels += 1
                            }
                        }
                    }
                    XCTAssertEqual(differingForegroundPixels, 0, "Foreground content must not disappear or repeat")
                }
            }
            print("LAYERED-PROXY height=\(height) meanMS=\(times.reduce(0,+) / Double(times.count)) maxMS=\(times.max() ?? 0)")
        }
    }

    func testSmoothStationaryWallpaperCannotHideForegroundMovement() throws {
        let fixture = Fixture(height: 1_920, smoothWallpaper: true)
        for (a, b, shift) in [(2_000, 1_820, -180), (1_820, 2_000, 180)] {
            let first = try fixture.frame(offset: a), second = try fixture.frame(offset: b)
            let foreground = ForegroundMotionRegistration.analyze(reference: first, current: second,
                                                                   configuration: fixture.configuration)
            XCTAssertEqual(foreground.status, .matched, "Smooth areas plus localized detail still form a fixed layer")
            var stitcher = StreamStitcher(configuration: fixture.configuration)
            _ = stitcher.ingest(first)
            let decision = stitcher.ingest(second)
            XCTAssertEqual(decision.status, .advanced)
            XCTAssertEqual(decision.contentOffset, shift)
        }
    }

    func testForegroundRegionStaysInsideMovingSupportAndReplays() throws {
        let fixture = Fixture(height: 2_556)
        let first = try fixture.frame(offset: 2_000), second = try fixture.frame(offset: 1_820)
        let result = ForegroundMotionRegistration.analyze(reference: first, current: second)
        XCTAssertEqual(result.status, .matched)
        let region = try XCTUnwrap(result.matchingInsets)
        XCTAssertGreaterThanOrEqual(region.top, fixture.top)
        XCTAssertGreaterThanOrEqual(region.bottom, fixture.bottom)
        XCTAssertLessThanOrEqual(result.candidateCount, 24)
        XCTAssertLessThanOrEqual(result.supportCount, 2_048)
        var replay = StreamStitcher(configuration: .init(topInset: region.top, bottomInset: region.bottom))
        _ = replay.ingest(first)
        let decision = replay.ingest(second)
        XCTAssertEqual(decision.status, .advanced)
        XCTAssertEqual(decision.contentOffset, -180)
        XCTAssertEqual(replay.lastForegroundRegistration?.status, .matched)
        _ = replay.ingest(second)
        XCTAssertNil(replay.lastForegroundRegistration)
    }

    func testSmallForegroundNoiseAndRejectedScenePreserveTrustedContinuation() throws {
        let fixture = Fixture(height: 1_920)
        let other = Fixture(height: 1_920, seed: 77_301)
        let first = try fixture.frame(offset: 2_000)
        let clean = try fixture.frame(offset: 1_820)
        var pixels = clean.pixels
        for y in 900..<920 {
            for x in 0..<fixture.width {
                pixels[y * fixture.width + x] = UInt8(clamping: Int(pixels[y * fixture.width + x]) + (x + y) % 5 - 2)
            }
        }
        let noisy = try GrayFrame(width: fixture.width, height: fixture.height, pixels: pixels)
        var stitcher = StreamStitcher(configuration: fixture.configuration)
        _ = stitcher.ingest(first)
        XCTAssertEqual(stitcher.ingest(try other.frame(offset: 1_820)).status, .rejected)
        XCTAssertEqual(stitcher.referenceCount, 1)
        let recovered = stitcher.ingest(noisy)
        XCTAssertEqual(recovered.status, .advanced)
        XCTAssertEqual(recovered.contentOffset, -180)
        let rows = try XCTUnwrap(recovered.sourceRows)
        XCTAssertTrue(noisy.pixels[(rows.lowerBound * fixture.width)..<(rows.upperBound * fixture.width)]
            .elementsEqual(clean.pixels[(fixture.top * fixture.width)..<((fixture.top + 180) * fixture.width)]))
    }

    func testPublicRegistrationRejectsInvalidConfigurationBeforeArithmetic() throws {
        let frame = try Fixture(height: 1_920).frame(offset: 2_000)
        let configurations: [AlignmentConfiguration] = [
            .init(topInset: -1), .init(topInset: Int.max), .init(bottomInset: Int.min), .init(bottomInset: Int.max),
            .init(minimumOverlap: .nan), .init(minimumOverlap: 0),
            .init(maximumMeanAbsoluteError: .nan), .init(maximumMeanAbsoluteError: 0),
            .init(ambiguityMargin: .infinity), .init(ambiguityMargin: 0)
        ]
        for configuration in configurations {
            let result = ForegroundMotionRegistration.analyze(reference: frame, current: frame, configuration: configuration)
            XCTAssertEqual(result.status, .rejected)
            XCTAssertEqual(result.rejection, .invalidConfiguration)
        }
    }

    func testOlderLayeredRejectionCannotEraseNewerPixelExactTableOverlap() throws {
        // This reproduces the table/whole-canvas case where the newest view
        // overlaps by 111 rows, but the next older view is 138 rows away and
        // exceeds the 108-row search limit. The latter must not veto the former.
        let width = 96, bodyHeight = 180, origin = 1_710
        var document = [UInt8](repeating: 0, count: width * 4_000)
        for y in 0..<4_000 {
            for x in 0..<width {
                let background: UInt8 = y / 23 % 2 == 0 ? 245 : 225
                let code = Int(Fixture.hash(x: x / 7, y: y / 23, seed: 1_374))
                let ink = x >= 5 && x < width - 5 && y % 23 < 8 && x % 7 < 5
                    && code % 11 != 0 && (code + (y % 23) * 3 + x % 7) % 7 < 4
                document[y * width + x] = y % 23 == 22 || x % 31 == 30 ? 141
                    : (ink ? UInt8(20 + code % 55) : background)
            }
        }
        var stitcher = StreamStitcher()
        var output: [UInt8] = []
        for step in 0..<15 {
            let position = origin - step * 69
            let pixels = Array(document[(position * width)..<((position + bodyHeight) * width)])
            let frame = try GrayFrame(width: width, height: bodyHeight, pixels: pixels)
            let decision = stitcher.ingest(frame)
            XCTAssertEqual(decision.status, step == 0 ? .started : .advanced, "step=\(step)")
            XCTAssertEqual(decision.contentOffset, position - origin)
            if let rows = decision.sourceRows {
                insert(Array(pixels[(rows.lowerBound * width)..<(rows.upperBound * width)]),
                       atHead: decision.placement == .prepend, into: &output)
            }
            XCTAssertTrue(output.elementsEqual(document[(position * width)..<((origin + bodyHeight) * width)]),
                          "Pixel-exact document interval after step \(step)")
        }
    }

    func testSharedWallpaperDoesNotJoinDifferentMessages() throws {
        let fixture = Fixture(height: 1_920)
        let other = Fixture(height: 1_920, seed: 77_301)
        for (first, second) in [(try fixture.frame(offset: 2_000), try other.frame(offset: 1_820)),
                                (try other.frame(offset: 1_820), try fixture.frame(offset: 2_000))] {
            var stitcher = StreamStitcher(configuration: fixture.configuration)
            _ = stitcher.ingest(first)
            let decision = stitcher.ingest(second)
            XCTAssertEqual(decision.status, .rejected)
            XCTAssertNil(decision.sourceRows)
            XCTAssertEqual(stitcher.contentOffset, 0)
        }
    }

    func testPeriodicForegroundRemainsAmbiguousDespiteUniqueWallpaper() throws {
        let fixture = Fixture(height: 1_920, periodic: true)
        var stitcher = StreamStitcher(configuration: fixture.configuration)
        _ = stitcher.ingest(try fixture.frame(offset: 2_000))
        let decision = stitcher.ingest(try fixture.frame(offset: 1_963))
        XCTAssertEqual(decision.status, .rejected)
        XCTAssertNil(decision.sourceRows)
    }

    func testSingleAnimatedPatchAndThinIndicatorsCannotBecomeForegroundScrolling() throws {
        let fixture = Fixture(height: 1_920, empty: true)
        for patchWidth in [1, 2, 3, 30] {
            func frame(at top: Int) throws -> GrayFrame {
                var pixels = try fixture.frame(offset: 0).pixels
                let patchHeight = patchWidth <= 3 ? 1_100 : 70
                for y in 0..<patchHeight {
                    for x in 0..<patchWidth {
                        pixels[(top + y) * fixture.width + 61 + x] = Fixture.hash(x: x, y: y, seed: 93)
                    }
                }
                return try GrayFrame(width: fixture.width, height: fixture.height, pixels: pixels)
            }
            var stitcher = StreamStitcher(configuration: fixture.configuration)
            _ = stitcher.ingest(try frame(at: 500))
            let decision = stitcher.ingest(try frame(at: 463))
            XCTAssertTrue(decision.status == .rejected || decision.status == .unchanged)
            XCTAssertNil(decision.sourceRows)
        }
    }

    private func insert(_ pixels: [UInt8], atHead: Bool, into output: inout [UInt8]) {
        if atHead { output.insert(contentsOf: pixels, at: 0) }
        else { output.append(contentsOf: pixels) }
    }

    struct Fixture {
        let width = 144
        let height: Int
        let top = 120
        let bottom = 80
        var bodyHeight: Int { height - top - bottom }
        var configuration: AlignmentConfiguration { .init(topInset: top, bottomInset: bottom) }
        var document: [UInt8]
        var opaque: [Bool]
        let smoothWallpaper: Bool

        init(height: Int, seed: Int = 919, periodic: Bool = false, empty: Bool = false,
             smoothWallpaper: Bool = false) {
            self.height = height
            self.smoothWallpaper = smoothWallpaper
            document = .init(repeating: 0, count: 144 * 8_000)
            opaque = .init(repeating: false, count: 144 * 8_000)
            guard !empty else { return }
            var y = 51, index = 0
            while y < 7_500 {
                let message = periodic ? 0 : index
                let right = !periodic && index % 3 == 1
                let short = index % 4 == 0
                let photo = !periodic && index % 5 == 3
                let bubbleWidth = photo ? 91 : (short ? 17 : 72)
                let bubbleHeight = photo ? 280 : (short ? 61 : 94)
                let left = right ? 126 - bubbleWidth : 20
                let avatarX = right ? 130 : 5
                for row in 0..<52 {
                    for x in 0..<9 { put(x: avatarX + x, y: y + row, value: Self.hash(x: x, y: row / 3, seed: 117)) }
                }
                for row in 0..<bubbleHeight {
                    for x in 0..<bubbleWidth {
                        let value: UInt8
                        if photo { value = Self.hash(x: x / 2, y: (y + row) / 3, seed: seed) }
                        else {
                            let lineY = row % 31
                            let glyph = Self.hash(x: x / 5, y: message + row / 31, seed: seed)
                            let ink = x >= 3 && x < bubbleWidth - 3 && row >= 12 && row < bubbleHeight - 10
                                && lineY < 24 && (Int(glyph) + lineY / 3 + x % 5) % 7 < 3
                            value = ink ? UInt8(21 + Int(glyph) % 34) : (right ? 194 : 249)
                        }
                        put(x: left + x, y: y + row, value: value)
                    }
                }
                y += periodic ? 181 : bubbleHeight + 59 + (index * 37 + index * index * 13) % 101
                index += 1
            }
        }

        func frame(offset: Int) throws -> GrayFrame {
            var pixels = [UInt8](repeating: 0, count: width * height)
            for y in 0..<height {
                for x in 0..<width {
                    // A detailed, deterministic photograph-like fixed field.
                    let low = Int(Self.hash(x: x / 7, y: y / 23, seed: 47)) / 3
                    let fine = Int(Self.hash(x: x, y: y, seed: 31)) / 4
                    if smoothWallpaper {
                        // Mostly smooth color fields, with small scattered
                        // patches of detail rather than full-screen noise.
                        let local = y % 277 < 65 && x > 12 && x < 132
                            ? Int(Self.hash(x: x / 3, y: y / 2, seed: 84)) / 12 : 0
                        pixels[y * width + x] = UInt8(55 + x / 3 + y / 240 % 18 + local)
                    } else { pixels[y * width + x] = UInt8(57 + low + fine) }
                    if y >= top && y < height - bottom {
                        let source = (offset + y - top) * width + x
                        if opaque[source] { pixels[y * width + x] = document[source] }
                    }
                }
            }
            return try GrayFrame(width: width, height: height, pixels: pixels)
        }

        private mutating func put(x: Int, y: Int, value: UInt8) {
            document[y * width + x] = value
            opaque[y * width + x] = true
        }

        static func hash(x: Int, y: Int, seed: Int) -> UInt8 {
            var value = UInt64(y) &* 0x9E3779B185EBCA87
            value ^= UInt64(x) &* 0xC2B2AE3D27D4EB4F
            value ^= UInt64(seed) &* 0x165667B19E3779F9
            value ^= value >> 30; value &*= 0xBF58476D1CE4E5B9; value ^= value >> 27
            return UInt8(truncatingIfNeeded: value)
        }
    }
}
