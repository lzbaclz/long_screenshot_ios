import XCTest
import CoreGraphics
import ScrollCaptureCore
@testable import ScrollCapture

final class CaptureFramePipelineTests: XCTestCase {
    func testAutomaticFixedBarsKeepEveryBodyRowWithoutRepeatingChrome() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let document = scene(seed: 311)
        var output: [UInt8] = []
        for offset in [0, 23, 47, 31, 68] {
            let gray = try chromeFrame(document, offset: offset, top: 17, bottom: 23)
            let result = try pipeline.ingest(gray) { self.image(gray) }
            XCTAssertNil(result.regionWarning)
            output += result.strips.flatMap { pixels($0.image) }
        }
        XCTAssertEqual(pipeline.effectiveConfiguration.topInset, 17)
        XCTAssertEqual(pipeline.effectiveConfiguration.bottomInset, 23)
        XCTAssertEqual(output, Array(document.prefix((120 + 68) * 48)))
    }

    func testAmbiguousWhitePaddingNeverCommitsAnAutomaticallyCroppedStart() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        var document = scene(seed: 801)
        document.replaceSubrange(0..<(60 * 48), with: repeatElement(UInt8(248), count: 60 * 48))
        _ = try feed(pipeline, source: document, offset: 0)
        let result = try feed(pipeline, source: document, offset: 25)
        XCTAssertEqual(result.status, .rejected)
        XCTAssertNotNil(result.regionWarning)
        XCTAssertTrue(result.strips.isEmpty)
        XCTAssertFalse(pipeline.hasStarted)
    }

    func testManualBarsBypassAutomaticAmbiguityAndKeepBodyPixels() throws {
        let pipeline = CaptureFramePipeline(configuration: .init(topInset: 17, bottomInset: 23))
        var document = scene(seed: 901)
        document.replaceSubrange(0..<(60 * 48), with: repeatElement(UInt8(248), count: 60 * 48))
        let first = try chromeFrame(document, offset: 0, top: 17, bottom: 23)
        _ = try pipeline.ingest(first) { self.image(first) }
        let current = try chromeFrame(document, offset: 25, top: 17, bottom: 23)
        let result = try pipeline.ingest(current) { self.image(current) }
        XCTAssertNil(result.regionWarning)
        XCTAssertEqual(result.strips.flatMap { pixels($0.image) }, Array(document.prefix(145 * 48)))
    }

    func testAppSwitchBeforeFirstScrollReplacesCandidateAndPreservesTargetBeginning() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let host = scene(seed: 4), target = scene(seed: 91)
        let first = try feed(pipeline, source: host, offset: 0)
        XCTAssertTrue(first.isArming)
        XCTAssertTrue(first.strips.isEmpty)
        let switched = try feed(pipeline, source: target, offset: 0)
        XCTAssertTrue(switched.isArming)
        XCTAssertTrue(switched.replacedProvisionalStart)
        XCTAssertTrue(switched.strips.isEmpty)
        let scrolled = try feed(pipeline, source: target, offset: 37)
        XCTAssertFalse(scrolled.isArming)
        XCTAssertEqual(scrolled.strips.map { $0.image.height }, [120, 37])
        let assembled = scrolled.strips.flatMap { pixels($0.image) }
        XCTAssertEqual(assembled, Array(target.prefix(157 * 48)))
    }

    func testStationaryArmingDoesNotRenderAgainAndUntrustedGapNeverAddsContent() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let target = scene(seed: 67)
        _ = try feed(pipeline, source: target, offset: 0)
        let gray = try frame(target, offset: 0)
        let stationary = try pipeline.ingest(gray) {
            XCTFail("Stationary frame must retain the provisional candidate without rendering again")
            return self.image(gray)
        }
        XCTAssertTrue(stationary.isArming)
        XCTAssertFalse(stationary.replacedProvisionalStart)
        XCTAssertFalse(pipeline.hasStarted)
        _ = try feed(pipeline, source: target, offset: 30)
        let gap = try feed(pipeline, source: scene(seed: 999), offset: 0)
        XCTAssertEqual(gap.status, .rejected)
        XCTAssertFalse(gap.isArming)
        XCTAssertTrue(gap.strips.isEmpty)
        let recovered = try feed(pipeline, source: target, offset: 60)
        XCTAssertEqual(recovered.strips.map { $0.image.height }, [30])
        XCTAssertEqual(recovered.strips.flatMap { pixels($0.image) }, Array(target[(150 * 48)..<(180 * 48)]))
    }

    func testUpwardAdjustmentBeforeStartBecomesNewStartingPosition() throws {
        let pipeline = CaptureFramePipeline(configuration: .init(topInset: 4, bottomInset: 6))
        let target = scene(seed: 403)
        _ = try feed(pipeline, source: target, offset: 35)
        let adjustment = try feed(pipeline, source: target, offset: 0)
        XCTAssertTrue(adjustment.isArming)
        XCTAssertTrue(adjustment.replacedProvisionalStart)
        XCTAssertTrue(adjustment.strips.isEmpty)
        let started = try feed(pipeline, source: target, offset: 24)
        XCTAssertEqual(started.strips.map { $0.image.height }, [110, 24])
        XCTAssertEqual(started.strips.flatMap { pixels($0.image) }, Array(target[(4 * 48)..<(138 * 48)]))
    }

    private func feed(_ pipeline: CaptureFramePipeline, source: [UInt8], offset: Int) throws -> CaptureFrameResult {
        let gray = try frame(source, offset: offset)
        return try pipeline.ingest(gray) { self.image(gray) }
    }

    private func frame(_ source: [UInt8], offset: Int) throws -> GrayFrame {
        try GrayFrame(width: 48, height: 120, pixels: Array(source[(offset * 48)..<((offset + 120) * 48)]))
    }

    private func chromeFrame(_ document: [UInt8], offset: Int, top: Int, bottom: Int) throws -> GrayFrame {
        let chrome = scene(seed: 11_091)
        let pixels = Array(chrome.prefix(top * 48)) + Array(document[(offset * 48)..<((offset + 120) * 48)])
            + Array(chrome[(200 * 48)..<((200 + bottom) * 48)])
        return try GrayFrame(width: 48, height: top + 120 + bottom, pixels: pixels)
    }

    private func scene(seed: UInt64) -> [UInt8] {
        var state = seed
        return (0..<(48 * 400)).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return UInt8(truncatingIfNeeded: state >> 32)
        }
    }

    private func image(_ frame: GrayFrame) -> CGImage {
        let data = Data(frame.pixels)
        return CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: frame.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                       provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
