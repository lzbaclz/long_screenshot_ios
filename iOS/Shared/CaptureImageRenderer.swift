#if canImport(UIKit)
import UIKit
import ImageIO
import UniformTypeIdentifiers
import ScrollCaptureCore

public struct CaptureRenderDimensions: Equatable, Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let wasDownscaled: Bool
}

extension CaptureSessionRepository {
    /// Write each original-resolution strip before publishing the manifest that references it.
    /// A crash can leave an orphan strip, but can never publish an incomplete image file.
    public func appendStrip(image: CGImage, sourceTopPixel: Int = 0,
                            placement: StitchDecision.Placement = .append, to manifest: inout CaptureSessionManifest) throws {
        guard manifest.status == .capturing, image.width <= 8_192, image.height <= 16_384,
              manifest.pixelWidth == 0 || manifest.pixelWidth == image.width else {
            throw CaptureStorageError.invalidManifest
        }
        let id = UUID()
        let strip = CaptureStrip(id: id, fileName: "\(id.uuidString).png", pixelWidth: image.width,
                                 pixelHeight: image.height, sourceTopPixel: sourceTopPixel)
        let finalURL = try stripURL(strip, sessionID: manifest.id)
        try Self.writeImage(image, to: finalURL, format: .png)
        let publishedCandidate = try loadSession(id: manifest.id).provisionalFrame
        var updated = manifest
        updated.pixelWidth = image.width
        if placement == .prepend { updated.strips.insert(strip, at: 0) }
        else { updated.strips.append(strip) }
        updated.updatedAt = Date(); updated.provisionalFrame = nil
        try saveManifest(updated)
        if let candidate = publishedCandidate,
           let url = try? stripURL(candidate, sessionID: manifest.id) { try? FileManager.default.removeItem(at: url) }
        manifest = updated
    }

    /// Publish the replacement still before releasing the old one. A fresh
    /// repository in the host can recover it if the capture process vanishes.
    @discardableResult
    func stageProvisionalFrame(image: CGImage, sessionID: UUID) throws -> CaptureStrip {
        var session = try loadSession(id: sessionID)
        guard session.status == .capturing, session.strips.isEmpty else {
            throw CaptureStorageError.invalidManifest
        }
        let id = UUID()
        let candidate = CaptureStrip(id: id, fileName: "\(id.uuidString).png", pixelWidth: image.width,
                                     pixelHeight: image.height)
        let url = try stripURL(candidate, sessionID: sessionID)
        try Self.writeImage(image, to: url, format: .png)
        let previous = session.provisionalFrame
        session.provisionalFrame = candidate; session.updatedAt = Date()
        do { try saveManifest(session) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
        if let previous, let old = try? stripURL(previous, sessionID: sessionID) {
            try? FileManager.default.removeItem(at: old)
        }
        return candidate
    }

    /// Commit an entire admitted frame transaction: all body strips and both
    /// visible outer edges become reachable together. Failure leaves the old
    /// manifest and its continuous image intact. Only superseded edge files
    /// owned by this transaction are removed after publication succeeds.
    @discardableResult
    func commit(_ result: CaptureFrameResult, maximumBodyHeight: Int,
                seamSelectionEnabled: Bool = true, to manifest: inout CaptureSessionManifest) throws -> Bool {
        guard manifest.status == .capturing, maximumBodyHeight > 0 else {
            throw CaptureStorageError.invalidManifest
        }
        let published = try loadSession(id: manifest.id)
        let publishedCandidate = published.provisionalFrame
        // A stale caller cannot publish an older output or overwrite edits.
        // Missing seam evidence may keep the default seam, but an output
        // conflict must fail before staging any new or replacement files.
        guard published.strips == manifest.strips, published.edits == manifest.edits,
              published.leadingEdgeStripID == manifest.leadingEdgeStripID,
              published.trailingEdgeStripID == manifest.trailingEdgeStripID,
              published.pixelWidth == manifest.pixelWidth, published.status == manifest.status,
              published.outputKind == manifest.outputKind else { throw CaptureStorageError.invalidManifest }
        var updated = manifest
        updated.provisionalFrame = publishedCandidate
        var newURLs: [URL] = []
        var committed = false
        defer { if !committed { for url in newURLs { try? FileManager.default.removeItem(at: url) } } }
        func encode(_ image: CGImage, sourceTop: Int) throws -> CaptureStrip {
            guard image.width > 0, image.height > 0,
                  updated.pixelWidth == 0 || updated.pixelWidth == image.width else {
                throw CaptureStorageError.invalidManifest
            }
            let id = UUID()
            let strip = CaptureStrip(id: id, fileName: "\(id.uuidString).png", pixelWidth: image.width,
                                     pixelHeight: image.height, sourceTopPixel: sourceTop)
            let url = try stripURL(strip, sessionID: updated.id)
            try autoreleasepool { try Self.writeImage(image, to: url, format: .png) }
            newURLs.append(url); updated.pixelWidth = image.width
            return strip
        }
        func replaceEdge(image: CGImage, rows: Range<Int>, leading: Bool) throws {
            guard !rows.isEmpty else { return }
            guard let cropped = image.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: image.width,
                                                          height: rows.count)) else {
                throw CaptureStorageError.imageEncodingFailed
            }
            let strip = try encode(cropped, sourceTop: rows.lowerBound)
            let oldID = leading ? updated.leadingEdgeStripID : updated.trailingEdgeStripID
            updated.strips.removeAll { $0.id == oldID }
            if leading { updated.strips.insert(strip, at: 0); updated.leadingEdgeStripID = strip.id }
            else { updated.strips.append(strip); updated.trailingEdgeStripID = strip.id }
        }
        func trimRetainedBody(_ rows: Int, prepend: Bool) throws {
            var remaining = rows
            while remaining > 0 {
                let bodyIndices = updated.strips.indices.filter {
                    updated.strips[$0].id != updated.leadingEdgeStripID && updated.strips[$0].id != updated.trailingEdgeStripID
                }
                guard let index = prepend ? bodyIndices.first : bodyIndices.last else { throw CaptureStorageError.invalidManifest }
                let old = updated.strips[index]
                if old.pixelHeight <= remaining {
                    remaining -= old.pixelHeight
                    updated.strips.remove(at: index)
                } else {
                    let image = try readCaptureStrip(old, sessionID: updated.id)
                    let sourceSkip = prepend ? remaining : 0
                    guard let crop = image.cropping(to: CGRect(x: 0, y: sourceSkip,
                        width: old.pixelWidth, height: old.pixelHeight - remaining)) else {
                        throw CaptureStorageError.imageEncodingFailed
                    }
                    // Immutable replacement: never use editor trim metadata for
                    // capture bookkeeping, and never overwrite a published PNG.
                    updated.strips[index] = try encode(crop, sourceTop: old.sourceTopPixel + sourceSkip)
                    remaining = 0
                }
            }
        }
        for pending in result.strips {
            let remaining = max(0, maximumBodyHeight - updated.bodyPixelHeight)
            let count = min(pending.image.height, remaining)
            guard count > 0 else { break }
            // At a quota boundary the retained rows must touch the existing
            // seam: bottom of a prepended head, top of an appended tail.
            let skipped = pending.placement == .prepend ? pending.image.height - count : 0
            let bodyHeightBefore = updated.bodyPixelHeight
            let seam = pending.isInitial ? nil : selectCaptureSeam(for: pending, admittedRows: count,
                manifest: updated, eligible: result.status == .advanced,
                quotaLimited: count < pending.image.height || count == remaining, enabled: seamSelectionEnabled)
            let shift = seam?.shift ?? 0
            let sourceTop = pending.sourceTopPixel + skipped - (pending.placement == .append ? shift : 0)
            let image: CGImage?
            if shift > 0, let full = pending.fullImage {
                image = full.cropping(to: CGRect(x: 0, y: sourceTop, width: full.width, height: count + shift))
            } else {
                image = pending.image.cropping(to: CGRect(x: 0, y: skipped, width: pending.image.width, height: count))
            }
            guard let image else {
                throw CaptureStorageError.imageEncodingFailed
            }
            if shift > 0 { try trimRetainedBody(shift, prepend: pending.placement == .prepend) }
            let strip = try encode(image, sourceTop: sourceTop)
            if pending.placement == .prepend {
                let index = updated.leadingEdgeStripID == nil ? 0 : 1
                updated.strips.insert(strip, at: index)
            } else {
                let index = updated.trailingEdgeStripID == nil ? updated.strips.count : updated.strips.count - 1
                updated.strips.insert(strip, at: index)
            }
            if let full = pending.fullImage {
                if pending.isInitial || pending.placement == .prepend {
                    try replaceEdge(image: full, rows: (sourceTop - pending.topInset)..<sourceTop, leading: true)
                }
                if pending.isInitial || pending.placement == .append {
                    let end = sourceTop + count + shift
                    try replaceEdge(image: full, rows: end..<(end + pending.bottomInset), leading: false)
                }
            }
            guard updated.bodyPixelHeight == bodyHeightBefore + count else { throw CaptureStorageError.invalidManifest }
            if let seam {
                if updated.diagnostics == nil { updated.diagnostics = .init() }
                var history = updated.diagnostics?.seams ?? .init()
                history.record(seam.record)
                updated.diagnostics?.seams = history
            }
            if !pending.isInitial { updated.outputKind = .stitched }
            if updated.bodyPixelHeight >= maximumBodyHeight { break }
        }
        guard newURLs.count > 0 else { return updated.bodyPixelHeight >= maximumBodyHeight }
        updated.updatedAt = Date(); updated.provisionalFrame = nil
        try saveManifest(updated)
        committed = true
        if let candidate = publishedCandidate,
           let url = try? stripURL(candidate, sessionID: manifest.id) { try? FileManager.default.removeItem(at: url) }
        let retained = Set(updated.strips.map(\.id))
        // Include transient edge files created earlier in this same transaction.
        let retainedURLs = Set(try updated.strips.map { try stripURL($0, sessionID: updated.id) })
        for old in manifest.strips where !retained.contains(old.id) {
            if let url = try? stripURL(old, sessionID: manifest.id) { try? FileManager.default.removeItem(at: url) }
        }
        for url in newURLs where !retainedURLs.contains(url) { try? FileManager.default.removeItem(at: url) }
        manifest = updated
        return updated.bodyPixelHeight >= maximumBodyHeight
    }

    static func writeImage(_ image: CGImage, to url: URL, format: CaptureExportFormat) throws {
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let type = format == .png ? UTType.png.identifier : UTType.jpeg.identifier
        guard let destination = CGImageDestinationCreateWithURL(temporaryURL as CFURL, type as CFString, 1, nil)
        else { throw CaptureStorageError.imageEncodingFailed }
        let properties: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.93] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CaptureStorageError.imageEncodingFailed }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: temporaryURL.path)
        #endif
        // Unique destination names ensure neither strips nor earlier exports are overwritten.
        try FileManager.default.moveItem(at: temporaryURL, to: url)
    }
}

/// Renders one source strip at a time into a bounded output bitmap. No giant source composite is created.
public final class CaptureImageRenderer: @unchecked Sendable {
    private let repository: CaptureSessionRepository
    public init(repository: CaptureSessionRepository) { self.repository = repository }

    public func preview(sessionID: UUID, maxDimension: Int = 1_800,
                        editsOverride: CaptureEditMetadata? = nil) throws -> UIImage {
        var manifest = try repository.loadSession(id: sessionID)
        if let editsOverride {
            try repository.validateEdits(editsOverride, strips: manifest.strips)
            manifest.edits = editsOverride
        }
        let bounds = try sourceBounds(manifest)
        let maximum = CGFloat(max(64, min(maxDimension, 4_096)))
        let scale = min(1, maximum / max(bounds.width, bounds.height))
        let dimensions = CaptureRenderDimensions(pixelWidth: max(1, Int(floor(bounds.width * scale))),
                                                 pixelHeight: max(1, Int(floor(bounds.height * scale))),
                                                 wasDownscaled: scale < 1)
        return try render(manifest, bounds: bounds, dimensions: dimensions)
    }

    public func outputDimensions(sessionID: UUID, maxPixelCount: Int = 32_000_000,
                                 allowDownscale: Bool = false) throws -> CaptureRenderDimensions {
        let bounds = try sourceBounds(repository.loadSession(id: sessionID))
        return try exportDimensions(bounds: bounds, maxPixelCount: maxPixelCount, allowDownscale: allowDownscale)
    }

    /// Exports never overwrite source strips or previous exports. Oversized images require explicit consent to downscale.
    public func export(sessionID: UUID, format: CaptureExportFormat = .png, maxPixelCount: Int = 32_000_000,
                       allowDownscale: Bool = false) throws -> URL {
        let manifest = try repository.loadSession(id: sessionID)
        guard manifest.status != .capturing else { throw CaptureStorageError.sessionStillActive }
        let bounds = try sourceBounds(manifest)
        let dimensions = try exportDimensions(bounds: bounds, maxPixelCount: maxPixelCount, allowDownscale: allowDownscale)
        let rendered = try render(manifest, bounds: bounds, dimensions: dimensions)
        guard let image = rendered.cgImage else { throw CaptureStorageError.imageEncodingFailed }
        let directory = repository.sessionDirectory(id: sessionID).appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suffix = format == .png ? "png" : "jpg"
        let url = directory.appendingPathComponent("Longlet-\(UUID().uuidString).\(suffix)")
        try CaptureSessionRepository.writeImage(image, to: url, format: format)
        return url
    }

    private func sourceBounds(_ manifest: CaptureSessionManifest) throws -> CGRect {
        guard manifest.pixelWidth > 0, manifest.editedPixelHeight > 0 else { throw CaptureStorageError.noImage }
        let full = CGRect(x: 0, y: 0, width: manifest.pixelWidth, height: manifest.editedPixelHeight)
        guard let crop = manifest.edits.crop else { return full }
        let bounds = normalizedRect(crop, fullSize: full.size).integral.intersection(full)
        guard !bounds.isNull, !bounds.isEmpty, bounds.width.isFinite, bounds.height.isFinite else {
            throw CaptureStorageError.invalidEdits
        }
        return bounds
    }

    private func exportDimensions(bounds: CGRect, maxPixelCount: Int,
                                  allowDownscale: Bool) throws -> CaptureRenderDimensions {
        guard maxPixelCount > 0 else { throw CaptureStorageError.exportTooLarge }
        let limit = CGFloat(min(maxPixelCount, 32_000_000))
        let scale = min(1, sqrt(limit / (bounds.width * bounds.height)),
                        32_000 / max(bounds.width, bounds.height))
        guard scale >= 1 || allowDownscale else { throw CaptureStorageError.exportTooLarge }
        return .init(pixelWidth: max(1, Int(floor(bounds.width * scale))),
                     pixelHeight: max(1, Int(floor(bounds.height * scale))), wasDownscaled: scale < 1)
    }

    private func render(_ manifest: CaptureSessionManifest, bounds: CGRect,
                        dimensions: CaptureRenderDimensions) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: dimensions.pixelWidth, height: dimensions.pixelHeight)
        var failure: Error?
        let result = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            let canvas = context.cgContext
            canvas.saveGState()
            canvas.scaleBy(x: size.width / bounds.width, y: size.height / bounds.height)
            canvas.translateBy(x: -bounds.minX, y: -bounds.minY)
            var y = 0
            for strip in manifest.strips {
                let trim = manifest.edits.seamTrimPixels[strip.id.uuidString] ?? 0
                let remainingHeight = strip.pixelHeight - trim
                let target = CGRect(x: 0, y: y, width: strip.pixelWidth, height: remainingHeight)
                defer { y += remainingHeight }
                guard target.intersects(bounds) else { continue }
                do {
                    try autoreleasepool {
                        let url = try repository.stripURL(strip, sessionID: manifest.id)
                        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                              image.width == strip.pixelWidth, image.height == strip.pixelHeight,
                              let cropped = image.cropping(to: CGRect(x: 0, y: trim,
                                                                     width: image.width, height: remainingHeight))
                        else { throw CaptureStorageError.invalidManifest }
                        UIImage(cgImage: cropped).draw(in: target)
                    }
                } catch { failure = error; break }
            }
            canvas.restoreGState()
            // Mask in destination pixel coordinates, rounded outward. Scaled source-space masks can
            // antialias their edges and leave underlying sensitive pixels partially visible.
            canvas.setShouldAntialias(false)
            canvas.setAllowsAntialiasing(false)
            canvas.setBlendMode(.copy)
            canvas.setFillColor(UIColor.black.cgColor)
            for redaction in manifest.edits.redactions {
                let rect = normalizedRect(redaction, fullSize: CGSize(width: manifest.pixelWidth,
                                                                       height: manifest.editedPixelHeight)).integral
                let scaleX = size.width / bounds.width, scaleY = size.height / bounds.height
                var outputRect = CGRect(x: (rect.minX - bounds.minX) * scaleX,
                                        y: (rect.minY - bounds.minY) * scaleY,
                                        width: rect.width * scaleX, height: rect.height * scaleY).integral
                if scaleX < 1 || scaleY < 1 {
                    // Cover the adjacent output pixels participating in image resampling.
                    outputRect = outputRect.insetBy(dx: -2, dy: -2)
                }
                canvas.fill(outputRect)
            }
        }
        if let failure { throw failure }
        return result
    }

    private func normalizedRect(_ rectangle: NormalizedRect, fullSize: CGSize) -> CGRect {
        CGRect(x: rectangle.x * fullSize.width, y: rectangle.y * fullSize.height,
               width: rectangle.width * fullSize.width, height: rectangle.height * fullSize.height)
    }
}
#endif
