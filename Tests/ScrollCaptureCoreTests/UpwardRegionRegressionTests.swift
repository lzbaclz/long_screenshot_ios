import XCTest
@testable import ScrollCaptureCore

final class UpwardRegionRegressionTests: XCTestCase {
    func testReversingTheSameFramePairPreservesCandidateSymmetry() throws {
        let first = try UpwardRegionFixture.frame(offset: 3_000)
        let earlier = try UpwardRegionFixture.frame(offset: 2_820, clock: 1)
        let forward = FixedRegionDetector.candidates(reference: earlier, current: first, displacement: 180)
        let backward = FixedRegionDetector.candidates(reference: first, current: earlier, displacement: -180)
        XCTAssertFalse(forward.isEmpty)
        XCTAssertEqual(forward, backward)
    }

    func testUpwardMotionBehindLargeBlankPhotoStillProvidesAUsableInterior() throws {
        try assertRecognizedInterior(bottom: 96, blankPhoto: true)
    }

    func testKeyboardSizedFixedBottomDoesNotVetoVerifiedUpwardBody() throws {
        try assertRecognizedInterior(bottom: 1_050, blankPhoto: false)
    }

    func testAChangingKeyboardKeyCannotPassRegionReplayAsScrolling() throws {
        let initial = try UpwardRegionFixture.frame(offset: 3_000, bottom: 1_050)
        var pixels = initial.pixels
        for y in (initial.height - 1_050 + 210)..<(initial.height - 1_050 + 310) {
            for x in 20..<32 { pixels[y * initial.width + x] = 120 }
        }
        let changed = try GrayFrame(width: initial.width, height: initial.height, pixels: pixels)
        for proposedOffset in [-180, -8, 8, 180] {
            let candidates = FixedRegionDetector.candidates(reference: initial, current: changed,
                                                              displacement: proposedOffset)
            for candidate in candidates {
                var replay = StreamStitcher(configuration: .init(topInset: candidate.top, bottomInset: candidate.bottom))
                _ = replay.ingest(initial)
                let result = replay.ingest(changed)
                XCTAssertNotEqual(result.status, .advanced,
                                  "A key highlight must not authorize offset \(proposedOffset) using \(candidate)")
            }
        }
    }

    private func assertRecognizedInterior(bottom: Int, blankPhoto: Bool,
                                          file: StaticString = #filePath, line: UInt = #line) throws {
        let initial = try UpwardRegionFixture.frame(offset: 3_000, bottom: bottom, blankPhoto: blankPhoto)
        let earlier = try UpwardRegionFixture.frame(offset: 2_820, bottom: bottom, blankPhoto: blankPhoto, clock: 1)
        var control = StreamStitcher(configuration: .init(topInset: 260, bottomInset: bottom))
        _ = control.ingest(initial)
        let trusted = control.ingest(earlier)
        XCTAssertEqual(trusted.status, .advanced, file: file, line: line)
        XCTAssertEqual(trusted.contentOffset, -180, file: file, line: line)
        let candidates = FixedRegionDetector.candidates(reference: initial, current: earlier, displacement: -180)
        XCTAssertFalse(candidates.isEmpty,
                       "The body has a verified overlap; missing outer-edge motion must not veto all interior regions",
                       file: file, line: line)
    }
}

private enum UpwardRegionFixture {
    static let width = 144, height = 2_556, top = 260
    static func frame(offset: Int, bottom: Int = 96, blankPhoto: Bool = false, clock: Int = 0) throws -> GrayFrame {
        var pixels = [UInt8](repeating: 248, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let documentY = y - top + offset
                var value: UInt8 = 248
                if y < top {
                    value = 242
                    if (180..<204).contains(y), (15..<130).contains(x), (x / 5 + y / 3) % 3 == 0 { value = 60 }
                    if (50..<68).contains(y), (8..<38).contains(x) { value = UInt8(30 + clock % 5 * 20) }
                } else if y >= height - bottom {
                    if bottom > 200 {
                        value = 224
                        let keyY = (y - (height - bottom)) % 170, keyX = x % 14
                        if keyY > 20, keyY < 145, keyX > 1, keyX < 12 { value = 250 }
                        if keyY > 67, keyY < 89, keyX > 4, keyX < 9 { value = 35 }
                    } else {
                        value = 236
                        if (height - 66..<height - 44).contains(y), (18..<125).contains(x), x % 13 < 5 { value = 80 }
                    }
                } else if !blankPhoto || !(3_950..<5_500).contains(documentY) {
                    // Sparse message glyphs with occasional textured picture cards;
                    // the large solid block models a loading image/blank photo area.
                    let row = documentY % 74, line = documentY / 74
                    if row < 13, (14..<132).contains(x), (x / 4 + line * 3) % 9 < 6 {
                        value = UInt8(25 + (line * 17 + x / 7) % 100)
                    }
                    if (25..<61).contains(row), (20..<122).contains(x), line % 3 == 0 {
                        value = UInt8(45 + (x * 11 + row * 3 + line * 13) % 145)
                    }
                }
                pixels[y * width + x] = value
            }
        }
        return try GrayFrame(width: width, height: height, pixels: pixels)
    }
}
