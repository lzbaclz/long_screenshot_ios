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
    private var startedUptime = 0.0
    private var lastFrameUptime = 0.0
    private var lastMotionUptime = 0.0
    private var continuity = CaptureContinuityPolicy()
    private var skippedSamples = 0
    private var maximumProcessingMilliseconds = 0.0
    private var originalWidth = 0
    private var originalHeight = 0
    private var initialOrientation: Int32?
    private var didMove = false
    private var finished = false
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
                session.diagnostics = CaptureDiagnostics()
                try storage.saveManifest(session); manifest = session
                startedUptime = ProcessInfo.processInfo.systemUptime
                lastMotionUptime = startedUptime
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
            guard !finished, let configuration = manifest?.configuration else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastFrameUptime >= 0.15 else { skippedSamples += 1; return }
            defer {
                maximumProcessingMilliseconds = max(maximumProcessingMilliseconds,
                    (ProcessInfo.processInfo.systemUptime - now) * 1_000)
                manifest?.diagnostics?.maximumProcessingMilliseconds = maximumProcessingMilliseconds
            }
            lastFrameUptime = now
            do {
                try autoreleasepool { try processVideo(sampleBuffer, configuration: configuration, now: now) }
            } catch {
                manifest?.diagnostics?.terminationCause = "processingError"
                terminate(reason: error.localizedDescription, partial: true)
            }
        }
    }

    override func broadcastPaused() {
        processingQueue.sync {
            // Continuing after a pause could skip unseen content. Preserve the trusted partial result.
            manifest?.diagnostics?.terminationCause = "systemPause"
            terminate(reason: "捕捉已暂停，已保留成功捕捉的部分。请重新开始下一段。", partial: true)
        }
    }

    override func broadcastResumed() { }

    override func broadcastFinished() {
        processingQueue.sync {
            guard !finished else { return }
            manifest?.diagnostics?.terminationCause = "manual"
            finishSession(reason: "已手动结束捕捉。", partial: false)
        }
    }

    private func processVideo(_ sample: CMSampleBuffer, configuration: CaptureConfiguration, now: Double) throws {
        guard let storage = repository, var session = manifest else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else {
            manifest?.diagnostics = framePipeline?.diagnostics ?? CaptureDiagnostics()
            manifest?.diagnostics?.lastStage = "missingVideoFrame"
            registerRejection(now: now); return
        }
        let attachment = CMGetAttachment(sample, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil)
        let orientation = (attachment as? NSNumber)?.int32Value ?? 1
        if let initialOrientation, initialOrientation != orientation, !session.strips.isEmpty {
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
            if !session.strips.isEmpty {
                manifest?.diagnostics?.terminationCause = "geometry"
                terminate(reason: "画面尺寸发生变化，已保存变化前的内容。", partial: true); return
            }
            framePipeline = nil
        }
        originalWidth = width; originalHeight = height
        let analysisWidth = min(144, width)
        // Downsample horizontally only. Native-height analysis keeps every seam on an original image row.
        session.diagnostics = framePipeline?.diagnostics ?? CaptureDiagnostics()
        session.diagnostics?.observedFrames += 1
        try checkpointStartup(stage: "frameConversion", storage: storage, session: &session)
        let coarse = try CaptureFrameConversion.grayFrame(source, context: imageContext,
                                                          width: analysisWidth, height: height)
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
        let result = try framePipeline.ingest(coarse) {
            guard let image = imageContext.createCGImage(source, from: source.extent) else {
                throw CaptureStorageError.imageEncodingFailed
            }
            return image
        }
        // Arming may atomically publish a provisional still. Merge its new
        // reference before this callback or the heartbeat writes its snapshot.
        session.provisionalFrame = framePipeline.provisionalFrame
        if result.replacedProvisionalStart {
            session.startWarning = "画面变化后重新确定了起点，请检查图片开头是否完整。"
            manifest = session
        }
        session.diagnostics = framePipeline.diagnostics
        session.diagnostics?.skippedSamples = skippedSamples
        session.diagnostics?.maximumProcessingMilliseconds = maximumProcessingMilliseconds
        manifest = session
        if result.status == .rejected {
            registerRejection(now: now); return
        }
        if result.status == .unchanged {
            continuity.accept()
            return
        }
        if !result.isArming && (result.status == .advanced || result.status == .backtracked) {
            didMove = true; lastMotionUptime = now
        }
        if !result.strips.isEmpty {
            let region = framePipeline.effectiveConfiguration
            let maximumHeight = configuration.maximumBodyPixelHeight(frameHeight: height,
                matchingTopInset: region.topInset, matchingBottomInset: region.bottomInset)
            try checkpointStartup(stage: "firstCommit", storage: storage, session: &session)
            session.diagnostics?.lastStage = "storage"
            manifest = session
            let reachedLimit = try storage.commit(result, maximumBodyHeight: maximumHeight, to: &session)
            framePipeline.confirmCommit()
            manifest = session
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
        try storage.saveManifest(session)
        persistedStartupStages.insert(stage)
    }

    private func registerRejection(now: Double) {
        manifest?.rejectedFrameCount += 1
        // Treat rejected motion as activity for idle-stop purposes. It can
        // finish only as a continuity failure unless a trusted bridge recovers.
        lastMotionUptime = now
        if continuity.reject(at: now, hasStarted: framePipeline?.hasStarted == true) {
            manifest?.diagnostics?.terminationCause = "continuity"
            terminate(reason: "画面暂时无法连续衔接，已保存已确认的连续长图。请降低滑动速度后重试。", partial: true)
        }
    }

    private func heartbeat() {
        guard !finished, var session = manifest, let storage = repository else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if storage.hasStopRequest(id: session.id) {
            manifest?.diagnostics?.terminationCause = "manual"
            terminate(reason: "已手动结束捕捉。", partial: false); return
        }
        if now - startedUptime >= session.configuration.maximumDurationSeconds {
            manifest?.diagnostics?.terminationCause = "duration"
            terminate(reason: "已达到设置的时长上限。", partial: false); return
        }
        // Initial system countdown/app switching must not trigger idle completion before the user scrolls.
        if didMove, !continuity.isAwaitingBridge, let idle = session.configuration.idleStopSeconds, now - lastMotionUptime >= idle {
            manifest?.diagnostics?.terminationCause = "idle"
            terminate(reason: "停止滑动 \(Int(idle)) 秒，已完成捕捉。", partial: false); return
        }
        session.updatedAt = Date()
        do { try storage.saveManifest(session); manifest = session }
        catch { terminate(reason: error.localizedDescription, partial: true) }
    }

    private func finishSession(reason: String, partial: Bool) {
        finished = true; timer?.cancel(); timer = nil
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
                    session.diagnostics?.lastStage = "storage"
                    session.diagnostics?.terminationCause = "processingError"
                    finalReason = error.localizedDescription
                }
            }
            session.finalizeCapture(reason: finalReason, partial: partial)
            do { try repository?.saveManifest(session); manifest = session }
            catch {
                // The previous atomic manifest and source strips survive; host recovery handles the interrupted lease.
            }
        }
        framePipeline = nil; imageContext.clearCaches()
        sessionLease = nil
    }

    private func terminate(reason: String, partial: Bool) {
        guard !finished else { return }
        finishSession(reason: reason, partial: partial)
        // ReplayKit exposes an error-based extension stop; a system notice may appear even after successful output.
        let error = NSError(domain: "ScrollCapture.Broadcast", code: manifest?.status == .partial ? 1 : 0,
                            userInfo: [NSLocalizedDescriptionKey: CaptureMessageLocalization.text(manifest?.stopReason ?? reason)])
        DispatchQueue.main.async { [weak self] in self?.finishBroadcastWithError(error) }
    }
}
