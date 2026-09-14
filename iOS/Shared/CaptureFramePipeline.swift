#if canImport(UIKit)
import CoreGraphics
import CoreImage
import ImageIO
import ScrollCaptureCore

struct PendingCaptureStrip {
    let image: CGImage
    let sourceTopPixel: Int
    let placement: StitchDecision.Placement
    /// Automatic matching insets never authorize losing outer screen pixels.
    /// The repository preserves these edges once and replaces the advancing end
    /// in the same atomic manifest commit as its adjoining content.
    let fullImage: CGImage?
    let topInset: Int
    let bottomInset: Int
    let isInitial: Bool

    init(image: CGImage, sourceTopPixel: Int, placement: StitchDecision.Placement = .append,
         fullImage: CGImage? = nil, topInset: Int = 0, bottomInset: Int = 0, isInitial: Bool = false) {
        self.image = image; self.sourceTopPixel = sourceTopPixel; self.placement = placement
        self.fullImage = fullImage; self.topInset = topInset; self.bottomInset = bottomInset
        self.isInitial = isInitial
    }
}

struct CaptureFrameResult {
    let status: StitchDecision.Status
    let strips: [PendingCaptureStrip]
    let isArming: Bool
    let replacedProvisionalStart: Bool
    let regionWarning: String?
    init(status: StitchDecision.Status, strips: [PendingCaptureStrip], isArming: Bool,
         replacedProvisionalStart: Bool = false, regionWarning: String? = nil) {
        self.status = status; self.strips = strips; self.isArming = isArming
        self.replacedProvisionalStart = replacedProvisionalStart; self.regionWarning = regionWarning
    }
}

/// One provisional lossless still file, bounded grayscale evidence, and no
/// untrusted bridge. A rejected frame never becomes a reference after stitching starts.
final class CaptureFramePipeline {
    let configuration: AlignmentConfiguration
    private(set) var effectiveConfiguration: AlignmentConfiguration
    private var stitcher: StreamStitcher
    private var probes: [StreamStitcher] = []
    private var candidateURL: URL?
    private let candidateRepository: CaptureSessionRepository?
    private let candidateSessionID: UUID?
    private var firstCommitConfirmed = false
    private(set) var provisionalFrame: CaptureStrip?
    private var candidateAnalysis: GrayFrame?
    private var armingRejections = 0
    private var wasRejected = false
    private(set) var hasStarted = false
    private(set) var diagnostics = CaptureDiagnostics()
    private var automaticallyFindRegion: Bool { configuration.topInset == 0 && configuration.bottomInset == 0 }

    init(configuration: AlignmentConfiguration, repository: CaptureSessionRepository? = nil, sessionID: UUID? = nil) {
        self.configuration = configuration; self.effectiveConfiguration = configuration
        self.stitcher = StreamStitcher(configuration: configuration)
        self.candidateRepository = repository; self.candidateSessionID = sessionID
    }

    deinit { clearCandidate() }

    func ingest(_ analysis: GrayFrame, makeImage: () throws -> CGImage) throws -> CaptureFrameResult {
        diagnostics.observedFrames += 1
        if candidateAnalysis == nil && !hasStarted {
            return try arm(analysis, replaced: false, makeImage: makeImage)
        }
        var updated = stitcher
        let automaticArming = !hasStarted && automaticallyFindRegion
        // Automatic arming is verified by regional probes and a full replay;
        // matching the uncropped whole screen here repeats an unused search.
        var decision = automaticArming
            ? StitchDecision(status: .rejected, sourceRows: nil, contentOffset: 0, furthestOffset: 0,
                             confidence: 0, rejection: .insufficientOverlap)
            : updated.ingest(analysis)
        if automaticArming {
            var hypotheses: [StitchDecision] = []
            var checkedOffsets: Set<Int> = []
            var verifiedOffsets: [Int: VerifiedStart] = [:]
            var accepted: [VerifiedStart] = []
            for probe in probes {
                var copy = probe
                let hypothesis = copy.ingest(analysis)
                hypotheses.append(hypothesis)
                guard hypothesis.status == .advanced else { continue }
                if checkedOffsets.insert(hypothesis.contentOffset).inserted {
                    if checkedOffsets.count == 1 { diagnostics.regionAttempts += 1 }
                    if let verified = verifyStart(analysis, displacement: hypothesis.contentOffset) {
                        verifiedOffsets[hypothesis.contentOffset] = verified
                    }
                }
                if let verified = verifiedOffsets[hypothesis.contentOffset] { accepted.append(verified) }
                // A keyboard can produce a plausible but wrong probe offset.
                // Only offsets independently replayed in a moving region may
                // vote or conflict; raw probe guesses never authorize a join.
                let offsets = Set(accepted.map { $0.decision.contentOffset })
                if offsets.count > 1 { return reject(arming: true, region: true) }
                if accepted.count >= 2 { break }
            }
            if let verified = accepted.first {
                updated = verified.stitcher; decision = verified.decision
                effectiveConfiguration = verified.configuration
            } else if !hypotheses.isEmpty, hypotheses.allSatisfy({ $0.status == .unchanged }) {
                armingRejections = 0
                return .init(status: .unchanged, strips: [], isArming: true)
            } else if !checkedOffsets.isEmpty {
                // Preserve the original frame while there is a motion
                // hypothesis whose region is still uncertain.
                return reject(arming: true, region: true)
            }
            // One stationary local patch does not make the whole frame still.
            // Mixed unchanged/rejected windows take the existing bounded
            // scene-replacement path, with its visible starting-point warning.
        }
        if decision.status == .rejected {
            if !hasStarted {
                armingRejections += 1
                // Ignore isolated countdown/loading/transition frames. A new
                // scene must persist through several admitted samples before
                // replacing the provisional starting point.
                if armingRejections >= 3 {
                    return try arm(analysis, replaced: true, makeImage: makeImage)
                }
            }
            return reject(arming: !hasStarted, region: false)
        }
        armingRejections = 0
        if decision.status == .unchanged {
            if hasStarted { stitcher = updated }
            recoveredIfNeeded()
            return .init(status: .unchanged, strips: [], isArming: !hasStarted)
        }
        guard let rows = decision.sourceRows, !rows.isEmpty else {
            stitcher = updated; recoveredIfNeeded()
            return .init(status: decision.status, strips: [], isArming: !hasStarted)
        }
        let region = effectiveConfiguration
        var strips: [PendingCaptureStrip] = []
        if !hasStarted {
            guard let candidateImage = loadCandidate(),
                  let first = candidateImage.cropping(to: CGRect(x: 0, y: region.topInset,
                      width: candidateImage.width, height: candidateImage.height - region.topInset - region.bottomInset))
            else { throw CaptureStorageError.imageEncodingFailed }
            strips.append(.init(image: first, sourceTopPixel: region.topInset,
                                fullImage: automaticallyFindRegion ? candidateImage : nil,
                                topInset: region.topInset, bottomInset: region.bottomInset, isInitial: true))
        }
        let image = try makeImage()
        guard image.height == analysis.height,
              let added = image.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: image.width, height: rows.count))
        else { throw CaptureStorageError.imageEncodingFailed }
        strips.append(.init(image: added, sourceTopPixel: rows.lowerBound, placement: decision.placement,
                            fullImage: automaticallyFindRegion ? image : nil,
                            topInset: region.topInset, bottomInset: region.bottomInset))
        hasStarted = true; candidateAnalysis = nil; probes.removeAll()
        stitcher = updated; diagnostics.acceptedFrames += 1; diagnostics.lastStage = "stitching"
        recoveredIfNeeded()
        return .init(status: decision.status, strips: strips, isArming: false)
    }

    /// This is explicitly a single screen fallback, never evidence of a long image.
    func takeSingleFrameFallback() -> CGImage? {
        guard !firstCommitConfirmed else { return nil }
        defer { clearCandidate(); candidateAnalysis = nil; probes.removeAll() }
        return loadCandidate()
    }

    private func arm(_ analysis: GrayFrame, replaced: Bool,
                     makeImage: () throws -> CGImage) throws -> CaptureFrameResult {
        // Stage the new still before releasing the old one. A rendering or
        // write failure during an app switch leaves the last usable candidate.
        let oldURL = candidateURL
        let url: URL
        if let repository = candidateRepository, let sessionID = candidateSessionID {
            let candidate = try autoreleasepool {
                try repository.stageProvisionalFrame(image: makeImage(), sessionID: sessionID)
            }
            provisionalFrame = candidate
            url = try repository.stripURL(candidate, sessionID: sessionID)
        } else {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("Longlet-Candidate-\(UUID().uuidString).png")
            try autoreleasepool { try CaptureSessionRepository.writeImage(makeImage(), to: url, format: .png) }
        }
        candidateURL = url
        if candidateRepository == nil, let oldURL { try? FileManager.default.removeItem(at: oldURL) }
        candidateAnalysis = analysis; armingRejections = 0
        stitcher = StreamStitcher(configuration: configuration); _ = stitcher.ingest(analysis)
        let windows = [
            (analysis.height / 5, analysis.height / 5),
            (analysis.height / 8, analysis.height / 8),
            // Chat keyboards occupy the lower third to half of a screen.
            // Search the upper body as well as symmetric central windows.
            (analysis.height / 10, analysis.height * 2 / 5),
            (analysis.height / 10, analysis.height / 2),
            (analysis.height / 3, analysis.height / 3)
        ]
        probes = windows.map { top, bottom in
            var region = configuration; region.topInset = top; region.bottomInset = bottom
            var probe = StreamStitcher(configuration: region); _ = probe.ingest(analysis); return probe
        }
        diagnostics.lastStage = "arming"
        if replaced { diagnostics.provisionalReplacements += 1 }
        return .init(status: .started, strips: [], isArming: true, replacedProvisionalStart: replaced)
    }

    private struct VerifiedStart {
        let stitcher: StreamStitcher
        let decision: StitchDecision
        let configuration: AlignmentConfiguration
    }

    private func verifyStart(_ analysis: GrayFrame, displacement: Int) -> VerifiedStart? {
        guard let candidateAnalysis else { return nil }
        let candidates = FixedRegionDetector.candidates(reference: candidateAnalysis, current: analysis,
                                                        displacement: displacement)
        for insets in candidates {
            var region = configuration
            region.topInset = insets.top; region.bottomInset = insets.bottom
            var replay = StreamStitcher(configuration: region)
            guard replay.ingest(candidateAnalysis).status == .started else { continue }
            let result = replay.ingest(analysis)
            if result.status == .advanced, result.contentOffset == displacement {
                return VerifiedStart(stitcher: replay, decision: result, configuration: region)
            }
        }
        return nil
    }

    private func loadCandidate() -> CGImage? {
        guard let candidateURL,
              let source = CGImageSourceCreateWithURL(candidateURL as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// Call only after the corresponding repository transaction has succeeded.
    /// Until then, even a detected first scroll can fall back to its durable still.
    func confirmCommit() {
        guard hasStarted else { return }
        firstCommitConfirmed = true; clearCandidate(); provisionalFrame = nil
    }

    private func clearCandidate() {
        // App Group candidates are owned by the atomic manifest transaction;
        // destroying this pipeline or a failed fallback must not delete them.
        if candidateRepository == nil, let candidateURL { try? FileManager.default.removeItem(at: candidateURL) }
        candidateURL = nil
    }

    private func reject(arming: Bool, region: Bool) -> CaptureFrameResult {
        wasRejected = true; diagnostics.rejectedFrames += 1
        diagnostics.lastStage = region ? "region" : "alignment"
        return .init(status: .rejected, strips: [], isArming: arming,
                     regionWarning: region ? "正在确认滚动区域，请缓慢滚动并等待画面稳定。" : nil)
    }

    private func recoveredIfNeeded() {
        if wasRejected { diagnostics.recoveredGaps += 1; wasRejected = false }
    }
}

/// Shared by the real capture adapters and host tests. CGImage crop rows and
/// GrayFrame pixels both use the CGImage's top-to-bottom provider row order.
/// Core Image's bottom-left coordinate system is confined to createCGImage.
enum CaptureFrameConversion {
    static func grayFrame(_ source: CIImage, context imageContext: CIContext,
                          width: Int, height: Int) throws -> GrayFrame {
        let normalized = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX,
                                                                  y: -source.extent.minY))
        let resized = normalized.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / normalized.extent.width,
                                                                   y: CGFloat(height) / normalized.extent.height))
        guard width > 0, height > 0,
              let image = imageContext.createCGImage(resized, from: CGRect(x: 0, y: 0, width: width, height: height)),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0),
              let bytes = context.data else { throw CaptureStorageError.imageEncodingFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try GrayFrame(width: width, height: height,
                             pixels: Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self),
                                                               count: width * height)))
    }
}
#endif
