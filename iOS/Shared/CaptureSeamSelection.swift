#if canImport(UIKit)
import CoreGraphics
import CoreImage
import ImageIO
import ScrollCaptureCore

struct CaptureSeamPlan {
    let shift: Int
    let record: CaptureSeamRecord
}

extension CaptureSessionRepository {
    // CIContext manages expensive rendering resources and is safe for concurrent
    // renders. Reuse those resources across transactions; cacheIntermediates is
    // disabled and no source image, frame history, or output pixels are retained.
    private static let seamImageContext = CIContext(options: [.cacheIntermediates: false])

    /// Called only within an admitted .advanced transaction. The retained
    /// patch is read from the output manifest, never from a matcher's history.
    /// Initial body strips written earlier in this transaction are readable too.
    func selectCaptureSeam(for pending: PendingCaptureStrip, admittedRows: Int,
                           manifest: CaptureSessionManifest, eligible: Bool,
                           quotaLimited: Bool, enabled: Bool = true) -> CaptureSeamPlan {
        let prepend = pending.placement == .prepend
        let defaultRow = prepend ? pending.sourceTopPixel + pending.image.height : pending.sourceTopPixel
        func fallback(_ reason: String) -> CaptureSeamPlan {
            .init(shift: 0, record: .init(direction: prepend ? "prepend" : "append",
                defaultRow: defaultRow, selectedRow: defaultRow, replacedBodyRows: 0,
                defaultScore: nil, selectedScore: nil, candidateCount: nil, reason: reason))
        }
        guard enabled else { return fallback("disabled") }
        guard eligible else { return fallback("untrustedOutput") }
        guard !quotaLimited, admittedRows == pending.image.height else { return fallback("quota") }
        guard manifest.edits == CaptureEditMetadata() else { return fallback("userEdits") }
        guard let incoming = pending.fullImage, incoming.width == manifest.pixelWidth,
              pending.topInset >= 0, pending.bottomInset >= 0,
              pending.sourceTopPixel >= pending.topInset,
              pending.sourceTopPixel + pending.image.height <= incoming.height - pending.bottomInset
        else { return fallback("unavailable") }
        let available = prepend ? incoming.height - pending.bottomInset - defaultRow : defaultRow - pending.topInset
        let overlap = min(available, manifest.bodyPixelHeight)
        let patchHeight = min(486, overlap)
        // Read only the bounded search interval plus six context rows. The
        // scorer receives the real overlap separately for its 35% bound.
        guard patchHeight >= 12 else { return fallback("insufficientOverlap") }
        do {
            let context = Self.seamImageContext
            let analysisWidth = min(144, incoming.width)
            let retained = try bodyFrontierGray(manifest, rows: patchHeight, prepend: prepend,
                                                 analysisWidth: analysisWidth, context: context)
            let origin = prepend ? defaultRow : defaultRow - patchHeight
            guard let crop = incoming.cropping(to: CGRect(x: 0, y: origin, width: incoming.width, height: patchHeight))
            else { return fallback("unavailable") }
            let current = try CaptureFrameConversion.grayFrame(CIImage(cgImage: crop), context: context,
                                                                 width: analysisWidth, height: patchHeight)
            let choice = SeamSelector.select(retained: retained, incoming: current,
                direction: prepend ? .prepend : .append, overlapLength: overlap, maximumShift: 480)
            guard choice.shift >= 0, choice.shift <= min(480, overlap * 35 / 100, patchHeight - 6),
                  choice.defaultRow == (prepend ? 0 : patchHeight),
                  choice.selectedRow == (prepend ? choice.shift : patchHeight - choice.shift),
                  choice.defaultScore.isFinite, choice.selectedScore.isFinite else { return fallback("unavailable") }
            return .init(shift: choice.shift, record: .init(direction: prepend ? "prepend" : "append",
                defaultRow: defaultRow, selectedRow: origin + choice.selectedRow,
                replacedBodyRows: choice.shift, defaultScore: choice.defaultScore,
                selectedScore: choice.selectedScore, candidateCount: choice.candidateCount,
                reason: choice.reason.rawValue))
        } catch {
            // Missing/inconsistent evidence never authorizes replacing old rows.
            return fallback("unavailable")
        }
    }

    private func bodyFrontierGray(_ manifest: CaptureSessionManifest, rows: Int, prepend: Bool,
                                  analysisWidth: Int, context: CIContext) throws -> GrayFrame {
        let wanted = prepend ? 0..<rows : (manifest.bodyPixelHeight - rows)..<manifest.bodyPixelHeight
        var bodyY = 0
        var pixels: [UInt8] = []
        pixels.reserveCapacity(analysisWidth * rows)
        for strip in manifest.strips where strip.id != manifest.leadingEdgeStripID && strip.id != manifest.trailingEdgeStripID {
            let stripRange = bodyY..<(bodyY + strip.pixelHeight)
            bodyY += strip.pixelHeight
            let lower = max(wanted.lowerBound, stripRange.lowerBound)
            let upper = min(wanted.upperBound, stripRange.upperBound)
            guard lower < upper else { continue }
            let part = try autoreleasepool {
                let image = try readCaptureStrip(strip, sessionID: manifest.id)
                guard let crop = image.cropping(to: CGRect(x: 0, y: lower - stripRange.lowerBound,
                    width: strip.pixelWidth, height: upper - lower)) else { throw CaptureStorageError.imageEncodingFailed }
                return try CaptureFrameConversion.grayFrame(CIImage(cgImage: crop), context: context,
                    width: analysisWidth, height: upper - lower)
            }
            pixels.append(contentsOf: part.pixels)
            if bodyY >= wanted.upperBound { break }
        }
        guard pixels.count == rows * analysisWidth else { throw CaptureStorageError.invalidManifest }
        return try GrayFrame(width: analysisWidth, height: rows, pixels: pixels)
    }

    func readCaptureStrip(_ strip: CaptureStrip, sessionID: UUID) throws -> CGImage {
        let url = try stripURL(strip, sessionID: sessionID)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == strip.pixelWidth, image.height == strip.pixelHeight else {
            throw CaptureStorageError.invalidManifest
        }
        return image
    }
}
#endif
