import XCTest
import UIKit
import CoreText
import CoreImage
import ScrollCaptureCore
@testable import ScrollCapture

final class UpwardStartRegressionTests: XCTestCase {
    func testUpwardStartWithLargeBlankPhotoPreservesEveryVisibleBodyRow() throws {
        try assertCapture(bottom: 96, blankPhoto: true)
    }

    func testUpwardStartAboveKeyboardPreservesEveryVisibleBodyRow() throws {
        try assertCapture(bottom: 1_050, blankPhoto: false)
    }

    func testLargeFirstUpwardStepAboveKeyboardCannotBecomeAnAppend() throws {
        try assertCapture(bottom: 1_050, blankPhoto: false, offsets: [3_000, 2_460])
    }

    func testOneUnchangedPatchDoesNotFreezeAChangedStartingScene() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let first = try UpwardStartFixture.frame(offset: 3_000)
        _ = try pipeline.ingest(first) { self.image(first) }
        let width = first.width, height = first.height
        var changedPixels = [UInt8](repeating: 40, count: width * height)
        let middle = (height / 3 * width)..<((height - height / 3) * width)
        changedPixels.replaceSubrange(middle, with: first.pixels[middle])
        let changed = try GrayFrame(width: width, height: height, pixels: changedPixels)
        let rejected = try pipeline.ingest(changed) { self.image(changed) }
        XCTAssertEqual(rejected.status, .rejected)
        _ = try pipeline.ingest(changed) { self.image(changed) }
        let replaced = try pipeline.ingest(changed) { self.image(changed) }
        XCTAssertEqual(replaced.status, .started)
        XCTAssertTrue(replaced.replacedProvisionalStart)
        XCTAssertTrue(replaced.strips.isEmpty)
        XCTAssertFalse(pipeline.hasStarted)
    }

    func testStationaryMessagesAndKeyboardHighlightNeverStartALongImage() throws {
        let pipeline = CaptureFramePipeline(configuration: .init())
        let initial = try UpwardStartFixture.frame(offset: 3_000, bottom: 1_050)
        _ = try pipeline.ingest(initial) { self.image(initial) }
        for update in 0..<4 {
            var changed = initial.pixels
            for y in (initial.height - 1_050 + 210)..<(initial.height - 1_050 + 310) {
                for x in (20 + update * 14)..<(32 + update * 14) { changed[y * initial.width + x] = 120 }
            }
            let frame = try GrayFrame(width: initial.width, height: initial.height, pixels: changed)
            let result = try pipeline.ingest(frame) { self.image(frame) }
            XCTAssertTrue(result.strips.isEmpty)
            XCTAssertFalse(pipeline.hasStarted)
        }
        XCTAssertEqual(pipeline.diagnostics.acceptedFrames, 0)
        XCTAssertNotNil(pipeline.takeSingleFrameFallback())
    }

    func testNarrowAutomaticRegionStillReceivesTwentyFullViewportBudget() {
        let configuration = CaptureConfiguration(maximumScreenCount: 20)
        let wide = configuration.maximumBodyPixelHeight(frameHeight: 2_556, matchingTopInset: 260, matchingBottomInset: 96)
        let narrow = configuration.maximumBodyPixelHeight(frameHeight: 2_556, matchingTopInset: 900, matchingBottomInset: 1_100)
        XCTAssertEqual(wide + 260 + 96, narrow + 900 + 1_100)
        XCTAssertEqual(narrow + 900 + 1_100, 20 * 2_556)
        let largest = configuration.maximumBodyPixelHeight(frameHeight: 4_096, matchingTopInset: 900, matchingBottomInset: 2_000)
        XCTAssertLessThan(largest + 4_096, 200_000)
        let manual = CaptureConfiguration(maximumScreenCount: 20, captureTopInsetFraction: 0.1, captureBottomInsetFraction: 0.2)
        XCTAssertEqual(manual.maximumBodyPixelHeight(frameHeight: 2_556, matchingTopInset: 255, matchingBottomInset: 511),
                       20 * (2_556 - 255 - 511))
    }

    func testNativeSingleAndDoubleCharacterMessagesStartUpwardOnBothSides() throws {
        for rightSide in [false, true] {
            for bottom in [133, 867] {
                try assertNativeShortMessages(rightSide: rightSide, bottom: bottom)
            }
        }
    }

    private func assertNativeShortMessages(rightSide: Bool, bottom: Int,
                                          file: StaticString = #filePath, line: UInt = #line) throws {
        let width = 1_179, height = 2_556, top = 221
        let document = try nativeShortMessageDocument(rightSide: rightSide)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try CaptureSessionRepository(rootURL: root)
        var manifest = try repository.createSession(configuration: .init())
        let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: manifest.id)
        let conversion = CIContext(options: [.cacheIntermediates: false])
        var initial: CGImage?
        var earlier: CGImage?
        for (index, offset) in [1_440, 1_403, 1_223].enumerated() {
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
            context.setFillColor(gray: 0.9, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let body = try XCTUnwrap(document.cropping(to: CGRect(x: 0, y: offset, width: width, height: height - top - bottom)))
            context.draw(body, in: CGRect(x: 0, y: bottom, width: width, height: height - top - bottom))
            // Synthetic clock variation, while the keyboard/input area stays fixed.
            context.setFillColor(gray: CGFloat(20 + index * 20) / 255, alpha: 1)
            context.fill(CGRect(x: 72, y: height - 99, width: 96, height: 26))
            if bottom > 200 {
                for row in 0..<4 {
                    for column in 0..<10 {
                        context.setFillColor(gray: 0.99, alpha: 1)
                        context.fill(CGRect(x: 17 + column * 115, y: 40 + row * 180, width: 99, height: 140))
                        context.setFillColor(gray: 0.2, alpha: 1)
                        context.fill(CGRect(x: 48 + column * 115, y: 90 + row * 180, width: 31, height: 41))
                    }
                }
            }
            let frame = try XCTUnwrap(context.makeImage())
            if initial == nil { initial = frame }; earlier = frame
            let gray = try CaptureFrameConversion.grayFrame(CIImage(cgImage: frame), context: conversion,
                                                             width: 144, height: height)
            let result = try pipeline.ingest(gray) { frame }
            manifest.provisionalFrame = pipeline.provisionalFrame
            if !result.strips.isEmpty {
                XCTAssertEqual(result.strips.last?.placement, .prepend, file: file, line: line)
                let region = pipeline.effectiveConfiguration
                let budget = manifest.configuration.maximumBodyPixelHeight(frameHeight: height,
                    matchingTopInset: region.topInset, matchingBottomInset: region.bottomInset)
                try repository.commit(result, maximumBodyHeight: budget, to: &manifest)
                pipeline.confirmCommit()
            }
        }
        let description = "native 1179px, 36px Chinese, right=\(rightSide), bottom=\(bottom), stage=\(pipeline.diagnostics.lastStage)"
        XCTAssertTrue(pipeline.hasStarted, description, file: file, line: line)
        XCTAssertEqual(manifest.outputKind, .stitched, description, file: file, line: line)
        guard manifest.hasImage else { return }
        manifest.finalizeCapture(reason: "已手动结束捕捉。", partial: false)
        try repository.saveManifest(manifest)
        let url = try CaptureImageRenderer(repository: repository).export(sessionID: manifest.id)
        let actual = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage)
        let first = pixels(try XCTUnwrap(initial)), last = pixels(try XCTUnwrap(earlier))
        let expected = Array(last.prefix((height - bottom) * width)) + Array(first.suffix((bottom + 217) * width))
        XCTAssertEqual(actual.height, height + 217, description, file: file, line: line)
        XCTAssertTrue(pixels(actual) == expected, "\(description): native visible pixels differ", file: file, line: line)
    }

    private func nativeShortMessageDocument(rightSide: Bool) throws -> CGImage {
        let width = 1_179, height = 6_000
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        context.setFillColor(gray: 0.95, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 36, nil)
        let attributes = [kCTFontAttributeName: font,
                          kCTForegroundColorAttributeName: CGColor(gray: 0.04, alpha: 1)] as CFDictionary
        let words = ["嗯", "好", "到了", "可以", "收到", "行", "在", "好的", "等等", "走吧", "谢谢"]
        var y = 73, index = 0
        while y < height - 100 {
            for row in 0..<6 {
                for column in 0..<6 {
                    context.setFillColor(gray: (row + column * 3) % 5 < 2 ? 0.16 : 0.71, alpha: 1)
                    let x = rightSide ? width - 66 + column * 8 : 18 + column * 8
                    context.fill(CGRect(x: x, y: height - y - (row + 1) * 8, width: 8, height: 8))
                }
            }
            let text = try XCTUnwrap(CFAttributedStringCreate(nil, words[index % words.count] as CFString, attributes))
            let textLine = CTLineCreateWithAttributedString(text)
            let textWidth = CTLineGetTypographicBounds(textLine, nil, nil, nil)
            let x = rightSide ? CGFloat(width - 82) - textWidth - 36 : 82
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: x, y: CGFloat(height - y - 64), width: textWidth + 36, height: 64))
            context.textPosition = CGPoint(x: x + 18, y: CGFloat(height - y - 44)); CTLineDraw(textLine, context)
            y += 124 + (index * 73 + index * index * 19) % 133; index += 1
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func assertCapture(bottom: Int, blankPhoto: Bool, offsets: [Int] = [3_000, 2_820, 2_640],
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try CaptureSessionRepository(rootURL: root)
        var manifest = try repository.createSession(configuration: .init())
        let pipeline = CaptureFramePipeline(configuration: .init(), repository: repository, sessionID: manifest.id)
        var first: GrayFrame?
        var last: GrayFrame?
        for (index, offset) in offsets.enumerated() {
            let frame = try UpwardStartFixture.frame(offset: offset, bottom: bottom, blankPhoto: blankPhoto, clock: index)
            if first == nil { first = frame }; last = frame
            let result = try pipeline.ingest(frame) { self.image(frame) }
            manifest.provisionalFrame = pipeline.provisionalFrame
            if !result.strips.isEmpty {
                XCTAssertEqual(result.strips.last?.placement, .prepend, file: file, line: line)
                try repository.commit(result, maximumBodyHeight: 30_000, to: &manifest)
                pipeline.confirmCommit()
            }
        }
        XCTAssertTrue(pipeline.hasStarted, "Upward start remained at stage \(pipeline.diagnostics.lastStage)", file: file, line: line)
        XCTAssertEqual(manifest.outputKind, .stitched, file: file, line: line)
        guard manifest.hasImage else { return }
        manifest.finalizeCapture(reason: "已手动结束捕捉。", partial: false)
        try repository.saveManifest(manifest)
        let exported = try CaptureImageRenderer(repository: repository).export(sessionID: manifest.id)
        let actual = try XCTUnwrap(UIImage(contentsOfFile: exported.path)?.cgImage)
        let initial = try XCTUnwrap(first), earlier = try XCTUnwrap(last)
        let width = UpwardStartFixture.width, height = UpwardStartFixture.height
        let added = try XCTUnwrap(offsets.first) - XCTUnwrap(offsets.last)
        let expected = Array(earlier.pixels.prefix((height - bottom) * width))
            + Array(initial.pixels.suffix((bottom + added) * width))
        XCTAssertEqual(actual.height, height + added, file: file, line: line)
        XCTAssertEqual(pixels(actual), expected, file: file, line: line)
    }

    private func image(_ frame: GrayFrame) -> CGImage {
        CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: frame.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                provider: CGDataProvider(data: Data(frame.pixels) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}

private enum UpwardStartFixture {
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
