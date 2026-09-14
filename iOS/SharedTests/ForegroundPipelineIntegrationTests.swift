import XCTest
import UIKit
import ScrollCaptureCore
@testable import ScrollCapture

/// Structural fixtures only: the wallpaper is fixed in screen coordinates and
/// opaque message cards move in document coordinates. No private chat content.
final class ForegroundPipelineIntegrationTests: XCTestCase {
    func testFixedWallpaperPreservesMovingForegroundAndOriginalStripPixels() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try CaptureSessionRepository(rootURL: folder)
        var manifest = try repository.createSession(configuration: .init())
        let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: manifest.id)
        let positions = [700, 663, 620, 712, 760, 640]
        let original = try fixture(offset: positions[0])
        for position in positions {
            let frame = try fixture(offset: position)
            let result = try pipeline.ingest(frame) { self.image(frame) }
            XCTAssertFalse(result.replacedProvisionalStart)
            XCTAssertNotEqual(result.status, .rejected, "position \(position), stage \(pipeline.diagnostics.lastStage)")
            for strip in result.strips {
                let source = strip.isInitial ? original : frame
                let expected = Array(source.pixels[(strip.sourceTopPixel * source.width)..<((strip.sourceTopPixel + strip.image.height) * source.width)])
                XCTAssertTrue(pixels(strip.image) == expected, "A pending strip must contain untouched source pixels")
            }
            manifest.provisionalFrame = pipeline.provisionalFrame
            if !result.strips.isEmpty {
                try repository.commit(result, maximumBodyHeight: 10_000, to: &manifest)
                pipeline.confirmCommit()
            }
        }
        XCTAssertTrue(pipeline.hasStarted)
        XCTAssertEqual(pipeline.diagnostics.provisionalReplacements, 0)
        manifest.finalizeCapture(reason: "已手动结束捕捉。", partial: false)
        try repository.saveManifest(manifest)
        let output = try CaptureImageRenderer(repository: repository).export(sessionID: manifest.id)
        let rendered = try XCTUnwrap(UIImage(contentsOfFile: output.path)?.cgImage)
        let actual = pixels(rendered)
        let earliest = try XCTUnwrap(positions.min()), latest = try XCTUnwrap(positions.max())
        XCTAssertEqual(rendered.height, height + latest - earliest)
        var mismatches: [String] = []
        for documentY in earliest..<(latest + height - top - bottom) {
            for x in 0..<width {
                guard let expected = foregroundPixel(x: x, documentY: documentY, seed: 0) else { continue }
                let y = top + documentY - earliest
                guard y < rendered.height else { continue }
                if actual[y * width + x] != expected, mismatches.count < 8 {
                    mismatches.append("\(x),\(documentY): \(actual[y * width + x]) != \(expected)")
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "Foreground differs from independent document coordinates: \(mismatches)")
        XCTAssertGreaterThan(pipeline.diagnostics.stageTimings?[.foregroundRegistration]?.count ?? 0, 0)
        XCTAssertGreaterThan(pipeline.diagnostics.stageTimings?[.alignment]?.count ?? 0, 0)
        XCTAssertEqual(pipeline.diagnostics.stageTimings?[.provisionalWrite]?.count, 1)
    }

    func testResumeRejectsUnknownGapThenContinuesOnlyFromTrustedOverlap() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        var lifecycle = CaptureLifecyclePolicy()
        for position in [700, 663] {
            let frame = try fixture(offset: position)
            _ = try pipeline.ingest(frame) { self.image(frame) }
        }
        XCTAssertTrue(pipeline.hasStarted)
        lifecycle.pause(at: 2, requiresOverlap: pipeline.hasReference)
        XCTAssertFalse(lifecycle.canProcessFrames)
        lifecycle.resume(at: 30)
        let gap = try fixture(offset: 4_500)
        let rejected = try pipeline.ingest(gap, allowProvisionalReplacement: !lifecycle.needsOverlapAfterResume) { self.image(gap) }
        XCTAssertEqual(rejected.status, .rejected)
        XCTAssertNotEqual(pipeline.diagnostics.foregroundStatus, "matched")
        XCTAssertTrue(rejected.strips.isEmpty)
        XCTAssertTrue(lifecycle.needsOverlapAfterResume)
        let previous = try fixture(offset: 663)
        let trusted = try pipeline.ingest(previous, allowProvisionalReplacement: false) { self.image(previous) }
        XCTAssertEqual(trusted.status, .unchanged)
        XCTAssertTrue(lifecycle.verifiedFrame(at: 31))
        let earlier = try fixture(offset: 620)
        let resumed = try pipeline.ingest(earlier) { self.image(earlier) }
        XCTAssertEqual(resumed.status, .advanced)
        XCTAssertEqual(resumed.strips.last?.placement, .prepend)
        XCTAssertEqual(resumed.strips.last?.image.height, 43)
        XCTAssertTrue(lifecycle.finish(at: 32))
        XCTAssertFalse(lifecycle.finish(at: 33))
    }

    func testPausedProvisionalCaptureDoesNotReplaceOriginAcrossAStableUnknownScene() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try CaptureSessionRepository(rootURL: folder)
        let manifest = try repository.createSession(configuration: .init())
        let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: manifest.id)
        let first = try fixture(offset: 700)
        _ = try pipeline.ingest(first) { self.image(first) }
        let candidate = pipeline.provisionalFrame
        var lifecycle = CaptureLifecyclePolicy()
        lifecycle.pause(at: 1, requiresOverlap: pipeline.hasReference)
        lifecycle.resume(at: 30)
        let other = try fixture(offset: 4_500, seed: 991)
        for _ in 0..<4 {
            let result = try pipeline.ingest(other, allowProvisionalReplacement: !lifecycle.needsOverlapAfterResume) { self.image(other) }
            XCTAssertEqual(result.status, .rejected)
            XCTAssertFalse(result.replacedProvisionalStart)
            XCTAssertTrue(result.strips.isEmpty)
        }
        XCTAssertEqual(pipeline.provisionalFrame, candidate)
        XCTAssertEqual(try repository.loadSession(id: manifest.id).provisionalFrame, candidate)
        XCTAssertTrue(pixels(try XCTUnwrap(pipeline.takeSingleFrameFallback())) == first.pixels)
        XCTAssertTrue(lifecycle.needsOverlapAfterResume)
    }

    private let width = 144, height = 800, top = 70, bottom = 90

    private func fixture(offset: Int, seed: Int = 0) throws -> GrayFrame {
        var values = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var value = UInt8(50 + Int(hash(x: x / 4, y: y / 6, seed: seed)) % 160)
                if y < top { value = 226 }
                else if y >= height - bottom { value = 212 }
                else if let foreground = foregroundPixel(x: x, documentY: y - top + offset, seed: seed) { value = foreground }
                values[y * width + x] = value
            }
        }
        return try GrayFrame(width: width, height: height, pixels: values)
    }

    private func foregroundPixel(x: Int, documentY: Int, seed: Int) -> UInt8? {
        let block = documentY / 113, localY = documentY % 113
        let left = block % 2 == 0 ? 18 : 42, cardWidth = 84
        guard (10..<84).contains(localY), x >= left, x < left + cardWidth else { return nil }
        let localX = x - left
        guard (7..<(cardWidth - 7)).contains(localX), (18..<76).contains(localY) else { return 242 }
        let cell = hash(x: localX / 4, y: localY / 5, seed: block + seed * 17)
        return cell % 5 < 3 ? UInt8(20 + Int(cell) % 145) : 242
    }

    private func hash(x: Int, y: Int, seed: Int) -> UInt8 {
        var value = UInt64(x + 1) &* 0x9E3779B185EBCA87 ^ UInt64(y + 1) &* 0xC2B2AE3D27D4EB4F
        value ^= UInt64(seed + 1) &* 0x165667B19E3779F9
        value ^= value >> 30; value &*= 0xBF58476D1CE4E5B9; value ^= value >> 27
        return UInt8(truncatingIfNeeded: value)
    }

    private func image(_ frame: GrayFrame) -> CGImage {
        CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: frame.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                provider: CGDataProvider(data: Data(frame.pixels) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: image.width * image.height)
        result.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return result
    }
}
