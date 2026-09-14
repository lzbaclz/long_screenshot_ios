import XCTest
import UIKit
import CoreImage
import ScrollCaptureCore
@testable import ScrollCapture

/// Fixed, textured wallpaper and moving opaque messages are rendered as separate
/// layers. The oracle is the original transparent document, never matcher offsets.
@MainActor
final class WallpaperAcceptanceTests: XCTestCase {
    private let imageContext = CIContext(options: [.cacheIntermediates: false])

    func test886By1920AutomaticWallpaperChatStartsUpwardThenReverses() throws {
        try autoreleasepool { try assertMovingCapture(width: 886, height: 1920, startsUpward: true) }
    }

    func test886By1920AutomaticWallpaperChatStartsDownwardThenReverses() throws {
        try autoreleasepool { try assertMovingCapture(width: 886, height: 1920, startsUpward: false) }
    }

    func test1179By2556AutomaticWallpaperChatStartsUpwardThenReverses() throws {
        try autoreleasepool { try assertMovingCapture(width: 1179, height: 2556, startsUpward: true) }
    }

    func test1179By2556AutomaticWallpaperChatStartsDownwardThenReverses() throws {
        try autoreleasepool { try assertMovingCapture(width: 1179, height: 2556, startsUpward: false) }
    }

    func testStationaryWallpaperChatRemainsOneScreenAtBothNativeSizes() throws {
        for (width, height) in [(886, 1920), (1179, 2556)] {
            try autoreleasepool {
                let fixture = makeFixture(width: width, height: height)
                let frame = try viewport(fixture, offset: fixture.bodyHeight * 2)
                let root = temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let repository = try CaptureSessionRepository(rootURL: root)
                var manifest = try repository.createSession(configuration: .init())
                let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: manifest.id)
                for index in 0..<8 {
                    let gray = try analysis(frame)
                    let result = try pipeline.ingest(gray) { frame }
                    XCTAssertTrue(result.strips.isEmpty, "Stationary sample \(index) must not add output rows")
                    _ = try repository.commit(result, maximumBodyHeight: fixture.document.height, to: &manifest)
                }
                XCTAssertFalse(pipeline.hasStarted, "Repeated stationary texture is not scrolling evidence")
                XCTAssertEqual(manifest.pixelHeight, 0)
                XCTAssertTrue(try repository.preserveProvisionalFrame(to: &manifest))
                manifest.finalizeCapture(reason: "已手动结束捕捉。", partial: false)
                try repository.saveManifest(manifest)
                XCTAssertTrue(manifest.isSingleFrameFallback)
                XCTAssertEqual(manifest.status, .partial)
                let url = try CaptureImageRenderer(repository: repository).export(sessionID: manifest.id, format: .png)
                let actual = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
                XCTAssertEqual(actual.width, width)
                XCTAssertEqual(actual.height, height, "An unscrolled page must never become a long screenshot")
                assertExactPixels(rgba(actual), rgba(frame), context: "stationary \(width)×\(height)")
            }
        }
    }

    private func assertMovingCapture(width: Int, height: Int, startsUpward: Bool) throws {
        let fixture = makeFixture(width: width, height: height)
        let offsets = trajectory(bodyHeight: fixture.bodyHeight, startsUpward: startsUpward)
        let firstOffset = try XCTUnwrap(offsets.first)
        let minimum = try XCTUnwrap(offsets.min())
        let maximum = try XCTUnwrap(offsets.max())
        XCTAssertGreaterThan(maximum - minimum, fixture.bodyHeight * 2,
                             "The independent trajectory must traverse more than two body viewports")
        XCTAssertGreaterThan(minimum, 0)
        XCTAssertLessThan(maximum + fixture.bodyHeight, fixture.document.height)
        let firstFrame = try viewport(fixture, offset: firstOffset)
        let movedFrame = try viewport(fixture, offset: offsets[2])
        // The outer 8 pixels contain no messages. They must remain identical at
        // the same SCREEN coordinates even though the document has scrolled.
        let margin = CGRect(x: 0, y: fixture.top, width: 8, height: fixture.bodyHeight)
        assertExactPixels(rgba(try XCTUnwrap(firstFrame.cropping(to: margin))),
                          rgba(try XCTUnwrap(movedFrame.cropping(to: margin))), context: "fixed wallpaper margin")
        XCTAssertNotEqual(rgba(firstFrame), rgba(movedFrame), "The foreground must actually move")

        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try CaptureSessionRepository(rootURL: root)
        var manifest = try repository.createSession(configuration: .init())
        // Both insets are zero: all region selection goes through production automatic ROI.
        let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: manifest.id)
        var trace: [[String: Any]] = []
        for (index, offset) in offsets.enumerated() {
            try autoreleasepool {
                let frame = try viewport(fixture, offset: offset)
                let result = try pipeline.ingest(analysis(frame)) { frame }
                _ = try repository.commit(result, maximumBodyHeight: fixture.document.height, to: &manifest)
                if !result.strips.isEmpty { pipeline.confirmCommit() }
                trace.append(["frame": index, "documentOffset": offset,
                              "status": String(describing: result.status), "stripsAdded": result.strips.count,
                              "savedHeight": manifest.pixelHeight])
            }
        }
        attachJSON(["source": "program-generated fixed wallpaper and transparent synthetic chat document",
                    "width": width, "height": height, "top": fixture.top, "bottom": fixture.bottom,
                    "expectedMinimumOffset": minimum, "expectedMaximumOffset": maximum,
                    "startsUpward": startsUpward, "trace": trace], name: "wallpaper-capture-trace")
        guard pipeline.hasStarted else {
            attachImage(firstFrame, name: "wallpaper-first-view")
            attachImage(movedFrame, name: "wallpaper-first-movement")
            XCTFail("Automatic capture never started for \(width)×\(height), upward=\(startsUpward)")
            throw FixtureFailure.captureDidNotStart
        }
        manifest.finalizeCapture(reason: "已手动结束捕捉。", partial: false)
        try repository.saveManifest(manifest)
        XCTAssertEqual(manifest.outputKind, .stitched)
        XCTAssertEqual(manifest.status, .completed)
        let url = try CaptureImageRenderer(repository: repository).export(sessionID: manifest.id, format: .png)
        let actual = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let expectedHeight = height + maximum - minimum
        guard actual.width == width, actual.height == expectedHeight else {
            attachImage(actual, name: "wallpaper-wrong-output-dimensions")
            XCTFail("Expected \(width)×\(expectedHeight), got \(actual.width)×\(actual.height); no inferred-offset adjustment is allowed")
            throw FixtureFailure.wrongOutputDimensions
        }

        let documentCoverage = CGRect(x: 0, y: minimum, width: width,
                                      height: maximum - minimum + fixture.bodyHeight)
        let coveredMessages = fixture.messages.filter { $0.inner.intersects(documentCoverage) }
        XCTAssertGreaterThan(coveredMessages.count, 15, "Enough distinct messages must enter the oracle")
        // Every intersecting message is inspected in increasing DOCUMENT order,
        // including partial messages at the two outer viewport boundaries.
        var previousDocumentY: CGFloat = -1
        for message in coveredMessages {
            XCTAssertGreaterThan(message.bubble.minY, previousDocumentY)
            previousDocumentY = message.bubble.minY
            let sourceRectangle = message.inner.intersection(documentCoverage)
            let outputRectangle = sourceRectangle.offsetBy(dx: 0, dy: CGFloat(fixture.top - minimum))
            let expectedPatch = try XCTUnwrap(fixture.document.cropping(to: sourceRectangle))
            let actualPatch = try XCTUnwrap(actual.cropping(to: outputRectangle))
            let expectedBytes = rgba(expectedPatch)
            XCTAssertTrue(stride(from: 3, to: expectedBytes.count, by: 4).allSatisfy { expectedBytes[$0] == 255 },
                          "The independent inner rectangle of \(message.id) must be fully opaque")
            assertExactPixels(rgba(actualPatch), expectedBytes,
                              context: "\(message.id) at document y=\(Int(sourceRectangle.minY)), output y=\(Int(outputRectangle.minY))")
        }
        // Also inspect ALL opaque foreground outside those inner rectangles:
        // avatars, timestamp tags, visible message IDs, card captions, and the
        // opaque portions of rounded bubble edges. Wallpaper-only pixels may differ.
        let expectedForeground = try XCTUnwrap(fixture.document.cropping(to: documentCoverage))
        let actualBody = try XCTUnwrap(actual.cropping(to: CGRect(x: 0, y: CGFloat(fixture.top),
                                                               width: CGFloat(width), height: documentCoverage.height)))
        assertOpaqueForeground(rgba(actualBody), expected: rgba(expectedForeground), width: width)
        let topRectangle = CGRect(x: 0, y: 0, width: width, height: fixture.top)
        let sourceBottom = CGRect(x: 0, y: height - fixture.bottom, width: width, height: fixture.bottom)
        let outputBottom = sourceBottom.offsetBy(dx: 0, dy: CGFloat(maximum - minimum))
        assertExactPixels(rgba(try XCTUnwrap(actual.cropping(to: topRectangle))),
                          rgba(try XCTUnwrap(firstFrame.cropping(to: topRectangle))), context: "single fixed top bar")
        assertExactPixels(rgba(try XCTUnwrap(actual.cropping(to: outputBottom))),
                          rgba(try XCTUnwrap(firstFrame.cropping(to: sourceBottom))), context: "single fixed bottom bar")
    }

    private func trajectory(bodyHeight: Int, startsUpward: Bool) -> [Int] {
        let start = bodyHeight * 2
        let step = bodyHeight / 5
        let sign = startsUpward ? -1 : 1
        var offsets = [start, start] // A stable starting view before the first movement.
        offsets += (1...6).map { start + sign * $0 * step }
        offsets += (1...12).map { start + sign * (6 - $0) * step }
        // A second reversal revisits existing content. It must not duplicate it.
        offsets += [start - sign * 5 * step, start - sign * 4 * step,
                    start - sign * 5 * step, start - sign * 6 * step]
        return offsets
    }

    private struct Message {
        let id: String
        let bubble: CGRect
        let inner: CGRect
        let avatar: CGRect
        let text: String
        let imageCard: Bool
        let outgoing: Bool
        let timestamp: CGRect?
    }

    private struct Fixture {
        let width: Int
        let height: Int
        let top: Int
        let bottom: Int
        let document: CGImage
        let wallpaper: CGImage
        let messages: [Message]
        var bodyHeight: Int { height - top - bottom }
    }

    private func makeFixture(width: Int, height: Int) -> Fixture {
        let scale = CGFloat(width) / 393
        let font = UIFont.systemFont(ofSize: 16 * scale)
        let top = Int((104 * scale).rounded())
        let bottom = Int((76 * scale).rounded())
        let texts = ["好呀", "这是一条合成短句，观察文字和壁纸分别怎样移动。", "收到", "嗯嗯",
                     "沿着小路慢慢走，看看树叶的颜色，再读一会儿书。\n这些内容由测试程序生成。",
                     "背景固定在屏幕上，只有消息在滚动。", "等一会儿", "可以往上看，也可以往下读。"]
        let maximumWidth = floor(254 * scale)
        var messages: [Message] = []
        var y = floor(18 * scale)
        for index in 0..<64 {
            let id = String(format: "W%03d", index)
            var timestamp: CGRect?
            if index.isMultiple(of: 7) {
                timestamp = CGRect(x: floor(CGFloat(width) / 2 - 66 * scale), y: y,
                                   width: floor(132 * scale), height: floor(22 * scale))
                y += floor(37 * scale)
            }
            let outgoing = index % 4 == 1 || index % 4 == 2
            let card = index % 9 == 4 || index % 13 == 9
            let text = (index % 6 == 3 ? "合成片段 \(id)\n" : "") + texts[index % texts.count]
            let measured = (text as NSString).boundingRect(with: CGSize(width: maximumWidth - 26 * scale, height: 1000 * scale),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
            let bubbleWidth = card ? floor(224 * scale) : max(floor(57 * scale), min(maximumWidth, ceil(measured.width + 26 * scale)))
            let bubbleHeight = card ? floor(170 * scale) : max(floor(44 * scale), ceil(measured.height + 24 * scale))
            let x = outgoing ? CGFloat(width) - floor(52 * scale) - bubbleWidth : floor(52 * scale)
            let bubble = CGRect(x: x, y: y, width: bubbleWidth, height: bubbleHeight)
            let avatar = CGRect(x: outgoing ? CGFloat(width) - floor(43 * scale) : floor(11 * scale), y: y,
                                width: floor(32 * scale), height: floor(32 * scale))
            messages.append(Message(id: id, bubble: bubble, inner: bubble.insetBy(dx: ceil(14 * scale), dy: ceil(14 * scale)),
                                    avatar: avatar, text: text, imageCard: card, outgoing: outgoing, timestamp: timestamp))
            y += bubbleHeight + floor(26 * scale)
        }
        let documentHeight = Int(y + 24 * scale)
        let document = renderer(width: width, height: documentHeight, opaque: false).image { context in
            context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: documentHeight))
            for (index, message) in messages.enumerated() {
                if let timestamp = message.timestamp {
                    UIColor(white: 0.40, alpha: 1).setFill()
                    UIBezierPath(roundedRect: timestamp, cornerRadius: 6 * scale).fill()
                    (String(format: "合成时间 %02d:%02d", 9 + index / 14, index * 3 % 60) as NSString).draw(
                        at: CGPoint(x: timestamp.minX + 10 * scale, y: timestamp.minY + 4 * scale),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 10 * scale), .foregroundColor: UIColor.white])
                }
                (message.outgoing ? UIColor(red: 0.65, green: 0.92, blue: 0.40, alpha: 1) : .white).setFill()
                UIBezierPath(roundedRect: message.bubble, cornerRadius: 13 * scale).fill()
                UIColor(red: message.outgoing ? 0.35 : 0.43, green: 0.49, blue: message.outgoing ? 0.29 : 0.69, alpha: 1).setFill()
                UIBezierPath(roundedRect: message.avatar, cornerRadius: 7 * scale).fill()
                ((message.outgoing ? "叶" : "山") as NSString).draw(
                    at: CGPoint(x: message.avatar.minX + 7 * scale, y: message.avatar.minY + 5 * scale),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 17 * scale, weight: .semibold), .foregroundColor: UIColor.white])
                if message.imageCard {
                    let card = CGRect(x: message.bubble.minX + 8 * scale, y: message.bubble.minY + 8 * scale,
                                      width: message.bubble.width - 16 * scale, height: 122 * scale).integral
                    drawTexture(context.cgContext, rect: card, seed: UInt64(index + 71) * 137, detailCount: 110)
                    ("合成图片 · 山间光影" as NSString).draw(
                        at: CGPoint(x: message.bubble.minX + 12 * scale, y: message.bubble.minY + 140 * scale),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 12 * scale), .foregroundColor: UIColor.black])
                } else {
                    (message.text as NSString).draw(in: message.bubble.insetBy(dx: 13 * scale, dy: 12 * scale),
                        withAttributes: [.font: font, .foregroundColor: UIColor.black])
                }
                (message.id as NSString).draw(at: CGPoint(x: message.bubble.minX + 3 * scale, y: message.bubble.maxY + 2 * scale),
                    withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 8 * scale, weight: .semibold),
                                     .foregroundColor: UIColor(white: 0.12, alpha: 1)])
            }
        }.cgImage!
        let wallpaper = renderer(width: width, height: height, opaque: true).image { context in
            drawTexture(context.cgContext, rect: CGRect(x: 0, y: 0, width: width, height: height),
                        seed: 0xCAFE_7139, detailCount: 6000)
        }.cgImage!
        return Fixture(width: width, height: height, top: top, bottom: bottom,
                       document: document, wallpaper: wallpaper, messages: messages)
    }

    private func viewport(_ fixture: Fixture, offset: Int) throws -> CGImage {
        let foreground = try XCTUnwrap(fixture.document.cropping(to: CGRect(x: 0, y: offset,
                                                                           width: fixture.width, height: fixture.bodyHeight)))
        let scale = CGFloat(fixture.width) / 393
        return try XCTUnwrap(renderer(width: fixture.width, height: fixture.height, opaque: true).image { context in
            UIImage(cgImage: fixture.wallpaper).draw(at: .zero)
            UIImage(cgImage: foreground).draw(at: CGPoint(x: 0, y: fixture.top))
            UIColor(white: 0.95, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: fixture.width, height: fixture.top))
            context.fill(CGRect(x: 0, y: fixture.height - fixture.bottom, width: fixture.width, height: fixture.bottom))
            ("09:41    固定壁纸 · 合成测试" as NSString).draw(at: CGPoint(x: 17 * scale, y: 40 * scale),
                withAttributes: [.font: UIFont.systemFont(ofSize: 16 * scale, weight: .semibold), .foregroundColor: UIColor.black])
            ("合成消息输入栏                       ＋" as NSString).draw(
                at: CGPoint(x: 16 * scale, y: CGFloat(fixture.height - fixture.bottom) + 18 * scale),
                withAttributes: [.font: UIFont.systemFont(ofSize: 14 * scale), .foregroundColor: UIColor.darkGray])
        }.cgImage)
    }

    private func drawTexture(_ context: CGContext, rect: CGRect, seed: UInt64, detailCount: Int) {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect)
        var random = TextureRandom(seed: seed)
        let colors = [UIColor(red: 0.36, green: 0.62, blue: 0.79, alpha: 1).cgColor,
                      UIColor(red: 0.83, green: 0.66, blue: 0.42, alpha: 1).cgColor,
                      UIColor(red: 0.19, green: 0.39, blue: 0.27, alpha: 1).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
            context.drawLinearGradient(gradient, start: rect.origin,
                                       end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        }
        for layer in 0..<6 {
            let path = UIBezierPath()
            let y = rect.minY + rect.height * (0.20 + CGFloat(layer) * 0.12)
            path.move(to: CGPoint(x: rect.minX, y: y))
            for step in 0...14 {
                path.addLine(to: CGPoint(x: rect.minX + CGFloat(step) * rect.width / 14,
                                        y: y + random.unit() * rect.height * 0.14))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.close()
            UIColor(red: 0.14 + random.unit() * 0.22, green: 0.31 + random.unit() * 0.26,
                    blue: 0.26 + random.unit() * 0.27, alpha: 0.57).setFill()
            path.fill()
        }
        let factor = rect.width / 393
        for _ in 0..<detailCount {
            let x = rect.minX + random.unit() * rect.width
            let y = rect.minY + random.unit() * rect.height
            let radius = (0.8 + random.unit() * 5) * factor
            context.setFillColor(UIColor(hue: 0.06 + random.unit() * 0.46,
                                         saturation: 0.2 + random.unit() * 0.56,
                                         brightness: 0.36 + random.unit() * 0.6,
                                         alpha: 0.18 + random.unit() * 0.45).cgColor)
            context.fillEllipse(in: CGRect(x: x, y: y, width: radius * 1.7, height: radius))
        }
    }

    private func renderer(width: Int, height: Int, opaque: Bool) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = opaque; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
    }

    private func analysis(_ image: CGImage) throws -> GrayFrame {
        try CaptureFrameConversion.grayFrame(CIImage(cgImage: image), context: imageContext,
                                            width: min(144, image.width), height: image.height)
    }

    private func assertExactPixels(_ actual: [UInt8], _ expected: [UInt8], context: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, context, file: file, line: line)
        guard actual.count == expected.count, actual != expected else { return }
        let first = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }
        XCTFail("\(context): first different byte \(first?.offset ?? -1)", file: file, line: line)
    }

    private func assertOpaqueForeground(_ actual: [UInt8], expected: [UInt8], width: Int,
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        guard actual.count == expected.count else { return }
        var protectedPixels = 0
        for pixel in stride(from: 0, to: expected.count, by: 4) where expected[pixel + 3] == 255 {
            protectedPixels += 1
            if actual[pixel] != expected[pixel] || actual[pixel + 1] != expected[pixel + 1]
                || actual[pixel + 2] != expected[pixel + 2] || actual[pixel + 3] != 255 {
                XCTFail("Opaque foreground replaced or shifted at body pixel (\((pixel / 4) % width), \((pixel / 4) / width)); background seams do not excuse foreground changes", file: file, line: line)
                return
            }
        }
        XCTAssertGreaterThan(protectedPixels, width * 200, "The alpha oracle must protect substantial foreground", file: file, line: line)
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

    private func attachImage(_ image: CGImage, name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func attachJSON(_ object: [String: Any], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WallpaperAcceptance-\(UUID().uuidString)")
    }

    private struct TextureRandom {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func unit() -> CGFloat {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(Double(state >> 32) / Double(UInt32.max))
        }
    }

    private enum FixtureFailure: Error { case captureDidNotStart, wrongOutputDimensions }
}
