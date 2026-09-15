import XCTest
@testable import ScrollCaptureCore

final class WeakGlassSeamTests: XCTestCase {
    func testNearBlackLowContrastGlassAcrossPhasesAndDirectionsNeverAttractsAppliedSeam() throws {
        var selected = 0
        for phase in [0.0, 0.7, 1.4, 2.2, 3.8, 5.0] {
            for direction in [SeamSelector.Direction.prepend, .append] {
                let pair = try weakPair(phase: phase, direction: direction)
                let result = SeamSelector.select(retained: pair.retained, incoming: pair.incoming, direction: direction)
                print("WEAK-GLASS phase=\(phase) direction=\(direction) shift=\(result.shift) reason=\(result.reason) MAE=\(result.defaultMetrics.pixelDifference)->\(result.selectedMetrics.pixelDifference)")
                if result.shift > 0 {
                    selected += 1
                    XCTAssertFalse(pair.cardRows.contains { $0.contains(result.selectedRow) })
                } else {
                    XCTAssertEqual(result.reason, .insufficientGain)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(selected, 6)
    }

    func testInversionPreservesWeakStructureDecisionWithoutBrightnessAssumptions() throws {
        for phase in [1.4, 2.2, 5.0] {
            let pair = try weakPair(phase: phase)
            let regular = SeamSelector.select(retained: pair.retained, incoming: pair.incoming, direction: .prepend)
            let inverted = SeamSelector.select(retained: try transform(pair.retained) { 255 - $0 },
                                                incoming: try transform(pair.incoming) { 255 - $0 }, direction: .prepend)
            XCTAssertEqual(inverted.shift, regular.shift)
            XCTAssertEqual(inverted.reason, regular.reason)
            XCTAssertEqual(inverted.defaultScore, regular.defaultScore)
            XCTAssertEqual(inverted.selectedScore, regular.selectedScore)
        }
    }

    func testOverallBrightnessChangesDoNotHideLowContrastCardEdges() throws {
        let pair = try weakPair(phase: 2.2)
        for change in [-8, 0, 20, 80, 180] {
            let result = SeamSelector.select(retained: try transform(pair.retained) { UInt8(clamping: Int($0) + change) },
                                              incoming: try transform(pair.incoming) { UInt8(clamping: Int($0) + change) }, direction: .prepend)
            XCTAssertEqual(result.reason, .selected, "Brightness shift \(change)")
            XCTAssertFalse(pair.cardRows.contains { $0.contains(result.selectedRow) })
        }
    }

    func testOneLevelNearBlackNoiseRemainsQuietDespiteSecondDifference() throws {
        let width = 144, height = 500
        let a = (0..<(width * height)).map { UInt8(8 + ($0 % width % 2 == 0 ? -1 : 1)) }
        let b = a.map { $0 + 4 }
        let result = SeamSelector.select(retained: try GrayFrame(width: width, height: height, pixels: a),
                                          incoming: try GrayFrame(width: width, height: height, pixels: b), direction: .prepend)
        XCTAssertEqual(result.reason, .defaultAlreadyQuiet)
        XCTAssertEqual(result.shift, 0)
        XCTAssertEqual(result.defaultMetrics.structureOccupancy, 0)
    }

    func testRampAndNoiseInDifferentFramesCannotCombineIntoAWeakEdge() throws {
        let width = 48, height = 500
        let ramp = (0..<(width * height)).map { UInt8(40 + ($0 % width) * 3) }
        let noise = (0..<(width * height)).map { UInt8($0 % width % 2 == 0 ? 59 : 61) }
        let a = try GrayFrame(width: width, height: height, pixels: ramp)
        let b = try GrayFrame(width: width, height: height, pixels: noise)
        for (first, second) in [(a, b), (b, a)] {
            let result = SeamSelector.select(retained: first, incoming: second, direction: .prepend)
            // Ramp: gradient=3, curvature=0. Noise: gradient=2, curvature=4.
            // Neither frame has a weak edge; their maxima must not be combined.
            XCTAssertEqual(result.reason, .defaultAlreadyQuiet)
            XCTAssertEqual(result.shift, 0)
            XCTAssertEqual(result.defaultMetrics.structureOccupancy, 0)
        }
    }

    func testNoGapInWeakGlassKeepsDefault() throws {
        let pair = try weakPair(phase: 2.2, cardHeight: 1_000)
        let result = SeamSelector.select(retained: pair.retained, incoming: pair.incoming, direction: .prepend)
        XCTAssertEqual(result.reason, .noSafeCandidate)
        XCTAssertEqual(result.shift, 0)
    }

    private func weakPair(phase: Double, cardHeight: Int = 300,
                          direction: SeamSelector.Direction = .prepend) throws -> GlassSeamFixture.Pair {
        try GlassSeamFixture.pair(phase: phase, cardHeight: cardHeight, startWithinCard: 75,
                                  backgroundBase: 18, materialTone: 8,
                                  waveAmplitude: 6, horizontalSlope: 0.01, verticalSlope: 0, direction: direction)
    }

    private func transform(_ frame: GrayFrame, _ pixel: (UInt8) -> UInt8) throws -> GrayFrame {
        try GrayFrame(width: frame.width, height: frame.height, pixels: frame.pixels.map(pixel))
    }
}
