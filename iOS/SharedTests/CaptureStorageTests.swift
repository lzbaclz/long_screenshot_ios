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

    func testEmptyTerminalStateKeepsStorageFailureAndNeverClaimsSavedContent() {
        var session = CaptureSessionManifest()
        let failure = CaptureStorageError.imageEncodingFailed.localizedDescription
        session.finalizeCapture(reason: failure, partial: true)
        XCTAssertEqual(session.status, .partial)
        XCTAssertFalse(session.hasImage)
        XCTAssertTrue(session.stopReason?.hasPrefix("未写入可用画面。") == true)
        XCTAssertTrue(session.stopReason?.contains(failure) == true)
        session.finalizeCapture(reason: "捕捉已暂停，已保留成功捕捉的部分。请重新开始下一段。", partial: true)
        XCTAssertFalse(session.stopReason?.contains("已保留") == true)
    }

    func testSchemaOneBeforeOptionalMetadataRemainsReadable() throws {
        let session = try repository.createSession(configuration: .init())
        let encoder = JSONEncoder()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(session)) as? [String: Any])
        for key in ["outputKind", "diagnostics", "leadingEdgeStripID", "trailingEdgeStripID", "provisionalFrame"] { json.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(CaptureSessionManifest.self,
                                              from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.schemaVersion, 1)
        XCTAssertFalse(legacy.hasImage)
        XCTAssertFalse(legacy.isSingleFrameFallback)
    }

    func testPrependQuotaRetainsRowsNearestExistingSeam() throws {
        var session = try repository.createSession(configuration: .init())
        try repository.appendStrip(image: solid(.blue, width: 20, height: 50), to: &session)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let head = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 20, width: 20, height: 10))
        }.cgImage!
        let result = CaptureFrameResult(status: .advanced,
            strips: [.init(image: head, sourceTopPixel: 7, placement: .prepend)], isArming: false)
        XCTAssertTrue(try repository.commit(result, maximumBodyHeight: 60, to: &session))
        XCTAssertEqual(session.strips.map(\.pixelHeight), [10, 50])
        XCTAssertEqual(session.strips[0].sourceTopPixel, 27)
        session.status = .completed; try repository.saveManifest(session)
        let output = try CaptureImageRenderer(repository: repository).export(sessionID: session.id)
        let rendered = try XCTUnwrap(UIImage(contentsOfFile: output.path)?.cgImage)
        XCTAssertEqual(pixel(rendered, x: 10, y: 5), [0, 255, 0, 255])
        XCTAssertEqual(pixel(rendered, x: 10, y: 15), [0, 0, 255, 255])
    }

    func testEdgeAndBodyTransactionFailureKeepsPriorCompleteManifest() throws {
        var session = try repository.createSession(configuration: .init())
        let full = solid(.red, width: 20, height: 80)
        let body = try XCTUnwrap(full.cropping(to: CGRect(x: 0, y: 10, width: 20, height: 60)))
        let start = CaptureFrameResult(status: .advanced,
            strips: [.init(image: body, sourceTopPixel: 10, fullImage: full,
                           topInset: 10, bottomInset: 10, isInitial: true)], isArming: false)
        try repository.commit(start, maximumBodyHeight: 500, to: &session)
        let before = session
        let originalURLs = try before.strips.map { try repository.stripURL($0, sessionID: before.id) }
        let originalData = try originalURLs.map { try Data(contentsOf: $0) }
        // First staged strip succeeds; the second has inconsistent width.
        let failed = CaptureFrameResult(status: .advanced, strips: [
            .init(image: solid(.blue, width: 20, height: 5), sourceTopPixel: 65,
                  fullImage: full, topInset: 10, bottomInset: 10),
            .init(image: solid(.blue, width: 21, height: 5), sourceTopPixel: 0)
        ], isArming: false)
        XCTAssertThrowsError(try repository.commit(failed, maximumBodyHeight: 500, to: &session))
        XCTAssertEqual(session, before)
        XCTAssertEqual(try repository.loadSession(id: session.id), before)
        XCTAssertEqual(try originalURLs.map { try Data(contentsOf: $0) }, originalData)
        let pngs = try FileManager.default.contentsOfDirectory(at: repository.sessionDirectory(id: session.id),
                                                              includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" }
        XCTAssertEqual(pngs.count, before.strips.count)
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
