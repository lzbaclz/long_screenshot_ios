import XCTest
import UIKit
import CoreImage
import ScrollCaptureCore
@testable import ScrollCapture

/// Independent review fixtures: rendered text and chat layout, not the matcher's
/// random-noise benchmark. Expected images come directly from the source page.
@MainActor
final class BidirectionalAcceptanceTests: XCTestCase {
    private let width = 240
    private let bodyHeight = 320
    private let top = 44
    private let bottom = 36
    private let imageContext = CIContext(options: [.cacheIntermediates: false])

    func testManualChatCaptureExtendsBothEndsInNaturalReadingOrder() throws {
        let document = makeDocument(chat: true)
        let offsets = [360, 323, 280, 320, 360, 407, 360, 300, 250, 420]
        let actual = try capture(document: document, offsets: offsets, automatic: false)
        let start = try XCTUnwrap(offsets.min())
        let end = try XCTUnwrap(offsets.max()) + bodyHeight
        let expected = try XCTUnwrap(document.cropping(to: CGRect(x: 0, y: start, width: width, height: end - start)))
        XCTAssertEqual(actual.height, end - start)
        assertPixels(rgba(actual), rgba(expected))
    }

    func testAutomaticChatPreservesAllBodyRowsAndOuterBarsOnce() throws {
        let document = makeDocument(chat: true)
        let offsets = [360, 323, 280, 320, 360, 407, 360, 300, 250, 420]
        try assertAutomaticDocument(document, offsets: offsets)
    }

    func testAutomaticMomentsLayoutHandlesPausePhotosAndBothDirections() throws {
        let document = makeMomentsDocument()
        // A pause at the intended start, downward browsing, then upward past
        // that start and finally a return beyond the original lower frontier.
        try assertAutomaticDocument(document, offsets: [320, 320, 320, 357, 401, 455, 400, 350, 300, 250, 302, 360, 418, 480])
    }

    func testAutomaticArticleCanStartByViewingEarlierContent() throws {
        try assertAutomaticDocument(makeDocument(chat: false), offsets: [360, 323, 280, 250, 280, 320, 367])
    }

    func testChatStartsUpwardWithLargePlainImageAtItsLowerEdge() throws {
        let base = makeDocument(chat: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let document = UIGraphicsImageRenderer(size: CGSize(width: width, height: base.height), format: format).image { context in
            UIImage(cgImage: base).draw(at: .zero)
            UIColor(white: 0.88, alpha: 1).setFill()
            context.fill(CGRect(x: 40, y: 870, width: 183, height: 650))
        }.cgImage!
        try assertAutomaticDocument(document, offsets: [700, 700, 680, 643, 607, 570])
    }

    func testChatStartsUpwardWithKeyboardAndPreservesBothOuterViews() throws {
        let document = makeDocument(chat: true)
        let offsets = [730, 730, 713, 676, 640, 603]
        let fullHeight = top + bodyHeight + bottom
        let visibleBody = 210
        let keyboardAndInput = fullHeight - top - visibleBody
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LongletKeyboardAcceptance-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try CaptureSessionRepository(rootURL: root)
        var manifest = try repository.createSession(configuration: .init())
        let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: manifest.id)
        var views: [CGImage] = []
        for (index, offset) in offsets.enumerated() {
            let view = try makeKeyboardViewport(document, offset: offset, visibleBody: visibleBody, clock: index)
            views.append(view)
            let result = try pipeline.ingest(analysis(view)) { view }
            _ = try repository.commit(result, maximumBodyHeight: 6_000, to: &manifest)
            if !result.strips.isEmpty { pipeline.confirmCommit() }
        }
        XCTAssertTrue(pipeline.hasStarted, "A usable chat region above the keyboard must allow upward capture")
        manifest.finalizeCapture(reason: "已手动结束捕捉。", partial: false)
        try repository.saveManifest(manifest)
        let output = try CaptureImageRenderer(repository: repository).export(sessionID: manifest.id)
        let actual = try XCTUnwrap(UIImage(contentsOfFile: output.path)?.cgImage)
        let earliest = try XCTUnwrap(offsets.min())
        let latest = try XCTUnwrap(offsets.max())
        let firstView = try XCTUnwrap(views.last)
        let lastView = try XCTUnwrap(views.first)
        let firstBar = try XCTUnwrap(firstView.cropping(to: CGRect(x: 0, y: 0, width: width, height: top)))
        let body = try XCTUnwrap(document.cropping(to: CGRect(x: 0, y: earliest, width: width,
                                                               height: latest - earliest + visibleBody)))
        let lastBar = try XCTUnwrap(lastView.cropping(to: CGRect(x: 0, y: top + visibleBody,
                                                               width: width, height: keyboardAndInput)))
        XCTAssertEqual(actual.height, fullHeight + latest - earliest)
        assertPixels(rgba(actual), rgba(firstBar) + rgba(body) + rgba(lastBar))
    }

    private func assertAutomaticDocument(_ document: CGImage, offsets: [Int], file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try capture(document: document, offsets: offsets, automatic: true)
        let minimum = try XCTUnwrap(offsets.min())
        let maximum = try XCTUnwrap(offsets.max())
        let first = try makeViewport(document, offset: minimum, clock: try XCTUnwrap(offsets.lastIndex(of: minimum)))
        let last = try makeViewport(document, offset: maximum, clock: try XCTUnwrap(offsets.lastIndex(of: maximum)))
        let firstBar = try XCTUnwrap(first.cropping(to: CGRect(x: 0, y: 0, width: width, height: top)))
        let body = try XCTUnwrap(document.cropping(to: CGRect(x: 0, y: minimum, width: width,
                                                               height: maximum - minimum + bodyHeight)))
        let lastBar = try XCTUnwrap(last.cropping(to: CGRect(x: 0, y: top + bodyHeight, width: width, height: bottom)))
        XCTAssertEqual(actual.height, top + maximum - minimum + bodyHeight + bottom, file: file, line: line)
        assertPixels(rgba(actual), rgba(firstBar) + rgba(body) + rgba(lastBar), file: file, line: line)
    }

    func testProductionGrayConversionKeepsTopAndBottomRowsInSourceOrder() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 200), format: format).image { context in
            UIColor(white: 0.9, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 200))
            UIColor(white: 0.1, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
            UIColor(white: 0.5, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 40, width: 80, height: 70))
        }.cgImage!
        let gray = try CaptureFrameConversion.grayFrame(CIImage(cgImage: image), context: CIContext(), width: 48, height: 200)
        let topValue = gray.pixels[10 * 48 + 20]
        let middleValue = gray.pixels[70 * 48 + 20]
        let bottomValue = gray.pixels[170 * 48 + 20]
        XCTAssertLessThan(topValue, middleValue)
        XCTAssertLessThan(middleValue, bottomValue)
        XCTAssertGreaterThan(Int(bottomValue) - Int(topValue), 100)
    }

    private func capture(document: CGImage, offsets: [Int], automatic: Bool) throws -> CGImage {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LongletAcceptance-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try CaptureSessionRepository(rootURL: root)
        var manifest = try repository.createSession(configuration: .init())
        let pipeline = CaptureFramePipeline(configuration: automatic ? .init() : .init(topInset: top, bottomInset: bottom),
                                            repository: repository, sessionID: manifest.id)
        for (index, offset) in offsets.enumerated() {
            let viewport = try makeViewport(document, offset: offset, clock: index)
            let gray = try analysis(viewport)
            let result = try pipeline.ingest(gray) { viewport }
            if !automatic { XCTAssertNotEqual(result.status, .rejected, "frame \(index), position \(offset)") }
            _ = try repository.commit(result, maximumBodyHeight: 6_000, to: &manifest)
            if !result.strips.isEmpty { pipeline.confirmCommit() }
        }
        XCTAssertTrue(pipeline.hasStarted)
        manifest.status = .completed
        try repository.saveManifest(manifest)
        let output = try CaptureImageRenderer(repository: repository).export(sessionID: manifest.id, format: .png)
        return try XCTUnwrap(UIImage(contentsOfFile: output.path)?.cgImage)
    }

    private func makeDocument(chat: Bool) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: 1_800), format: format).image { context in
            UIColor(white: chat ? 0.96 : 1, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: 1_800))
            let sentences = ["Save the view, keep the detail.", "A short message with a reply.",
                             "The next row has different words.", "Read earlier, then continue below."]
            var y: CGFloat = 18
            for row in 0..<30 {
                if row == 8 || row == 19 { y += 65 }
                let x: CGFloat = chat && row % 2 == 1 ? 48 : 18
                if chat {
                    (row % 2 == 1 ? UIColor(red: 0.79, green: 0.92, blue: 0.83, alpha: 1) : UIColor.white).setFill()
                    UIBezierPath(roundedRect: CGRect(x: x - 7, y: y - 6, width: 181, height: 40), cornerRadius: 8).fill()
                    UIColor(red: CGFloat((row * 37) % 190) / 255, green: 0.43, blue: 0.55, alpha: 1).setFill()
                    context.fill(CGRect(x: x == 48 ? 222 : 3, y: y - 2, width: 12, height: 15))
                }
                let text = "\(row + 1). \(sentences[row % sentences.count])"
                (text as NSString).draw(in: CGRect(x: x, y: y, width: 164, height: 35), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor(white: 0.15, alpha: 1)
                ])
                y += 49
            }
        }.cgImage!
    }

    private func makeViewport(_ document: CGImage, offset: Int, clock: Int) throws -> CGImage {
        let body = try XCTUnwrap(document.cropping(to: CGRect(x: 0, y: offset, width: width, height: bodyHeight)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: top + bodyHeight + bottom), format: format).image { context in
            UIColor(white: 0.94, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: top + bodyHeight + bottom))
            UIImage(cgImage: body).draw(in: CGRect(x: 0, y: top, width: width, height: bodyHeight))
            ("09:\(String(format: "%02d", clock % 60))   Test conversation" as NSString).draw(
                at: CGPoint(x: 12, y: 14), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black])
            ("Message                         +" as NSString).draw(
                at: CGPoint(x: 16, y: top + bodyHeight + 10), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray])
        }.cgImage!
    }

    private func makeMomentsDocument() -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: 2_200), format: format)
        return renderer.image { context in drawMomentsPage(context) }.cgImage!
    }

    private func makeKeyboardViewport(_ document: CGImage, offset: Int, visibleBody: Int, clock: Int) throws -> CGImage {
        let body = try XCTUnwrap(document.cropping(to: CGRect(x: 0, y: offset, width: width, height: visibleBody)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let fullHeight = top + bodyHeight + bottom
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: fullHeight), format: format).image { context in
            UIColor(white: 0.94, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: fullHeight))
            UIImage(cgImage: body).draw(in: CGRect(x: 0, y: top, width: width, height: visibleBody))
            ("09:\(String(format: "%02d", clock))   Chat" as NSString).draw(at: CGPoint(x: 12, y: 14),
                withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black])
            let inputY = top + visibleBody
            UIColor.white.setFill()
            context.fill(CGRect(x: 30, y: inputY + 4, width: 176, height: 24))
            for row in 0..<3 {
                for column in 0..<9 {
                    let key = CGRect(x: 8 + column * 25, y: inputY + 37 + row * 31, width: 21, height: 26)
                    UIColor.white.setFill()
                    UIBezierPath(roundedRect: key, cornerRadius: 4).fill()
                    let title = String(UnicodeScalar(65 + row * 9 + column)!)
                    (title as NSString).draw(at: CGPoint(x: key.minX + 6, y: key.minY + 5),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black])
                }
            }
        }.cgImage!
    }

    private func drawMomentsPage(_ context: UIGraphicsImageRendererContext) {
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: 2_200))
            var y: CGFloat = 10
            for post in 0..<10 {
                UIColor(red: 0.3 + CGFloat(post % 3) * 0.1, green: 0.6, blue: 0.72, alpha: 1).setFill()
                context.fill(CGRect(x: 8, y: y, width: 25, height: 25))
                ("Friend \(post + 1)" as NSString).draw(at: CGPoint(x: 43, y: y), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 12), .foregroundColor: UIColor(red: 0.22, green: 0.31, blue: 0.46, alpha: 1)])
                ("Post \(post + 1): a walk, a picture,\nand something to remember." as NSString).draw(
                    in: CGRect(x: 43, y: y + 20, width: 186, height: 34), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor(white: 0.13, alpha: 1)])
                let photoHeight: CGFloat = post % 2 == 0 ? 92 : 61
                let photo = CGRect(x: 43, y: y + 61, width: 157, height: photoHeight)
                context.cgContext.saveGState()
                context.cgContext.clip(to: photo)
                for band in 0..<12 {
                    let redValue: Int = 40 + (band * 17 + post * 31) % 150
                    let greenValue: Int = 85 + (band * 11 + post * 7) % 125
                    let blueValue: Int = 55 + (band * 23 + post * 19) % 150
                    UIColor(red: CGFloat(redValue) / 255, green: CGFloat(greenValue) / 255,
                            blue: CGFloat(blueValue) / 255, alpha: 1).setFill()
                    let bandX = photo.minX + CGFloat(band * 17)
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: bandX - 60, y: photo.minY))
                    path.addLine(to: CGPoint(x: bandX - 41, y: photo.minY))
                    path.addLine(to: CGPoint(x: bandX + 20, y: photo.maxY))
                    path.addLine(to: CGPoint(x: bandX, y: photo.maxY))
                    path.close(); path.fill()
                }
                context.cgContext.restoreGState()
                ("\(post + 1) minutes ago  ·  2 comments" as NSString).draw(
                    at: CGPoint(x: 43, y: photo.maxY + 12), withAttributes: [
                        .font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray])
                y = photo.maxY + 49
                UIColor(white: 0.93, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: y - 10, width: CGFloat(width), height: 1))
            }
    }

    private func analysis(_ image: CGImage) throws -> GrayFrame {
        try CaptureFrameConversion.grayFrame(CIImage(cgImage: image), context: imageContext,
                                            width: min(144, image.width), height: image.height)
    }

    private func assertPixels(_ actual: [UInt8], _ expected: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        guard actual != expected else { return }
        let first = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }
        XCTFail("Source/output pixels differ; first different byte \(first?.offset ?? -1)", file: file, line: line)
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
