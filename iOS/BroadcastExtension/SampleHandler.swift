import CoreImage
import CoreMedia
import ImageIO
import ReplayKit
import ScrollCaptureCore

/// ReplayKit calls are serial; each admitted sample is processed before returning.
/// No CMSampleBuffer escapes its callback and no video/audio file is created.
/// Mutable capture state is confined to processingQueue. The main-queue stop callback
/// only invokes ReplayKit after the queue has finalized all state.
final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
    private let processingQueue = DispatchQueue(label: "dev.lzbaclz.longscreenshot.capture", qos: .userInitiated)
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var repository: CaptureSessionRepository?
    private var manifest: CaptureSessionManifest?
    private var sessionLease: CaptureSessionLease?
    private var framePipeline: CaptureFramePipeline?
    private var timer: DispatchSourceTimer?
    private var lifecycle = CaptureLifecyclePolicy()
    private var adapterTimings = CaptureStageTimings()
    private var activeProcessingStage: String?
    private var lastFrameUptime = 0.0
    private var lastMotionActiveTime = 0.0
    private var continuity = CaptureContinuityPolicy()
    private var skippedSamples = 0
    private var maximumProcessingMilliseconds = 0.0
    private var originalWidth = 0
    private var originalHeight = 0
    private var initialOrientation: Int32?
    private var didMove = false
    private var finished: Bool { lifecycle.isFinished }
    private var persistedStartupStages: Set<String> = []

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        processingQueue.sync {
            do {
                let storage = try CaptureSessionRepository.application()
                _ = try storage.recoverInterruptedSessions()
                let configuration = try storage.loadConfiguration()
                var session = try storage.createSession(configuration: configuration)
                sessionLease = try storage.acquireSessionLease(id: session.id)
                repository = storage; manifest = session
                lifecycle = .init(startedAt: ProcessInfo.processInfo.systemUptime)
                lastMotionActiveTime = 0
                session.diagnostics = CaptureDiagnostics()
                try measure(.manifestWrite) { try storage.saveManifest(session) }; manifest = session
                refreshDiagnostics()
                let heartbeat = DispatchSource.makeTimerSource(queue: processingQueue)
                heartbeat.schedule(deadline: .now() + 1, repeating: 1)
                heartbeat.setEventHandler { [weak self] in self?.heartbeat() }
                timer = heartbeat; heartbeat.resume()
            } catch { terminate(reason: error.localizedDescription, partial: true) }
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Audio is deliberately ignored even if the system microphone switch is enabled.
        guard sampleBufferType == .video else { return }
        processingQueue.sync {
            guard lifecycle.canProcessFrames, let configuration = manifest?.configuration else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastFrameUptime >= 0.15 else { skippedSamples += 1; return }
            defer {
                maximumProcessingMilliseconds = max(maximumProcessingMilliseconds,
                    (ProcessInfo.processInfo.systemUptime - now) * 1_000)
                refreshDiagnostics(stage: activeProcessingStage)
                activeProcessingStage = nil
            }
            lastFrameUptime = now
            do {
                try autoreleasepool { try processVideo(sampleBuffer, configuration: configuration, now: now) }
            } catch {
                let pipelineStage = framePipeline?.diagnostics.lastStage
                if let pipelineStage, ["frameRendering", "provisionalRead", "provisionalWrite"].contains(pipelineStage) {
                    activeProcessingStage = pipelineStage
                }
                refreshDiagnostics(stage: activeProcessingStage)
                manifest?.diagnostics?.terminationCause = "processingError"
                terminate(reason: error.localizedDescription, partial: true)
            }
        }
    }

    override func broadcastPaused() {
        processingQueue.sync {
            let now = ProcessInfo.processInfo.systemUptime
            guard lifecycle.pause(at: now, requiresOverlap: framePipeline?.hasReference == true) else { return }
            // Keep only existing bounded grayscale references and durable PNGs.
            // A pause is not a failure and must not call finishBroadcastWithError.
            continuity.accept(); imageContext.clearCaches()
            refreshDiagnostics(stage: "paused")
            persistLifecycleSnapshot()
        }
    }

    override func broadcastResumed() {
        processingQueue.sync {
            let now = ProcessInfo.processInfo.systemUptime
            guard lifecycle.resume(at: now) else { return }
            lastFrameUptime = 0
            continuity.accept()
            lastMotionActiveTime = lifecycle.activeElapsed(at: now)
            refreshDiagnostics(stage: lifecycle.needsOverlapAfterResume ? "awaitingResumeOverlap" : "arming")
            persistLifecycleSnapshot()
        }
    }

    override func broadcastFinished() {
        processingQueue.sync {
            guard !finished else { return }
            // The public callback does not say whether Control Center or some
            // other system action initiated the stop. Only our stop.request is
            // positively attributable to the app's own manual stop action.
            let requested = manifest.map { repository?.hasStopRequest(id: $0.id) == true } ?? false
            refreshDiagnostics()
            manifest?.diagnostics?.terminationCause = requested ? "manual" : "systemStop"
            finishSession(reason: requested ? "已手动结束捕捉。" : "捕捉已由系统结束。", partial: false)
        }
    }

    private func processVideo(_ sample: CMSampleBuffer, configuration: CaptureConfiguration, now: Double) throws {
        guard let storage = repository, var session = manifest else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else {
            activeProcessingStage = "missingVideoFrame"
            refreshDiagnostics(stage: "missingVideoFrame")
            registerRejection(now: now); return
        }
        let attachment = CMGetAttachment(sample, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil)
        let orientation = (attachment as? NSNumber)?.int32Value ?? 1
        if let initialOrientation, initialOrientation != orientation,
           !session.strips.isEmpty || lifecycle.needsOverlapAfterResume {
            manifest?.diagnostics?.terminationCause = "geometry"
            terminate(reason: "屏幕方向改变，已保存旋转前的内容。请重新开始下一段。", partial: true)
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
            if !session.strips.isEmpty || lifecycle.needsOverlapAfterResume {
                manifest?.diagnostics?.terminationCause = "geometry"
                terminate(reason: "画面尺寸发生变化，已保存变化前的内容。", partial: true); return
            }
            framePipeline = nil
        }
        originalWidth = width; originalHeight = height
        let analysisWidth = min(144, width)
        // Downsample horizontally only. Native-height analysis keeps every seam on an original image row.
        refreshDiagnostics(stage: "frameConversion")
        session.diagnostics = manifest?.diagnostics
        session.diagnostics?.observedFrames += 1
        activeProcessingStage = "frameConversion"
        try checkpointStartup(stage: "frameConversion", storage: storage, session: &session)
        let coarse = try measure(.grayConversion) {
            try CaptureFrameConversion.grayFrame(source, context: imageContext, width: analysisWidth, height: height)
        }
        let top = Int(Double(height) * configuration.captureTopInsetFraction)
        let bottom = Int(Double(height) * configuration.captureBottomInsetFraction)
        if framePipeline == nil {
            framePipeline = .init(configuration: .init(topInset: top, bottomInset: bottom),
                                  repository: storage, sessionID: session.id)
        }
        guard let framePipeline else { return }
        if framePipeline.diagnostics.observedFrames == 0 {
            try checkpointStartup(stage: "provisionalImage", storage: storage, session: &session)
        }
        activeProcessingStage = "alignment"
        let result = try framePipeline.ingest(coarse,
            allowProvisionalReplacement: !lifecycle.needsOverlapAfterResume) {
            guard let image = imageContext.createCGImage(source, from: source.extent) else {
                throw CaptureStorageError.imageEncodingFailed
            }
            return image
        }
        activeProcessingStage = framePipeline.diagnostics.lastStage
        // Arming may atomically publish a provisional still. Merge its new
        // reference before this callback or the heartbeat writes its snapshot.
        session.provisionalFrame = framePipeline.provisionalFrame
        if result.replacedProvisionalStart {
            session.startWarning = "画面变化后重新确定了起点，请检查图片开头是否完整。"
            manifest = session
        }
        manifest = session
        refreshDiagnostics(stage: activeProcessingStage)
        session.diagnostics = manifest?.diagnostics
        if result.status == .rejected {
            registerRejection(now: now); return
        }
        let trusted = result.status == .advanced || result.status == .backtracked || result.status == .unchanged
        if trusted, lifecycle.verifiedFrame(at: now) {
            lastMotionActiveTime = lifecycle.activeElapsed(at: now)
            refreshDiagnostics(); session.diagnostics = manifest?.diagnostics
        }
        if result.status == .unchanged {
            continuity.accept()
            return
        }
        if !result.isArming && (result.status == .advanced || result.status == .backtracked) {
            didMove = true; lastMotionActiveTime = lifecycle.activeElapsed(at: now)
        }
        if !result.strips.isEmpty {
            let region = framePipeline.effectiveConfiguration
            let maximumHeight = configuration.maximumBodyPixelHeight(frameHeight: height,
                matchingTopInset: region.topInset, matchingBottomInset: region.bottomInset)
            try checkpointStartup(stage: "firstCommit", storage: storage, session: &session)
            session.diagnostics?.lastStage = "storage"
            activeProcessingStage = "storage"
            manifest = session
            let reachedLimit = try measure(.stripCommit) {
                try storage.commit(result, maximumBodyHeight: maximumHeight, to: &session)
            }
            framePipeline.confirmCommit()
            manifest = session
            refreshDiagnostics(stage: "storage")
            if reachedLimit {
                manifest?.diagnostics?.terminationCause = "screenLimit"
                terminate(reason: "已达到设置的 \(configuration.maximumScreenCount) 屏上限。", partial: false); return
            }
        }
        continuity.accept()
    }

    /// Only the first passage through an expensive startup stage is persisted.
    /// If the extension disappears before a strip is published, recovery can
    /// identify its last attempted stage without storing pixels or per-frame logs.
    private func checkpointStartup(stage: String, storage: CaptureSessionRepository,
                                   session: inout CaptureSessionManifest) throws {
        guard session.strips.isEmpty, !persistedStartupStages.contains(stage) else { return }
        if session.diagnostics == nil { session.diagnostics = CaptureDiagnostics() }
        session.diagnostics?.lastStage = stage; session.updatedAt = Date()
        manifest = session
        try measure(.manifestWrite) { try storage.saveManifest(session) }
        persistedStartupStages.insert(stage)
    }

    private func registerRejection(now: Double) {
        lifecycle.rejectedFrame()
        manifest?.rejectedFrameCount += 1
        lastMotionActiveTime = lifecycle.activeElapsed(at: now)
        let resuming = lifecycle.needsOverlapAfterResume
        if continuity.reject(at: lifecycle.activeElapsed(at: now),
                             hasStarted: framePipeline?.hasStarted == true || resuming) {
            manifest?.diagnostics?.terminationCause = resuming ? "resumeOverlap" : "continuity"
            let reason = resuming
                ? "恢复后的画面无法可靠衔接，已保留暂停前的画面。请重新开始下一段。"
                : "画面暂时无法连续衔接，已保存已确认的连续长图。请降低滑动速度后重试。"
            terminate(reason: reason, partial: true)
        }
    }

    private func heartbeat() {
        guard !finished, var session = manifest, let storage = repository else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if storage.hasStopRequest(id: session.id) {
            manifest?.diagnostics?.terminationCause = "manual"
            terminate(reason: "已手动结束捕捉。", partial: false); return
        }
        if lifecycle.state != .paused,
           lifecycle.activeElapsed(at: now) >= session.configuration.maximumDurationSeconds {
            manifest?.diagnostics?.terminationCause = "duration"
            terminate(reason: "已达到设置的时长上限。", partial: false); return
        }
        // Initial system countdown/app switching must not trigger idle completion before the user scrolls.
        if didMove, lifecycle.canStopForIdle, !continuity.isAwaitingBridge,
           let idle = session.configuration.idleStopSeconds,
           lifecycle.activeElapsed(at: now) - lastMotionActiveTime >= idle {
            manifest?.diagnostics?.terminationCause = "idle"
            terminate(reason: "停止滑动 \(Int(idle)) 秒，已完成捕捉。", partial: false); return
        }
        refreshDiagnostics(stage: lifecycle.state == .paused ? "paused" : nil)
        session.diagnostics = manifest?.diagnostics; session.updatedAt = Date()
        do { try measure(.manifestWrite) { try storage.saveManifest(session) }; manifest = session }
        catch {
            if lifecycle.state == .paused { refreshDiagnostics(stage: "storage") }
            else {
                refreshDiagnostics(stage: "storage")
                manifest?.diagnostics?.recordStorageFailure()
                terminate(reason: error.localizedDescription, partial: true)
            }
        }
    }

    private func finishSession(reason: String, partial: Bool) {
        let finalPartial = partial || lifecycle.hasUnverifiedContent
        guard lifecycle.finish(at: ProcessInfo.processInfo.systemUptime) else { return }
        timer?.cancel(); timer = nil
        refreshDiagnostics(stage: manifest?.diagnostics?.lastStage)
        if var session = manifest {
            var finalReason = reason
            if session.strips.isEmpty {
                do {
                    let preserved = try repository?.preserveProvisionalFrame(to: &session) ?? false
                    if !preserved, let fallback = framePipeline?.takeSingleFrameFallback() {
                        session.outputKind = .singleFrame
                        try repository?.appendStrip(image: fallback, to: &session)
                    }
                } catch {
                    session.diagnostics?.recordStorageFailure()
                    finalReason = error.localizedDescription
                }
            }
            session.finalizeCapture(reason: finalReason, partial: finalPartial)
            do { try measure(.manifestWrite) { try repository?.saveManifest(session) }; manifest = session }
            catch {
                // The previous atomic manifest survives on disk. Keep the real
                // failure in the terminal callback without replacing its cause.
                session.diagnostics?.recordStorageFailure()
                session.status = .partial; session.stopReason = error.localizedDescription
                manifest = session
            }
        }
        framePipeline = nil; imageContext.clearCaches()
        sessionLease = nil
    }

    private func measure<T>(_ stage: CaptureProcessingStage, _ operation: () throws -> T) rethrows -> T {
        let start = ProcessInfo.processInfo.systemUptime
        defer { adapterTimings.record(stage, seconds: ProcessInfo.processInfo.systemUptime - start) }
        return try operation()
    }

    private func refreshDiagnostics(stage: String? = nil) {
        guard manifest != nil else { return }
        let cause = manifest?.diagnostics?.terminationCause
        let lastStage = stage ?? manifest?.diagnostics?.lastStage
        let pipelineTimings = framePipeline?.diagnostics.stageTimings ?? manifest?.diagnostics?.stageTimings
        var stats = framePipeline?.diagnostics ?? manifest?.diagnostics ?? .init()
        // Seam records describe repository transactions, not alignment plans.
        stats.seams = manifest?.diagnostics?.seams
        stats.stageTimings = .combined(pipeline: pipelineTimings, adapter: adapterTimings)
        stats.skippedSamples = skippedSamples
        stats.maximumProcessingMilliseconds = maximumProcessingMilliseconds
        stats.lifecycleState = lifecycle.state.rawValue
        stats.pauseCount = lifecycle.pauseCount; stats.resumeCount = lifecycle.resumeCount
        stats.recoveredResumeCount = lifecycle.recoveredResumeCount
        stats.terminationCause = cause
        if let lastStage { stats.lastStage = lastStage }
        manifest?.diagnostics = stats
    }

    private func persistLifecycleSnapshot() {
        guard var session = manifest, let repository else { return }
        session.updatedAt = Date()
        do { try measure(.manifestWrite) { try repository.saveManifest(session) }; manifest = session }
        catch {
            // The previous atomic manifest remains intact. A failed metadata
            // checkpoint is not permission to turn a system pause into a stop.
            refreshDiagnostics(stage: "storage")
        }
    }

    private func terminate(reason: String, partial: Bool) {
        guard !finished else { return }
        if manifest?.diagnostics?.terminationCause == nil {
            refreshDiagnostics(stage: activeProcessingStage)
            manifest?.diagnostics?.terminationCause = partial ? "processingError" : "manual"
        }
        finishSession(reason: reason, partial: partial)
        // ReplayKit exposes an error-based extension stop; a system notice may appear even after successful output.
        let error = NSError(domain: "ScrollCapture.Broadcast", code: manifest?.status == .partial ? 1 : 0,
                            userInfo: [NSLocalizedDescriptionKey: CaptureMessageLocalization.text(manifest?.stopReason ?? reason)])
        DispatchQueue.main.async { [weak self] in self?.finishBroadcastWithError(error) }
    }
}
