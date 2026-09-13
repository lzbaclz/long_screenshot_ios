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
    private var rejectedSince: Double?
    private var originalWidth = 0
    private var originalHeight = 0
    private var initialOrientation: Int32?
    private var didMove = false
    private var finished = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        processingQueue.sync {
            do {
                let storage = try CaptureSessionRepository.application()
                _ = try storage.recoverInterruptedSessions()
                let configuration = try storage.loadConfiguration()
                let session = try storage.createSession(configuration: configuration)
                sessionLease = try storage.acquireSessionLease(id: session.id)
                repository = storage; manifest = session
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
            guard now - lastFrameUptime >= 0.15 else { return }
            lastFrameUptime = now
            do {
                try autoreleasepool { try processVideo(sampleBuffer, configuration: configuration, now: now) }
            } catch { terminate(reason: error.localizedDescription, partial: true) }
        }
    }

    override func broadcastPaused() {
        processingQueue.sync {
            // Continuing after a pause could skip unseen content. Preserve the trusted partial result.
            terminate(reason: "捕捉已暂停，已保留成功捕捉的部分。请重新开始下一段。", partial: true)
        }
    }

    override func broadcastResumed() { }

    override func broadcastFinished() {
        processingQueue.sync {
            guard !finished else { return }
            finishSession(reason: "已手动结束捕捉。", partial: false)
        }
    }

    private func processVideo(_ sample: CMSampleBuffer, configuration: CaptureConfiguration, now: Double) throws {
        guard let buffer = CMSampleBufferGetImageBuffer(sample), let storage = repository,
              var session = manifest else { return }
        let attachment = CMGetAttachment(sample, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil)
        let orientation = (attachment as? NSNumber)?.int32Value ?? 1
        if let initialOrientation, initialOrientation != orientation, !session.strips.isEmpty {
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
                terminate(reason: "画面尺寸发生变化，已保存变化前的内容。", partial: true); return
            }
            framePipeline = nil
        }
        originalWidth = width; originalHeight = height
        let analysisWidth = min(144, width)
        // Downsample horizontally only. Native-height analysis keeps every seam on an original image row.
        let coarse = try grayFrame(source, width: analysisWidth, height: height)
        let top = Int(Double(height) * configuration.captureTopInsetFraction)
        let bottom = Int(Double(height) * configuration.captureBottomInsetFraction)
        if framePipeline == nil { framePipeline = .init(configuration: .init(topInset: top, bottomInset: bottom)) }
        guard let framePipeline else { return }
        let result = try framePipeline.ingest(coarse) {
            guard let image = imageContext.createCGImage(source, from: source.extent) else {
                throw CaptureStorageError.imageEncodingFailed
            }
            return image
        }
        if result.replacedProvisionalStart {
            session.startWarning = "画面变化后重新确定了起点，请检查图片开头是否完整。"
            manifest = session
        }
        if let warning = result.regionWarning {
            terminate(reason: warning, partial: true); return
        }
        if result.status == .rejected {
            registerRejection(now: now); return
        }
        if result.status == .unchanged {
            rejectedSince = nil
            return
        }
        if !result.isArming && (result.status == .advanced || result.status == .backtracked) {
            didMove = true; lastMotionUptime = now
        }
        for pending in result.strips {
            let region = framePipeline.effectiveConfiguration
            let maximumHeight = (height - region.topInset - region.bottomInset) * configuration.maximumScreenCount
            let remaining = max(0, maximumHeight - session.pixelHeight)
            let rowCount = min(pending.image.height, remaining)
            if rowCount > 0 {
                guard let strip = pending.image.cropping(to: CGRect(x: 0, y: 0, width: width, height: rowCount))
                else { throw CaptureStorageError.imageEncodingFailed }
                try storage.appendStrip(image: strip, sourceTopPixel: pending.sourceTopPixel, to: &session)
                manifest = session
            }
            if session.pixelHeight >= maximumHeight {
                terminate(reason: "已达到设置的 \(configuration.maximumScreenCount) 屏上限。", partial: false); return
            }
        }
        rejectedSince = nil
    }

    private func grayFrame(_ source: CIImage, width: Int, height: Int) throws -> GrayFrame {
        let resized = source.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / source.extent.width,
                                                               y: CGFloat(height) / source.extent.height))
        guard let image = imageContext.createCGImage(resized, from: CGRect(x: 0, y: 0, width: width, height: height)),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0),
              let bytes = context.data else { throw CaptureStorageError.imageEncodingFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: width * height))
        return try GrayFrame(width: width, height: height, pixels: pixels)
    }

    private func registerRejection(now: Double) {
        manifest?.rejectedFrameCount += 1
        if rejectedSince == nil { rejectedSince = now }
        if now - (rejectedSince ?? now) >= 0.8 {
            terminate(reason: "画面无法可靠衔接，已保存连续部分。请降低滑动速度或调整捕捉区域后重试。", partial: true)
        }
    }

    private func heartbeat() {
        guard !finished, var session = manifest, let storage = repository else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if storage.hasStopRequest(id: session.id) {
            terminate(reason: "已手动结束捕捉。", partial: false); return
        }
        if now - startedUptime >= session.configuration.maximumDurationSeconds {
            terminate(reason: "已达到设置的时长上限。", partial: false); return
        }
        // Initial system countdown/app switching must not trigger idle completion before the user scrolls.
        if didMove, let idle = session.configuration.idleStopSeconds, now - lastMotionUptime >= idle {
            terminate(reason: "停止滑动 \(Int(idle)) 秒，已完成捕捉。", partial: false); return
        }
        session.updatedAt = Date()
        do { try storage.saveManifest(session); manifest = session }
        catch { terminate(reason: error.localizedDescription, partial: true) }
    }

    private func finishSession(reason: String, partial: Bool) {
        finished = true; timer?.cancel(); timer = nil
        if var session = manifest {
            session.status = partial || session.strips.isEmpty ? .partial : .completed
            session.stopReason = session.strips.isEmpty && !partial ? "未检测到可衔接的向下滚动。请停留在起点后缓慢向下滑动，再结束捕捉。" : reason
            if let warning = session.startWarning, !session.strips.isEmpty {
                session.stopReason = (session.stopReason ?? "") + " " + warning
            }
            session.updatedAt = Date()
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
        let error = NSError(domain: "ScrollCapture.Broadcast", code: partial ? 1 : 0,
                            userInfo: [NSLocalizedDescriptionKey: CaptureMessageLocalization.text(reason)])
        DispatchQueue.main.async { [weak self] in self?.finishBroadcastWithError(error) }
    }
}
