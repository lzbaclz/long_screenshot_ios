import XCTest
@testable import ScrollCaptureCore

final class ForegroundCandidateCoverageTests: XCTestCase {
    func testDistinctPeaksSupplementRatherThanReplaceOriginalRivals() {
        // Several shoulders around high-vote motifs precede a low-vote but
        // spatially distinct explanation. This tests proposal geometry alone.
        let votes = [301: 20, 302: 19, 300: 18, -201: 17, -202: 16, -200: 15,
                     91: 14, 92: 13, 90: 12, -41: 2]
        let actual = ForegroundMotionRegistration.proposedShifts(votes: votes, maximumShift: 500)
        var original: Set<Int> = []
        let highest = votes.keys.sorted { votes[$0]! > votes[$1]! }.prefix(8)
        for peak in highest { original.formUnion((peak - 1)...(peak + 1)) }
        XCTAssertTrue(original.isSubset(of: actual), "Do not discard previous one-pixel rivals")
        XCTAssertTrue(actual.contains(-41), "Repeated high-vote shoulders must leave room for a separate explanation")
        XCTAssertLessThanOrEqual(actual.count, 48)
        XCTAssertFalse(actual.contains(0))
    }

    func testProposalBudgetAndBoundsRemainFiniteWithManyTiedVotes() {
        let votes = Dictionary(uniqueKeysWithValues: (-700...700).filter { $0 != 0 }.map { ($0, 1) })
        let forward = ForegroundMotionRegistration.proposedShifts(votes: votes, maximumShift: 600)
        let reverse = ForegroundMotionRegistration.proposedShifts(votes: Dictionary(uniqueKeysWithValues: votes.reversed()), maximumShift: 600)
        XCTAssertEqual(forward, reverse)
        XCTAssertLessThanOrEqual(forward.count, 48)
        XCTAssertTrue(forward.allSatisfy { $0 != 0 && abs($0) <= 600 })
    }

    func testLowVoteRepeatedGlassPairMatchesItsTrueDisplacementBothWays() throws {
        let fixture = RepeatedGlassCaptureFixture(width: 144, height: 2_556)
        let first = try frame(fixture, offset: 2_197), second = try frame(fixture, offset: 2_095)
        for (a, b, expected) in [(first, second, -102), (second, first, 102)] {
            let result = ForegroundMotionRegistration.analyze(reference: a, current: b,
                configuration: .init(topInset: 265, bottomInset: 270, maxHistory: 1))
            XCTAssertEqual(result.status, .matched)
            XCTAssertEqual(result.displacement, expected)
            XCTAssertLessThanOrEqual(result.candidateCount, 48)
        }
    }

    func testOriginalGlassTrajectoriesPreserveEveryAdmittedRowWithShortHistory() throws {
        let fixture = RepeatedGlassCaptureFixture(width: 144, height: 2_556)
        let start = fixture.period * 4 + fixture.period / 2, step = fixture.period / 5
        let trajectories = [[start,start-step,start-2*step,start-3*step,start-2*step,start-step,start,start+step],
                            [start,start+step,start+2*step,start+3*step,start+2*step,start+step,start,start-step]]
        for positions in trajectories {
            let top = 265, bottom = 270
            var stitcher = StreamStitcher(configuration: .init(topInset: top, bottomInset: bottom, maxHistory: 1))
            var minimum = positions[0], maximum = positions[0]
            var actual: [UInt8] = [], expected: [UInt8] = []
            for (index, position) in positions.enumerated() {
                let source = try frame(fixture, offset: position)
                let result = stitcher.ingest(source)
                XCTAssertNotEqual(result.status, .rejected, "index \(index)")
                XCTAssertEqual(result.contentOffset, position - positions[0], "index \(index)")
                if let rows = result.sourceRows {
                    let bytes = source.pixels[(rows.lowerBound * fixture.width)..<(rows.upperBound * fixture.width)]
                    if result.placement == .prepend { actual.insert(contentsOf: bytes, at: 0) }
                    else { actual.append(contentsOf: bytes) }
                }
                let rows: Range<Int>?
                if index == 0 { rows = top..<(fixture.height - bottom) }
                else if position < minimum { rows = top..<(top + minimum - position) }
                else if position > maximum { rows = (fixture.height - bottom - position + maximum)..<(fixture.height - bottom) }
                else { rows = nil }
                if let rows {
                    let bytes = source.pixels[(rows.lowerBound * fixture.width)..<(rows.upperBound * fixture.width)]
                    if position < minimum { expected.insert(contentsOf: bytes, at: 0) }
                    else { expected.append(contentsOf: bytes) }
                }
                minimum = min(minimum, position); maximum = max(maximum, position)
                XCTAssertTrue(actual == expected, "Independent source-row oracle at index \(index)")
            }
            XCTAssertEqual(actual.count / fixture.width + top + bottom, 2_964)
        }
    }

    func testNearPeriodicForegroundStillRejectsAnAmbiguousMatch() throws {
        let fixture = LayeredForegroundRegistrationTests.Fixture(height: 1_920, periodic: true)
        let first = try fixture.frame(offset: 2_000)
        var second = try fixture.frame(offset: 1_963)
        var pixels = second.pixels
        // Small deterministic noise must not manufacture unique scroll proof.
        for y in stride(from: fixture.top, to: fixture.height - fixture.bottom, by: 17) {
            for x in 5..<(fixture.width - 5) { pixels[y * fixture.width + x] = UInt8(clamping: Int(pixels[y * fixture.width + x]) + (x + y) % 3 - 1) }
        }
        second = try GrayFrame(width: fixture.width, height: fixture.height, pixels: pixels)
        var stitcher = StreamStitcher(configuration: fixture.configuration)
        _ = stitcher.ingest(first)
        let result = stitcher.ingest(second)
        XCTAssertEqual(result.status, .rejected)
        XCTAssertNil(result.sourceRows)
        XCTAssertEqual(stitcher.contentOffset, 0)
    }

    private func frame(_ fixture: RepeatedGlassCaptureFixture, offset: Int) throws -> GrayFrame {
        try GrayFrame(width: fixture.width, height: fixture.height, pixels: fixture.frame(offset: offset))
    }
}
