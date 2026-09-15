import XCTest
import UIKit
import CoreImage
import ScrollCaptureCore
@testable import ScrollCapture

/// Independent procedural page geometry and source-frame ownership. No private
/// screenshots, no visible test IDs, and no oracle input is passed to capture.
final class SeamCaptureAcceptanceTests: XCTestCase {
    func testNativeGlassPrependAndReversalUseOriginalSourceRows() throws {
        try nativeCapture(prepend: true)
    }

    func testNativeGlassAppendAndReversalUseOriginalSourceRows() throws {
        try nativeCapture(prepend: false)
    }

    func testReplacementTraversesMultipleSmallStripsAndPreviouslyCroppedStrip() throws {
        for prepend in [true, false] {
            try withRepository { repository, session in
                let fixture = GlassCaptureFixture(width: 144, height: 1_000)
                let oldOffset = fixture.period * 4 + fixture.period / 2
                let old = fixture.frame(offset: oldOffset)
                // Many real immutable body files; the frontier is deliberately
                // not represented by any one original reference frame.
                for y in stride(from: fixture.top, to: fixture.height - fixture.bottom, by: 11) {
                    let end = min(y + 11, fixture.height - fixture.bottom)
                    try repository.appendStrip(image: self.image(old, fixture).cropping(to:
                        CGRect(x: 0, y: y, width: fixture.width, height: end - y))!, sourceTopPixel: y, to: &session)
                }
                var expected = Array(old[(fixture.top * fixture.width)..<((fixture.height - fixture.bottom) * fixture.width)])
                var offset = oldOffset
                var firstShift = 0
                for step in 0..<2 {
                    offset += prepend ? -37 : 37
                    let values = fixture.frame(offset: offset)
                    let full = self.image(values, fixture)
                    let pending = try self.pending(full, fixture, delta: 37, prepend: prepend)
                    let beforeHeight = session.bodyPixelHeight
                    try repository.commit(.init(status: .advanced, strips: [pending], isArming: false),
                                          maximumBodyHeight: 20_000, to: &session)
                    let record = try XCTUnwrap(session.diagnostics?.seams?.recent.last)
                    if step == 0 { firstShift = record.replacedBodyRows }
                    let shift = record.replacedBodyRows
                    if prepend {
                        expected.removeFirst(shift * fixture.width)
                        expected.insert(contentsOf: values[(fixture.top * fixture.width)..<((fixture.top + 37 + shift) * fixture.width)], at: 0)
                    } else {
                        expected.removeLast(shift * fixture.width)
                        let start = fixture.height - fixture.bottom - 37 - shift
                        expected.append(contentsOf: values[(start * fixture.width)..<((fixture.height - fixture.bottom) * fixture.width)])
                    }
                    XCTAssertEqual(session.bodyPixelHeight, beforeHeight + 37)
                    XCTAssertTrue(session.strips.allSatisfy { $0.pixelHeight > 0 })
                    XCTAssertEqual(Set(session.strips.map(\.id)).count, session.strips.count)
                    XCTAssertTrue(session.edits.seamTrimPixels.isEmpty)
                    XCTAssertEqual(try self.bodyPixels(repository, session), expected)
                }
                XCTAssertGreaterThan(firstShift, 22, "Replacement should traverse several 11-row stored strips")
            }
        }
    }

    func testQuotaFallbackPreservesExistingSkipAndBodyBudget() throws {
        for prepend in [true, false] {
            for remaining in [0, 17, 37] {
                try withRepository { repository, session in
                    let fixture = GlassCaptureFixture(width: 144, height: 1_000)
                    let oldOffset = fixture.period * 4 + fixture.period / 2
                    let old = fixture.frame(offset: oldOffset)
                    try self.seed(repository, &session, fixture, values: old)
                    let before = session
                    let values = fixture.frame(offset: oldOffset + (prepend ? -37 : 37))
                    let full = self.image(values, fixture)
                    let result = CaptureFrameResult(status: .advanced,
                        strips: [try self.pending(full, fixture, delta: 37, prepend: prepend)], isArming: false)
                    XCTAssertTrue(try repository.commit(result, maximumBodyHeight: before.bodyPixelHeight + remaining, to: &session))
                    XCTAssertEqual(session.bodyPixelHeight, before.bodyPixelHeight + remaining)
                    if remaining == 0 {
                        XCTAssertEqual(session, before)
                    } else {
                        let record = try XCTUnwrap(session.diagnostics?.seams?.recent.last)
                        XCTAssertFalse(record.applied)
                        XCTAssertEqual(record.reason, "quota")
                        let body = Array(old[(fixture.top * fixture.width)..<((fixture.height - fixture.bottom) * fixture.width)])
                        let start = prepend ? fixture.top + 37 - remaining : fixture.height - fixture.bottom - 37
                        let added = Array(values[(start * fixture.width)..<((start + remaining) * fixture.width)])
                        XCTAssertEqual(try self.bodyPixels(repository, session), prepend ? added + body : body + added)
                        let preservedID = prepend ? session.trailingEdgeStripID : session.leadingEdgeStripID
                        XCTAssertEqual(preservedID, prepend ? before.trailingEdgeStripID : before.leadingEdgeStripID)
                        let changedID = try XCTUnwrap(prepend ? session.leadingEdgeStripID : session.trailingEdgeStripID)
                        let cap = try XCTUnwrap(session.strips.first { $0.id == changedID })
                        let capStart = prepend ? 37 - remaining : start + remaining
                        let capHeight = prepend ? fixture.top : fixture.bottom
                        XCTAssertEqual(self.pixels(try repository.readCaptureStrip(cap, sessionID: session.id)),
                            Array(values[(capStart * fixture.width)..<((capStart + capHeight) * fixture.width)]))
                    }
                }
            }
        }
    }

    func testUserEditsDisableReplacementAndKeepStripIDsValid() throws {
        try withRepository { repository, session in
            let fixture = GlassCaptureFixture(width: 144, height: 1_000)
            let offset = fixture.period * 4 + fixture.period / 2
            try self.seed(repository, &session, fixture, values: fixture.frame(offset: offset))
            let bodyID = try XCTUnwrap(session.strips.first { $0.id != session.leadingEdgeStripID && $0.id != session.trailingEdgeStripID }).id
            session.edits.seamTrimPixels[bodyID.uuidString] = 7
            try repository.saveManifest(session)
            let full = self.image(fixture.frame(offset: offset - 37), fixture)
            try repository.commit(.init(status: .advanced, strips: [try self.pending(full, fixture, delta: 37, prepend: true)], isArming: false),
                                  maximumBodyHeight: 20_000, to: &session)
            XCTAssertTrue(session.strips.contains { $0.id == bodyID })
            XCTAssertEqual(session.edits.seamTrimPixels[bodyID.uuidString], 7)
            XCTAssertEqual(session.diagnostics?.seams?.recent.last?.reason, "userEdits")
            XCTAssertEqual(session.diagnostics?.seams?.recent.last?.replacedBodyRows, 0)
        }
    }

    func testFailedReplacementTransactionLeavesEveryPublishedByteAndDiagnosticUntouched() throws {
        try withRepository { repository, session in
            let fixture = GlassCaptureFixture(width: 144, height: 1_000)
            let offset = fixture.period * 4 + fixture.period / 2
            try self.seed(repository, &session, fixture, values: fixture.frame(offset: offset))
            let before = session
            let urls = try before.strips.map { try repository.stripURL($0, sessionID: session.id) }
            let bytes = try urls.map { try Data(contentsOf: $0) }
            let full = self.image(fixture.frame(offset: offset - 37), fixture)
            let valid = try self.pending(full, fixture, delta: 37, prepend: true)
            let planned = repository.selectCaptureSeam(for: valid, admittedRows: 37, manifest: session,
                                                        eligible: true, quotaLimited: false)
            XCTAssertGreaterThan(planned.shift, 0, "The rollback must exercise an actual selected replacement")
            // The first operation trims and stages new files; a later invalid
            // width aborts the transaction before its manifest is published.
            let wrong = self.image([UInt8](repeating: 50, count: 145 * 10), width: 145, height: 10)
            let failed = CaptureFrameResult(status: .advanced, strips: [valid,
                .init(image: wrong, sourceTopPixel: 0)], isArming: false)
            XCTAssertThrowsError(try repository.commit(failed, maximumBodyHeight: 20_000, to: &session))
            XCTAssertEqual(session, before)
            XCTAssertEqual(try repository.loadSession(id: session.id), before)
            XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, bytes)
            let files = try FileManager.default.contentsOfDirectory(at: repository.sessionDirectory(id: session.id), includingPropertiesForKeys: nil)
            XCTAssertEqual(files.filter { $0.pathExtension == "png" }.count, before.strips.count)
        }
    }

    func testFirstCommitFailureKeepsProvisionalStillAndPublishesNoSeam() throws {
        try withRepository { repository, session in
            let fixture = GlassCaptureFixture(width: 144, height: 1_000)
            let offset = fixture.period * 4 + fixture.period / 2
            let first = self.image(fixture.frame(offset: offset), fixture)
            let candidate = try repository.stageProvisionalFrame(image: first, sessionID: session.id)
            session.provisionalFrame = candidate
            let before = try repository.loadSession(id: session.id)
            let candidateURL = try repository.stripURL(candidate, sessionID: session.id)
            let candidateBytes = try Data(contentsOf: candidateURL)
            let body = try XCTUnwrap(first.cropping(to: CGRect(x: 0, y: fixture.top, width: fixture.width, height: fixture.bodyHeight)))
            let next = self.image(fixture.frame(offset: offset - 37), fixture)
            let bad = self.image([UInt8](repeating: 0, count: 145 * 5), width: 145, height: 5)
            let result = CaptureFrameResult(status: .advanced, strips: [
                .init(image: body, sourceTopPixel: fixture.top, fullImage: first,
                      topInset: fixture.top, bottomInset: fixture.bottom, isInitial: true),
                try self.pending(next, fixture, delta: 37, prepend: true),
                .init(image: bad, sourceTopPixel: 0)
            ], isArming: false)
            XCTAssertThrowsError(try repository.commit(result, maximumBodyHeight: 20_000, to: &session))
            XCTAssertTrue(session.strips.isEmpty)
            XCTAssertNil(session.diagnostics?.seams)
            XCTAssertEqual(try repository.loadSession(id: session.id), before)
            XCTAssertEqual(try Data(contentsOf: candidateURL), candidateBytes)
            let files = try FileManager.default.contentsOfDirectory(at: repository.sessionDirectory(id: session.id), includingPropertiesForKeys: nil)
            XCTAssertEqual(files.filter { $0.pathExtension == "png" }.count, 1)
        }
    }

    func testUnavailableFrontierAndManualSourceKeepDefault() throws {
        for mode in ["missing", "manual"] {
            try withRepository { repository, session in
                let fixture = GlassCaptureFixture(width: 144, height: 1_000)
                let offset = fixture.period * 4 + fixture.period / 2
                try self.seed(repository, &session, fixture, values: fixture.frame(offset: offset))
                let oldHeight = session.bodyPixelHeight
                let bodyIndex = try XCTUnwrap(session.strips.firstIndex { $0.id != session.leadingEdgeStripID && $0.id != session.trailingEdgeStripID })
                let oldBody = session.strips[bodyIndex]
                if mode == "missing" {
                    try FileManager.default.removeItem(at: repository.stripURL(oldBody, sessionID: session.id))
                }
                let full = self.image(fixture.frame(offset: offset - 37), fixture)
                let source = try self.pending(full, fixture, delta: 37, prepend: true)
                let pending = mode == "manual" ? PendingCaptureStrip(image: source.image,
                    sourceTopPixel: source.sourceTopPixel, placement: .prepend,
                    topInset: fixture.top, bottomInset: fixture.bottom) : source
                let previousLeading = session.leadingEdgeStripID
                try repository.commit(.init(status: .advanced, strips: [pending], isArming: false),
                                      maximumBodyHeight: 20_000, to: &session)
                XCTAssertEqual(session.bodyPixelHeight, oldHeight + 37)
                XCTAssertEqual(session.diagnostics?.seams?.recent.last?.replacedBodyRows, 0)
                XCTAssertEqual(session.diagnostics?.seams?.recent.last?.reason, "unavailable")
                XCTAssertTrue(session.strips.contains { $0.id == oldBody.id })
                if mode == "manual" { XCTAssertEqual(session.leadingEdgeStripID, previousLeading) }
            }
        }
    }

    func testStalePublishedBodyOrEditsRejectBeforeWriting() throws {
        for mode in ["body", "edits"] {
            try withRepository { repository, session in
                let fixture = GlassCaptureFixture(width: 144, height: 1_000)
                let offset = fixture.period * 4 + fixture.period / 2
                try self.seed(repository, &session, fixture, values: fixture.frame(offset: offset))
                let oldSnapshot = session
                var newer = session
                if mode == "body" {
                    let full = self.image(fixture.frame(offset: offset + 37), fixture)
                    try repository.commit(.init(status: .advanced, strips: [try self.pending(full, fixture,
                        delta: 37, prepend: false)], isArming: false), maximumBodyHeight: 20_000, to: &newer)
                } else {
                    let body = try XCTUnwrap(newer.strips.first { $0.id != newer.leadingEdgeStripID && $0.id != newer.trailingEdgeStripID })
                    newer.edits.seamTrimPixels[body.id.uuidString] = 7
                    try repository.saveManifest(newer)
                }
                let manifestURL = repository.sessionDirectory(id: session.id).appendingPathComponent("manifest.json")
                let manifestBytes = try Data(contentsOf: manifestURL)
                let filesBefore = try FileManager.default.contentsOfDirectory(at: repository.sessionDirectory(id: session.id), includingPropertiesForKeys: nil)
                let urls = try newer.strips.map { try repository.stripURL($0, sessionID: session.id) }
                let pixelsBefore = try urls.map { try Data(contentsOf: $0) }
                let full = self.image(fixture.frame(offset: offset - 37), fixture)
                let staleCommit = CaptureFrameResult(status: .advanced, strips: [try self.pending(full, fixture,
                    delta: 37, prepend: true)], isArming: false)
                XCTAssertThrowsError(try repository.commit(staleCommit, maximumBodyHeight: 20_000, to: &session))
                XCTAssertEqual(session, oldSnapshot)
                XCTAssertEqual(try repository.loadSession(id: session.id), newer)
                XCTAssertEqual(try Data(contentsOf: manifestURL), manifestBytes)
                XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, pixelsBefore)
                XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(at: repository.sessionDirectory(id: session.id),
                    includingPropertiesForKeys: nil)), Set(filesBefore))
            }
        }
    }

    func testOldDataAndBoundedPublishedSeamHistory() throws {
        let old = try JSONDecoder().decode(CaptureDiagnostics.self, from: JSONEncoder().encode(CaptureDiagnostics()))
        XCTAssertNil(old.seams)
        var stats = CaptureSeamDiagnostics()
        for index in 0..<80 {
            stats.record(.init(direction: "prepend", defaultRow: 300, selectedRow: 300 + index,
                replacedBodyRows: index, defaultScore: 20, selectedScore: 10, candidateCount: 20, reason: "selected"))
        }
        XCTAssertEqual(stats.totalCount, 80)
        XCTAssertEqual(stats.appliedCount, 79)
        XCTAssertEqual(stats.omittedCount, 48)
        XCTAssertEqual(stats.recent.count, 32)
        XCTAssertEqual(stats.recent.first?.selectedRow, 348)
        XCTAssertEqual(try JSONDecoder().decode(CaptureSeamDiagnostics.self, from: JSONEncoder().encode(stats)), stats)
    }

    func testPureTranslatedPageRemainsPixelIdenticalAndUsesDefaultSeam() throws {
        try withRepository { repository, session in
            let fixture = GlassCaptureFixture(width: 144, height: 1_000, fixedBackground: false)
            let offset = 900
            let old = fixture.frame(offset: offset)
            try self.seed(repository, &session, fixture, values: old)
            let next = fixture.frame(offset: offset - 37)
            try repository.commit(.init(status: .advanced, strips: [try self.pending(self.image(next, fixture), fixture,
                delta: 37, prepend: true)], isArming: false), maximumBodyHeight: 20_000, to: &session)
            XCTAssertEqual(session.diagnostics?.seams?.recent.last?.replacedBodyRows, 0)
            let expected = Array(next[(fixture.top * fixture.width)..<((fixture.top + 37) * fixture.width)])
                + Array(old[(fixture.top * fixture.width)..<((fixture.height - fixture.bottom) * fixture.width)])
            XCTAssertEqual(try self.bodyPixels(repository, session), expected)
        }
    }

    private func nativeCapture(prepend: Bool) throws {
        let fixture = GlassCaptureFixture(width: 1_179, height: 2_556)
        let start = fixture.period * 4 + fixture.period / 2
        let step = fixture.period / 5
        // maxHistory=1 deliberately makes alignment history unsuitable as an
        // output-frontier cache; reversing continues from actual stored strips.
        let offsets = prepend ? [start, start-step, start-2*step, start-3*step, start-2*step, start-step, start, start+step]
                              : [start, start+step, start+2*step, start+3*step, start+2*step, start+step, start, start-step]
        // Generate exactly once; ON and OFF receive these same original bytes.
        let sources = offsets.map { fixture.frame(offset: $0) }
        var modeHeights: [Int] = []
        for enabled in [false, true] {
        let mode = enabled ? "on" : "off"
        let route = prepend ? "prepend" : "append"
        try withRepository { repository, session in
            var trace: [[String: Any]] = []
            func snapshot(_ manifest: CaptureSessionManifest) -> [String: Any] {
                let leading = manifest.strips.first { $0.id == manifest.leadingEdgeStripID }
                let trailing = manifest.strips.first { $0.id == manifest.trailingEdgeStripID }
                return ["bodyHeight": manifest.bodyPixelHeight, "totalHeight": manifest.pixelHeight,
                    "leadingCapHeight": leading?.pixelHeight ?? 0, "trailingCapHeight": trailing?.pixelHeight ?? 0,
                    "strips": manifest.strips.map { ["id": $0.id.uuidString, "height": $0.pixelHeight,
                        "sourceTop": $0.sourceTopPixel, "leadingCap": $0.id == manifest.leadingEdgeStripID,
                        "trailingCap": $0.id == manifest.trailingEdgeStripID] as [String: Any] }]
            }
            defer {
                if let data = try? JSONSerialization.data(withJSONObject: trace, options: [.prettyPrinted, .sortedKeys]) {
                    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                    attachment.name = "seam-\(route)-\(mode)-trace.json"; attachment.lifetime = .keepAlways; self.add(attachment)
                }
            }
            var configuration = AlignmentConfiguration()
            configuration.maxHistory = 1
            let pipeline = CaptureFramePipeline(configuration: configuration, repository: repository, sessionID: session.id)
            let context = CIContext(options: [.cacheIntermediates: false])
            var owners: [Int: Int] = [:]
            var earliest = start, latest = start
            var leadingIndex = 0, trailingIndex = 0
            for (index, offset) in offsets.enumerated() {
                let values = sources[index]
                let full = self.image(values, fixture)
                let gray = try CaptureFrameConversion.grayFrame(CIImage(cgImage: full), context: context, width: 144, height: fixture.height)
                if !enabled {
                    let attachment = XCTAttachment(data: Data(gray.pixels), uniformTypeIdentifier: "public.data")
                    attachment.name = String(format: "seam-%@-gray-%dx%d-%02d.bin", route, gray.width, gray.height, index)
                    attachment.lifetime = .keepAlways; self.add(attachment)
                }
                let before = snapshot(session)
                let ingestBegan = ProcessInfo.processInfo.systemUptime
                let result = try pipeline.ingest(gray) { full }
                let ingestElapsed = (ProcessInfo.processInfo.systemUptime - ingestBegan) * 1_000
                let entry: [String: Any] = ["index": index, "sourceOffset": offset,
                    "sourceWidth": fixture.width, "sourceHeight": fixture.height,
                    "seamSelectionEnabled": enabled, "status": String(describing: result.status),
                    "ingestElapsedMilliseconds": ingestElapsed,
                    "isArming": result.isArming, "replacedProvisionalStart": result.replacedProvisionalStart,
                    "regionTop": pipeline.effectiveConfiguration.topInset,
                    "regionBottom": pipeline.effectiveConfiguration.bottomInset,
                    "before": before, "after": snapshot(session),
                    "pending": result.strips.map { ["sourceTop": $0.sourceTopPixel,
                        "height": $0.image.height, "placement": String(describing: $0.placement),
                        "isInitial": $0.isInitial, "topInset": $0.topInset, "bottomInset": $0.bottomInset] as [String: Any] }]
                trace.append(entry)
                XCTAssertNotEqual(result.status, .rejected, "frame \(index), stage \(pipeline.diagnostics.lastStage)")
                session.provisionalFrame = pipeline.provisionalFrame
                if index == 0 {
                    for y in start..<(start + fixture.bodyHeight) { owners[y] = 0 }
                }
                guard !result.strips.isEmpty else { continue }
                let commitBegan = ProcessInfo.processInfo.systemUptime
                do {
                    try repository.commit(result, maximumBodyHeight: 25_000, seamSelectionEnabled: enabled, to: &session)
                } catch {
                    trace[trace.count - 1]["commitError"] = String(describing: error)
                    throw error
                }
                trace[trace.count - 1]["commitElapsedMilliseconds"] = (ProcessInfo.processInfo.systemUptime - commitBegan) * 1_000
                trace[trace.count - 1]["after"] = snapshot(session)
                pipeline.confirmCommit()
                let record = try XCTUnwrap(session.diagnostics?.seams?.recent.last)
                trace[trace.count - 1]["seam"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
                let selectedDocumentRow = offset + record.selectedRow - fixture.top
                trace[trace.count - 1]["selectedDocumentRow"] = selectedDocumentRow
                if offset < earliest {
                    for y in offset..<selectedDocumentRow { owners[y] = index }
                    earliest = offset; leadingIndex = index
                } else if offset > latest {
                    for y in selectedDocumentRow..<(offset + fixture.bodyHeight) { owners[y] = index }
                    latest = offset; trailingIndex = index
                }
                if enabled {
                    XCTAssertFalse(fixture.isCardRow(selectedDocumentRow), "Every seam with a feasible gap must leave the glass card: \(record)")
                }
                if record.applied {
                    XCTAssertLessThanOrEqual(record.replacedBodyRows, 480)
                    XCTAssertLessThanOrEqual(try XCTUnwrap(record.selectedScore), try XCTUnwrap(record.defaultScore))
                }
            }
            XCTAssertTrue(pipeline.hasStarted)
            if enabled { XCTAssertGreaterThan(session.diagnostics?.seams?.appliedCount ?? 0, 0) }
            else { XCTAssertEqual(session.diagnostics?.seams?.appliedCount ?? 0, 0) }
            modeHeights.append(session.pixelHeight)
            let expectedHeight = fixture.height + offsets.max()! - offsets.min()!
            trace.append(["summary": true, "expectedHeight": expectedHeight,
                "actualHeight": session.pixelHeight, "earliestSourceOffset": offsets.min()!, "latestSourceOffset": offsets.max()!])
            XCTAssertEqual(session.pixelHeight, expectedHeight, "mode=\(mode)")
            session.finalizeCapture(reason: "已手动结束捕捉。", partial: false)
            try repository.saveManifest(session)
            let output = try CaptureImageRenderer(repository: repository).export(sessionID: session.id, format: .png)
            let rendered = try XCTUnwrap(UIImage(contentsOfFile: output.path)?.cgImage)
            let outputAttachment = XCTAttachment(data: try Data(contentsOf: output), uniformTypeIdentifier: "public.png")
            outputAttachment.name = "seam-\(route)-\(mode)-output.png"; outputAttachment.lifetime = .keepAlways; self.add(outputAttachment)
            let actual = self.pixels(rendered)
            var expected = Array(sources[leadingIndex].prefix(fixture.top * fixture.width))
            for y in earliest..<(latest + fixture.bodyHeight) {
                let owner = try XCTUnwrap(owners[y])
                let sourceRow = fixture.top + y - offsets[owner]
                XCTAssertTrue((fixture.top..<(fixture.height - fixture.bottom)).contains(sourceRow))
                expected.append(contentsOf: sources[owner][(sourceRow * fixture.width)..<((sourceRow + 1) * fixture.width)])
            }
            expected.append(contentsOf: sources[trailingIndex].suffix(fixture.bottom * fixture.width))
            XCTAssertEqual(actual.count, expected.count, "mode=\(mode)")
            if actual != expected {
                let byte = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? -1
                XCTFail("mode=\(mode): Independent original-frame oracle differs at row \(byte / fixture.width), byte \(byte)")
            }
        }
        }
        XCTAssertEqual(modeHeights.first, modeHeights.last, "ON/OFF must preserve the identical admitted document height")
    }

    private func pending(_ image: CGImage, _ fixture: GlassCaptureFixture, delta: Int, prepend: Bool) throws -> PendingCaptureStrip {
        let top = prepend ? fixture.top : fixture.height - fixture.bottom - delta
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: top, width: fixture.width, height: delta)))
        return .init(image: crop, sourceTopPixel: top, placement: prepend ? .prepend : .append,
            fullImage: image, topInset: fixture.top, bottomInset: fixture.bottom)
    }

    private func seed(_ repository: CaptureSessionRepository, _ manifest: inout CaptureSessionManifest,
                      _ fixture: GlassCaptureFixture, values: [UInt8]) throws {
        let full = image(values, fixture)
        let body = try XCTUnwrap(full.cropping(to: CGRect(x: 0, y: fixture.top, width: fixture.width, height: fixture.bodyHeight)))
        try repository.commit(.init(status: .advanced, strips: [.init(image: body, sourceTopPixel: fixture.top,
            fullImage: full, topInset: fixture.top, bottomInset: fixture.bottom, isInitial: true)], isArming: false),
            maximumBodyHeight: 20_000, to: &manifest)
    }

    private func bodyPixels(_ repository: CaptureSessionRepository, _ session: CaptureSessionManifest) throws -> [UInt8] {
        try session.strips.filter { $0.id != session.leadingEdgeStripID && $0.id != session.trailingEdgeStripID }
            .flatMap { pixels(try repository.readCaptureStrip($0, sessionID: session.id)) }
    }

    private func withRepository(_ operation: (CaptureSessionRepository, inout CaptureSessionManifest) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try CaptureSessionRepository(rootURL: folder)
        var session = try repository.createSession(configuration: .init())
        try operation(repository, &session)
    }

    private func image(_ values: [UInt8], _ fixture: GlassCaptureFixture) -> CGImage {
        image(values, width: fixture.width, height: fixture.height)
    }

    private func image(_ values: [UInt8], width: Int, height: Int) -> CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: CGDataProvider(data: Data(values) as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var values = [UInt8](repeating: 0, count: image.width * image.height)
        values.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return values
    }
}

private struct GlassCaptureFixture {
    let width: Int
    let height: Int
    var fixedBackground = true
    var top: Int { height / 10 }
    var bottom: Int { height / 12 }
    var bodyHeight: Int { height - top - bottom }
    var period: Int { height / 5 }
    func isCardRow(_ documentY: Int) -> Bool { (period / 12..<period * 3 / 4).contains(documentY % period) }

    func frame(offset: Int) -> [UInt8] {
        var values = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            var row = [UInt8](repeating: 0, count: 144)
            for x in 0..<144 {
                if y < top || y >= height - bottom {
                    row[x] = (x / 5 + y / 7) % 3 == 0 ? 35 : 235
                    continue
                }
                let documentY = offset + y - top
                let screenY = fixedBackground ? y : documentY
                let background = 115 + 24 * sin(Double(x) / 9) + 18 * sin(Double(screenY) / 31)
                    + 24 * sin((Double(x) + Double(screenY) / 8) / 25)
                var value = background
                let localY = documentY % period
                if isCardRow(documentY), (7..<66).contains(x) || (78..<137).contains(x) {
                    value = 0.45 * background + 0.55 * 240
                    let localX = x < 70 ? x - 7 : x - 78
                    let iconY = (localY - period / 12) % max(1, period / 4)
                    if (6..<25).contains(localX) || (33..<52).contains(localX),
                       (period / 20..<period / 5).contains(iconY) {
                        let block = documentY / period
                        value = (localX / 3 + iconY / 7 + block * 11) % 5 < 3 ? Double(20 + (block * 17 + localX * 3) % 100) : 240
                    }
                }
                row[x] = UInt8(max(0, min(255, value.rounded())))
            }
            for x in 0..<width { values[y * width + x] = row[x * 144 / width] }
        }
        return values
    }
}
