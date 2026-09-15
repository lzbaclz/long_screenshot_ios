#if CAPTUREKIT_IOS27 && os(iOS)
@preconcurrency import ScreenCaptureKit
import CoreImage
import CoreMedia
import Foundation
import ImageIO
import ScrollCaptureCore

struct ScreenCaptureKit27Outcome: Sendable {
    let manifest: CaptureSessionManifest
    let persistenceError: String?
}

/// Experimental lifetime wrapper deliberately separated from ReplayKit until SDK/device validation.
/// Stream callbacks and the heartbeat share one serial queue. No sample leaves its output callback.
@available(iOS 27.0, *)
final class ScreenCaptureKit27FrameSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.lzbaclz.longscreenshot.sck27.frames", qos: .userInitiated)
    let sessionID: UUID
    private let repository: CaptureSessionRepository
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let onFinish: @Sendable (ScreenCaptureKit27Outcome) -> Void
    private var manifest: CaptureSessionManifest
    private var lease: CaptureSessionLease?
    private var pipeline: CaptureFramePipeline?
    private var timer: DispatchSourceTimer?
    private var outcome: ScreenCaptureKit27Outcome?
    private var lifecycle = CaptureLifecyclePolicy(startedAt: ProcessInfo.processInfo.systemUptime)
    private var adapterTimings = CaptureStageTimings()
    private var maximumProcessingMilliseconds = 0.0
    private var skippedSamples = 0
    private var lastFrameUptime = 0.0
    private var lastMotionActiveTime = 0.0
    private var continuity = CaptureContinuityPolicy()
    private var stoppedFrameUptime: Double?
    private var didMove = false
    private var initialOrientation: Int32?
    private var originalWidth = 0
    private var originalHeight = 0

    init(repository: CaptureSessionRepository, configuration: CaptureConfiguration,
         onFinish: @escaping @Sendable (ScreenCaptureKit27Outcome) -> Void) throws {
        self.repository = repository
        self.onFinish = onFinish
        let created = try repository.createSession(configuration: configuration)
        self.manifest = created; self.sessionID = created.id
        self.lease = try repository.acquireSessionLease(id: created.id)
        super.init()
        queue.async { [weak self] in self?.startHeartbeat() }
    }

    deinit { timer?.cancel() }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard type == .screen, outcome == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let values = attachments.first,
              let raw = values[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else {
            registerRejection(now: now)
            return
        }
        switch status {
        case .idle: return
        case .stopped:
            // Wait briefly for the delegate's userStopped code so an intentional system stop
            // is not mislabelled as an interruption. A missing delegate is bounded by the heartbeat.
            if stoppedFrameUptime == nil { stoppedFrameUptime = now }
            return
        case .blank, .suspended:
            if lifecycle.pause(at: now, requiresOverlap: pipeline?.hasReference == true) {
                continuity.accept(); imageContext.clearCaches()
                refreshDiagnostics(stage: "paused"); persistLifecycleSnapshot()
            }
            return
        case .complete, .started:
            if lifecycle.resume(at: now) {
                continuity.accept(); lastFrameUptime = 0
                lastMotionActiveTime = lifecycle.activeElapsed(at: now)
                refreshDiagnostics(stage: lifecycle.needsOverlapAfterResume ? "awaitingResumeOverlap" : "arming")
                persistLifecycleSnapshot()
            }
        @unknown default:
            registerRejection(now: now); return
        }
        guard stoppedFrameUptime == nil else { return }
        guard lifecycle.canProcessFrames, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard now - lastFrameUptime >= 0.15 else { skippedSamples += 1; return }
        defer {
            maximumProcessingMilliseconds = max(maximumProcessingMilliseconds,
                (ProcessInfo.processInfo.systemUptime - now) * 1_000)
            refreshDiagnostics()
        }
        lastFrameUptime = now
        let orientation = (values[.videoOrientation] as? NSNumber)?.int32Value ?? 1
        do {
            try autoreleasepool { try process(sampleBuffer, orientation: orientation, now: now) }
        } catch {
            refreshDiagnostics(); manifest.diagnostics?.terminationCause = "processingError"
            _ = finishOnQueue(reason: error.localizedDescription, partial: true)
        }
    }

    func finish(reason: String, partial: Bool) async -> ScreenCaptureKit27Outcome {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.finishOnQueue(reason: reason, partial: partial)) }
        }
    }

    private func process(_ sample: CMSampleBuffer, orientation: Int32, now: Double) throws {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { registerRejection(now: now); return }
        guard (1...8).contains(orientation) else { registerRejection(now: now); return }
        if let initialOrientation, initialOrientation != orientation,
           !manifest.strips.isEmpty || lifecycle.needsOverlapAfterResume {
            _ = finishOnQueue(reason: "屏幕方向改变，已保存旋转前的内容。请重新开始下一段。", partial: true)
            return
        }
        initialOrientation = orientation
        let oriented = CIImage(cvPixelBuffer: buffer).oriented(forExifOrientation: orientation)
        let source = oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX,
                                                               y: -oriented.extent.minY))
        let width = Int(source.extent.width), height = Int(source.extent.height)
        guard width > 0, height > 0, width <= 4_096, height <= 4_096, width * height <= 9_000_000 else {
            throw CaptureStorageError.exportTooLarge
        }
        if originalWidth != 0 && (originalWidth != width || originalHeight != height) {
            guard manifest.strips.isEmpty, !lifecycle.needsOverlapAfterResume else {
                _ = finishOnQueue(reason: "画面尺寸发生变化，已保存变化前的内容。", partial: true); return
            }
            pipeline = nil
        }
        originalWidth = width; originalHeight = height
        let configuration = manifest.configuration
        let top = Int(Double(height) * configuration.captureTopInsetFraction)
        let bottom = Int(Double(height) * configuration.captureBottomInsetFraction)
        if pipeline == nil {
            pipeline = .init(configuration: .init(topInset: top, bottomInset: bottom),
                             repository: repository, sessionID: manifest.id)
        }
        guard let pipeline else { return }
        refreshDiagnostics(stage: "frameConversion")
        let gray = try measure(.grayConversion) {
            try CaptureFrameConversion.grayFrame(source, context: imageContext, width: min(144, width), height: height)
        }
        let result = try pipeline.ingest(gray,
            allowProvisionalReplacement: !lifecycle.needsOverlapAfterResume) {
            guard let image = imageContext.createCGImage(source, from: source.extent) else {
                throw CaptureStorageError.imageEncodingFailed
            }
            return image
        }
        manifest.provisionalFrame = pipeline.provisionalFrame
        if result.replacedProvisionalStart {
            manifest.startWarning = "画面变化后重新确定了起点，请检查图片开头是否完整。"
        }
        refreshDiagnostics(stage: pipeline.diagnostics.lastStage)
        if result.status == .rejected { registerRejection(now: now); return }
        let trusted = result.status == .advanced || result.status == .backtracked || result.status == .unchanged
        if trusted, lifecycle.verifiedFrame(at: now) {
            lastMotionActiveTime = lifecycle.activeElapsed(at: now); refreshDiagnostics()
        }
        if !result.isArming && (result.status == .advanced || result.status == .backtracked) {
            didMove = true; lastMotionActiveTime = lifecycle.activeElapsed(at: now)
        }
        if !result.strips.isEmpty {
            let region = pipeline.effectiveConfiguration
            let maximumHeight = configuration.maximumBodyPixelHeight(frameHeight: height,
                matchingTopInset: region.topInset, matchingBottomInset: region.bottomInset)
            refreshDiagnostics(stage: "storage")
            let reachedLimit = try measure(.stripCommit) {
                try repository.commit(result, maximumBodyHeight: maximumHeight, to: &manifest)
            }
            pipeline.confirmCommit(); refreshDiagnostics(stage: "storage")
            if reachedLimit {
                _ = finishOnQueue(reason: "已达到设置的 \(configuration.maximumScreenCount) 屏上限。", partial: false)
                return
            }
        }
        continuity.accept()
    }

    private func registerRejection(now: Double) {
        lifecycle.rejectedFrame()
        manifest.rejectedFrameCount += 1
        lastMotionActiveTime = lifecycle.activeElapsed(at: now)
        let resuming = lifecycle.needsOverlapAfterResume
        if continuity.reject(at: lifecycle.activeElapsed(at: now), hasStarted: pipeline?.hasStarted == true || resuming) {
            manifest.diagnostics?.terminationCause = resuming ? "resumeOverlap" : "continuity"
            let reason = resuming
                ? "恢复后的画面无法可靠衔接，已保留暂停前的画面。请重新开始下一段。"
                : "画面暂时无法连续衔接，已保存已确认的连续长图。请降低滑动速度后重试。"
            _ = finishOnQueue(reason: reason, partial: true)
        }
    }

    private func startHeartbeat() {
        guard outcome == nil else { return }
        let heartbeat = DispatchSource.makeTimerSource(queue: queue)
        heartbeat.schedule(deadline: .now() + 1, repeating: 1)
        heartbeat.setEventHandler { [weak self] in self?.heartbeat() }
        timer = heartbeat; heartbeat.resume()
    }

    private func heartbeat() {
        guard outcome == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let stoppedFrameUptime, now - stoppedFrameUptime >= 2 {
            manifest.diagnostics?.terminationCause = "systemStop"
            _ = finishOnQueue(reason: "捕捉已由系统结束。", partial: false); return
        }
        if repository.hasStopRequest(id: sessionID) {
            manifest.diagnostics?.terminationCause = "manual"
            _ = finishOnQueue(reason: "已手动结束捕捉。", partial: false); return
        }
        if lifecycle.state != .paused, lifecycle.activeElapsed(at: now) >= manifest.configuration.maximumDurationSeconds {
            manifest.diagnostics?.terminationCause = "duration"
            _ = finishOnQueue(reason: "已达到设置的时长上限。", partial: false); return
        }
        if didMove, lifecycle.canStopForIdle, !continuity.isAwaitingBridge,
           let idle = manifest.configuration.idleStopSeconds,
           lifecycle.activeElapsed(at: now) - lastMotionActiveTime >= idle {
            manifest.diagnostics?.terminationCause = "idle"
            _ = finishOnQueue(reason: "停止滑动 \(Int(idle)) 秒，已完成捕捉。", partial: false); return
        }
        refreshDiagnostics(stage: lifecycle.state == .paused ? "paused" : nil)
        manifest.updatedAt = Date()
        do { try measure(.manifestWrite) { try repository.saveManifest(manifest) } }
        catch {
            if lifecycle.state == .paused { refreshDiagnostics(stage: "storage") }
            else {
                refreshDiagnostics(stage: "storage"); manifest.diagnostics?.recordStorageFailure()
                _ = finishOnQueue(reason: error.localizedDescription, partial: true)
            }
        }
    }

    private func finishOnQueue(reason: String, partial: Bool) -> ScreenCaptureKit27Outcome {
        if let outcome { return outcome }
        let finalPartial = partial || lifecycle.hasUnverifiedContent
        _ = lifecycle.finish(at: ProcessInfo.processInfo.systemUptime)
        refreshDiagnostics()
        if manifest.diagnostics?.terminationCause == nil {
            manifest.diagnostics?.terminationCause = reason == "已手动结束捕捉。" ? "manual" : partial ? "systemInterruption" : "systemStop"
        }
        refreshDiagnostics()
        timer?.cancel(); timer = nil
        var finalReason = reason
        if manifest.strips.isEmpty {
            do {
                let preserved = try repository.preserveProvisionalFrame(to: &manifest)
                if !preserved, let fallback = pipeline?.takeSingleFrameFallback() {
                    manifest.outputKind = .singleFrame
                    try repository.appendStrip(image: fallback, to: &manifest)
                }
            } catch {
                manifest.diagnostics?.recordStorageFailure(); finalReason = error.localizedDescription
            }
        }
        manifest.finalizeCapture(reason: finalReason, partial: finalPartial)
        var persistenceError: String?
        do { try measure(.manifestWrite) { try repository.saveManifest(manifest) } }
        catch {
            persistenceError = error.localizedDescription
            manifest.diagnostics?.recordStorageFailure()
            manifest.status = .partial; manifest.stopReason = error.localizedDescription
        }
        let result = ScreenCaptureKit27Outcome(manifest: manifest, persistenceError: persistenceError)
        outcome = result; pipeline = nil; imageContext.clearCaches(); lease = nil
        onFinish(result)
        return result
    }
    private func measure<T>(_ stage: CaptureProcessingStage, _ operation: () throws -> T) rethrows -> T {
        let start = ProcessInfo.processInfo.systemUptime
        defer { adapterTimings.record(stage, seconds: ProcessInfo.processInfo.systemUptime - start) }
        return try operation()
    }

    private func refreshDiagnostics(stage: String? = nil) {
        let cause = manifest.diagnostics?.terminationCause
        let lastStage = stage ?? manifest.diagnostics?.lastStage
        let pipelineTimings = pipeline?.diagnostics.stageTimings ?? manifest.diagnostics?.stageTimings
        var stats = pipeline?.diagnostics ?? manifest.diagnostics ?? .init()
        stats.seams = manifest.diagnostics?.seams
        stats.stageTimings = .combined(pipeline: pipelineTimings, adapter: adapterTimings)
        stats.skippedSamples = skippedSamples; stats.maximumProcessingMilliseconds = maximumProcessingMilliseconds
        stats.lifecycleState = lifecycle.state.rawValue
        stats.pauseCount = lifecycle.pauseCount; stats.resumeCount = lifecycle.resumeCount
        stats.recoveredResumeCount = lifecycle.recoveredResumeCount; stats.terminationCause = cause
        if let lastStage { stats.lastStage = lastStage }
        manifest.diagnostics = stats
    }

    private func persistLifecycleSnapshot() {
        manifest.updatedAt = Date()
        do { try measure(.manifestWrite) { try repository.saveManifest(manifest) } }
        catch { refreshDiagnostics(stage: "storage") }
    }

}
#endif
