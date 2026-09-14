import XCTest
import UIKit
import CoreImage
import ScrollCaptureCore
@testable import ScrollCapture

/// Native-size, short Chinese bubbles pass through the actual grayscale,
/// automatic startup, durable strip storage and PNG export path.
@MainActor
final class ShortChatAcceptanceTests: XCTestCase {
    private let width = 1_179
    private let height = 2_556
    private let top = 260
    private let bottom = 156
    private let imageContext = CIContext(options: [.cacheIntermediates: false])

    func testIncomingShortChineseMessagesStartUpward() throws { try verify(layout: 0) }
    func testOutgoingShortChineseMessagesStartUpward() throws { try verify(layout: 1) }
    func testAlternatingShortChineseMessagesStartUpward() throws { try verify(layout: 2) }

    private func verify(layout: Int) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShortChatAcceptance-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try CaptureSessionRepository(rootURL: root)
        var manifest = try repository.createSession(configuration: .init())
        let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: manifest.id)
        let document = makeDocument(layout: layout)
        let offsets = [3_000, 2_963, 2_820]
        var views: [CGImage] = []
        for offset in offsets {
            let view = try viewport(document, offset: offset)
            views.append(view)
            let gray = try CaptureFrameConversion.grayFrame(CIImage(cgImage: view), context: imageContext,
                                                           width: 144, height: height)
            let result = try pipeline.ingest(gray) { view }
            _ = try repository.commit(result, maximumBodyHeight: 20 * height - top - bottom, to: &manifest)
            if !result.strips.isEmpty { pipeline.confirmCommit() }
        }
        XCTAssertTrue(pipeline.hasStarted, "Short-message layout \(layout) stalled at \(pipeline.diagnostics.lastStage)")
        guard manifest.hasImage else { return }
        manifest.finalizeCapture(reason: "已手动结束捕捉。", partial: false)
        try repository.saveManifest(manifest)
        let output = try CaptureImageRenderer(repository: repository).export(sessionID: manifest.id)
        let actual = try XCTUnwrap(UIImage(contentsOfFile: output.path)?.cgImage)
        let start = try XCTUnwrap(offsets.min()), end = try XCTUnwrap(offsets.max()) + height - top - bottom
        let leading = try XCTUnwrap(views.last?.cropping(to: CGRect(x: 0, y: 0, width: width, height: top)))
        let body = try XCTUnwrap(document.cropping(to: CGRect(x: 0, y: start, width: width, height: end - start)))
        let trailing = try XCTUnwrap(views.first?.cropping(to: CGRect(x: 0, y: height - bottom, width: width, height: bottom)))
        XCTAssertEqual(actual.height, height + 180)
        let expected = rgba(leading) + rgba(body) + rgba(trailing)
        XCTAssertTrue(rgba(actual) == expected, "Export must contain the exact earlier messages, in source order")
    }

    private func makeDocument(layout: Int) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: 7_000), format: format)
        return renderer.image { context in
            UIColor(white: 0.95, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: 7_000))
            let words = ["嗯", "好", "到了", "行", "可以", "是", "走", "嗯嗯", "好的", "到啦", "嗯好"]
            let spaces = [127, 191, 143, 216, 164, 137, 183]
            var y = 20
            var index = 0
            while y < 6_900 {
                let outgoing = layout == 1 || (layout == 2 && index % 2 == 1)
                let word = words[index % words.count]
                let wordWidth = word.count * 36
                let avatarX = outgoing ? width - 84 : 36
                let bubbleWidth = wordWidth + 36
                let bubbleX = outgoing ? width - 108 - bubbleWidth : 108
                UIColor(red: 0.27, green: 0.48, blue: 0.66, alpha: 1).setFill()
                context.fill(CGRect(x: avatarX, y: y, width: 48, height: 48))
                UIColor.white.setStroke()
                let face = UIBezierPath(ovalIn: CGRect(x: avatarX + 12, y: y + 8, width: 24, height: 28))
                face.lineWidth = 3; face.stroke()
                (outgoing ? UIColor(red: 0.69, green: 0.91, blue: 0.56, alpha: 1) : UIColor.white).setFill()
                UIBezierPath(roundedRect: CGRect(x: bubbleX, y: y - 4, width: bubbleWidth, height: 62), cornerRadius: 10).fill()
                (word as NSString).draw(at: CGPoint(x: bubbleX + 18, y: y + 4), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor(white: 0.08, alpha: 1)
                ])
                y += spaces[index % spaces.count]; index += 1
            }
        }.cgImage!
    }

    private func viewport(_ document: CGImage, offset: Int) throws -> CGImage {
        let bodyHeight = height - top - bottom
        let body = try XCTUnwrap(document.cropping(to: CGRect(x: 0, y: offset, width: width, height: bodyHeight)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor(white: 0.94, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIImage(cgImage: body).draw(in: CGRect(x: 0, y: top, width: width, height: bodyHeight))
            ("测试聊天" as NSString).draw(at: CGPoint(x: 450, y: 145), withAttributes: [
                .font: UIFont.systemFont(ofSize: 42), .foregroundColor: UIColor.black
            ])
            UIColor.white.setFill()
            context.fill(CGRect(x: 140, y: height - 118, width: 820, height: 76))
        }.cgImage!
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
