#if canImport(UIKit)
import CoreGraphics
import ScrollCaptureCore

struct PendingCaptureStrip {
    let image: CGImage
    let sourceTopPixel: Int
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
        self.replacedProvisionalStart = replacedProvisionalStart
        self.regionWarning = regionWarning
    }
}

/// Before first confirmed scrolling, scene changes replace the provisional start frame.
/// Once started, rejected gaps never replace or extend the trusted sequence.
final class CaptureFramePipeline {
    let configuration: AlignmentConfiguration
    private(set) var effectiveConfiguration: AlignmentConfiguration
    private var stitcher: StreamStitcher
    private var candidateImage: CGImage?
    private var candidateAnalysis: GrayFrame?
    private(set) var hasStarted = false
    private var automaticallyFindRegion: Bool { configuration.topInset == 0 && configuration.bottomInset == 0 }

    init(configuration: AlignmentConfiguration) {
        self.configuration = configuration
        self.effectiveConfiguration = configuration
        self.stitcher = StreamStitcher(configuration: configuration)
    }

    func ingest(_ analysis: GrayFrame, makeImage: () throws -> CGImage) throws -> CaptureFrameResult {
        if !hasStarted && candidateAnalysis == nil && automaticallyFindRegion {
            stitcher = StreamStitcher(configuration: probeConfiguration(height: analysis.height))
        }
        var updated = stitcher
        var decision = updated.ingest(analysis)
        var replacedStart = false
        if !hasStarted && (decision.status == .rejected || decision.status == .backtracked) {
            // App switching and moving to the desired starting point are allowed while arming.
            replacedStart = candidateImage != nil
            updated = StreamStitcher(configuration: automaticallyFindRegion
                ? probeConfiguration(height: analysis.height) : configuration)
            decision = updated.ingest(analysis)
        }
        if !hasStarted && decision.status == .started {
            candidateImage = try makeImage()
            candidateAnalysis = analysis
            stitcher = updated
            return .init(status: .started, strips: [], isArming: true, replacedProvisionalStart: replacedStart)
        }
        if decision.status == .rejected {
            return .init(status: .rejected, strips: [], isArming: !hasStarted)
        }
        if decision.status == .unchanged {
            // Preserve the provisional first frame so its position matches the reference.
            if hasStarted { stitcher = updated }
            return .init(status: .unchanged, strips: [], isArming: !hasStarted)
        }
        if !hasStarted && automaticallyFindRegion && decision.status == .advanced {
            guard let candidateAnalysis,
                  case .resolved(let insets) = FixedRegionDetector.resolve(
                    reference: candidateAnalysis, current: analysis,
                    downwardDisplacement: decision.contentOffset) else { return ambiguousRegion() }
            var resolved = configuration
            resolved.topInset = insets.top; resolved.bottomInset = insets.bottom
            var replay = StreamStitcher(configuration: resolved)
            guard replay.ingest(candidateAnalysis).status == .started else { return ambiguousRegion() }
            let verified = replay.ingest(analysis)
            guard verified.status == .advanced, verified.contentOffset == decision.contentOffset else {
                return ambiguousRegion()
            }
            effectiveConfiguration = resolved
            updated = replay; decision = verified
        }
        guard let rows = decision.sourceRows, !rows.isEmpty else {
            stitcher = updated
            return .init(status: decision.status, strips: [], isArming: !hasStarted)
        }
        var strips: [PendingCaptureStrip] = []
        if !hasStarted {
            guard let candidateImage,
                  let first = candidateImage.cropping(to: CGRect(x: 0, y: effectiveConfiguration.topInset,
                      width: candidateImage.width,
                      height: candidateImage.height - effectiveConfiguration.topInset - effectiveConfiguration.bottomInset)) else {
                throw CaptureStorageError.imageEncodingFailed
            }
            strips.append(.init(image: first, sourceTopPixel: effectiveConfiguration.topInset))
        }
        let image = try makeImage()
        guard let tail = image.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: image.width, height: rows.count))
        else { throw CaptureStorageError.imageEncodingFailed }
        strips.append(.init(image: tail, sourceTopPixel: rows.lowerBound))
        hasStarted = true; candidateImage = nil; candidateAnalysis = nil; stitcher = updated
        return .init(status: decision.status, strips: strips, isArming: false)
    }

    private func probeConfiguration(height: Int) -> AlignmentConfiguration {
        var probe = configuration
        // Discard outer fifths for the initial motion hypothesis only. The
        // source image is cropped only after the separate boundary check.
        probe.topInset = height / 5; probe.bottomInset = height / 5
        return probe
    }

    private func ambiguousRegion() -> CaptureFrameResult {
        .init(status: .rejected, strips: [], isArming: true,
              regionWarning: "无法安全识别固定栏或页面留白。请手动设置顶部和底部忽略区域后重试。")
    }
}
#endif
