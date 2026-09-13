import XCTest
import UIKit
@testable import ScrollCapture

final class CaptureStorageTests: XCTestCase {
    private var directory: URL!
    private var repository: CaptureSessionRepository!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repository = try CaptureSessionRepository(rootURL: directory)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testAtomicRoundTripAndStaleSessionRecoveryPreserveStrips() throws {
        var session = try repository.createSession(configuration: .init())
        try repository.appendStrip(image: solid(.red, width: 100, height: 120), to: &session)
        let stripURL = try repository.stripURL(XCTUnwrap(session.strips.first), sessionID: session.id)
        let source = try Data(contentsOf: stripURL)
        session.updatedAt = Date(timeIntervalSinceNow: -60)
        try repository.saveManifest(session)
        XCTAssertEqual(try repository.recoverInterruptedSessions(), 1)
        XCTAssertEqual(try repository.loadSession(id: session.id).status, .interrupted)
        XCTAssertEqual(try Data(contentsOf: stripURL), source)
        XCTAssertEqual(try repository.recoverInterruptedSessions(), 0)
    }

    func testActiveSessionCannotBeEditedOrDeletedAndFreshLeaseIsNotRecovered() throws {
        let session = try repository.createSession(configuration: .init())
        XCTAssertThrowsError(try repository.saveEdits(.init(), sessionID: session.id))
        XCTAssertThrowsError(try repository.deleteSession(id: session.id))
        XCTAssertEqual(try repository.recoverInterruptedSessions(), 0)
        try repository.requestStop(id: session.id)
        XCTAssertTrue(repository.hasStopRequest(id: session.id))
    }

    func testLiveWriterLeasePreventsStaleRecoveryUntilProcessOwnershipEnds() throws {
        var session = try repository.createSession(configuration: .init())
        var lease: CaptureSessionLease? = try repository.acquireSessionLease(id: session.id)
        session.updatedAt = Date(timeIntervalSinceNow: -300)
        try repository.saveManifest(session)
        XCTAssertEqual(try repository.recoverInterruptedSessions(), 0)
        XCTAssertEqual(try repository.loadSession(id: session.id).status, .capturing)
        XCTAssertThrowsError(try repository.acquireSessionLease(id: session.id))
        XCTAssertThrowsError(try repository.deleteSession(id: session.id))
        withExtendedLifetime(lease) {}
        lease = nil
        XCTAssertEqual(try repository.recoverInterruptedSessions(), 1)
        XCTAssertEqual(try repository.loadSession(id: session.id).status, .interrupted)
    }

    func testRejectsUnsafeConfigurationAndPathTraversal() throws {
        XCTAssertThrowsError(try repository.saveConfiguration(.init(maximumDurationSeconds: .infinity)))
        XCTAssertThrowsError(try repository.saveConfiguration(.init(idleStopSeconds: 2)))
        var session = try repository.createSession(configuration: .init())
        session.pixelWidth = 100
        session.strips = [.init(fileName: "../../outside.png", pixelWidth: 100, pixelHeight: 100)]
        XCTAssertThrowsError(try repository.saveManifest(session))
        XCTAssertThrowsError(try repository.stripURL(session.strips[0], sessionID: session.id))
    }

    func testCropOpaqueRedactionAndSeamTrimExportDoNotModifySource() throws {
        var session = try repository.createSession(configuration: .init())
        try repository.appendStrip(image: solid(.red, width: 100, height: 100), to: &session)
        try repository.appendStrip(image: solid(.blue, width: 100, height: 100), to: &session)
        session.status = .completed
        try repository.saveManifest(session)
        let urls = try session.strips.map { try repository.stripURL($0, sessionID: session.id) }
        let originals = try urls.map { try Data(contentsOf: $0) }
        let edits = CaptureEditMetadata(crop: .init(x: 0, y: 0, width: 1, height: 0.5),
                                        redactions: [.init(x: 0.2, y: 0.1, width: 0.2, height: 0.2)],
                                        seamTrimPixels: [session.strips[1].id.uuidString: 20])
        try repository.saveEdits(edits, sessionID: session.id)
        let renderer = CaptureImageRenderer(repository: repository)
        let dimensions = try renderer.outputDimensions(sessionID: session.id)
        XCTAssertEqual(dimensions.pixelWidth, 100)
        XCTAssertEqual(dimensions.pixelHeight, 90)
        let first = try renderer.export(sessionID: session.id)
        let second = try renderer.export(sessionID: session.id, format: .jpeg)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, originals)
        let result = try XCTUnwrap(UIImage(contentsOfFile: first.path)?.cgImage)
        XCTAssertEqual(pixel(result, x: 30, y: 30), [0, 0, 0, 255])
        XCTAssertEqual(pixel(result, x: 80, y: 30), [255, 0, 0, 255])
        let unedited = try renderer.preview(sessionID: session.id, editsOverride: .init())
        XCTAssertEqual(unedited.cgImage?.height, 200)
        XCTAssertEqual(try repository.loadSession(id: session.id).edits, edits)
    }

    func testExportRequiresExplicitDownscaleAndReportsDimensions() throws {
        var session = try repository.createSession(configuration: .init())
        try repository.appendStrip(image: solid(.green, width: 100, height: 200), to: &session)
        session.status = .completed
        try repository.saveManifest(session)
        let renderer = CaptureImageRenderer(repository: repository)
        XCTAssertThrowsError(try renderer.outputDimensions(sessionID: session.id, maxPixelCount: 5_000))
        XCTAssertThrowsError(try renderer.export(sessionID: session.id, maxPixelCount: 5_000))
        let dimensions = try renderer.outputDimensions(sessionID: session.id, maxPixelCount: 5_000, allowDownscale: true)
        XCTAssertEqual(dimensions.pixelWidth, 50)
        XCTAssertEqual(dimensions.pixelHeight, 100)
        XCTAssertTrue(dimensions.wasDownscaled)
        let url = try renderer.export(sessionID: session.id, maxPixelCount: 5_000, allowDownscale: true)
        XCTAssertEqual(UIImage(contentsOfFile: url.path)?.cgImage?.height, 100)
    }

    func testInvalidEditAndMissingSourceFailClosed() throws {
        var session = try repository.createSession(configuration: .init())
        try repository.appendStrip(image: solid(.red, width: 50, height: 50), to: &session)
        session.status = .completed
        try repository.saveManifest(session)
        XCTAssertThrowsError(try repository.saveEdits(.init(redactions: [.init(x: .nan, y: 0, width: 1, height: 1)]),
                                                      sessionID: session.id))
        XCTAssertThrowsError(try repository.saveEdits(.init(crop: .init(x: 1, y: 0, width: 0.0000001, height: 1)),
                                                      sessionID: session.id))
        XCTAssertThrowsError(try repository.saveEdits(.init(seamTrimPixels: [session.strips[0].id.uuidString: 50]),
                                                      sessionID: session.id))
        try FileManager.default.removeItem(at: repository.stripURL(session.strips[0], sessionID: session.id))
        XCTAssertThrowsError(try CaptureImageRenderer(repository: repository).export(sessionID: session.id))
        XCTAssertEqual(try repository.loadSession(id: session.id).strips.count, 1)
    }

    func testDownscaledRedactionMasksPixelEdgesWithoutTranslucentLeakage() throws {
        var session = try repository.createSession(configuration: .init())
        try repository.appendStrip(image: solid(.red, width: 100, height: 200), to: &session)
        session.status = .completed
        try repository.saveManifest(session)
        try repository.saveEdits(.init(redactions: [.init(x: 0.01, y: 0.2, width: 0.02, height: 0.4)]),
                                 sessionID: session.id)
        let url = try CaptureImageRenderer(repository: repository)
            .export(sessionID: session.id, maxPixelCount: 5_000, allowDownscale: true)
        let result = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        XCTAssertEqual(result.width, 50)
        for x in 0..<4 {
            XCTAssertEqual(pixel(result, x: x, y: 30), [0, 0, 0, 255])
        }
        XCTAssertEqual(pixel(result, x: 6, y: 30), [255, 0, 0, 255])
    }

    private func solid(_ color: UIColor, width: Int, height: Int) -> CGImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.cgImage!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let start = (y * image.width + x) * 4
        return Array(bytes[start..<(start + 4)])
    }
}
