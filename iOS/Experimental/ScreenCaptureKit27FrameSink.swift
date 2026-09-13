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
    private let startedUptime = ProcessInfo.processInfo.systemUptime
    private var lastFrameUptime = 0.0
    private var lastMotionUptime = 0.0
    private var rejectedSince: Double?
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
            _ = finishOnQueue(reason: "捕捉已暂停，已保留成功捕捉的部分。请重新开始下一段。", partial: true)
            return
        case .complete, .started: break
        @unknown default:
            registerRejection(now: now); return
        }
        guard stoppedFrameUptime == nil else { return }
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer), now - lastFrameUptime >= 0.15 else { return }
        lastFrameUptime = now
        let orientation = (values[.videoOrientation] as? NSNumber)?.int32Value ?? 1
        do {
            try autoreleasepool { try process(sampleBuffer, orientation: orientation, now: now) }
        } catch { _ = finishOnQueue(reason: error.localizedDescription, partial: true) }
    }

    func finish(reason: String, partial: Bool) async -> ScreenCaptureKit27Outcome {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.finishOnQueue(reason: reason, partial: partial)) }
        }
    }

    private func process(_ sample: CMSampleBuffer, orientation: Int32, now: Double) throws {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { registerRejection(now: now); return }
        guard (1...8).contains(orientation) else { registerRejection(now: now); return }
        if let initialOrientation, initialOrientation != orientation, !manifest.strips.isEmpty {
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
            guard manifest.strips.isEmpty else {
                _ = finishOnQueue(reason: "画面尺寸发生变化，已保存变化前的内容。", partial: true); return
            }
            pipeline = nil
        }
        originalWidth = width; originalHeight = height
        let configuration = manifest.configuration
        let top = Int(Double(height) * configuration.captureTopInsetFraction)
        let bottom = Int(Double(height) * configuration.captureBottomInsetFraction)
        if pipeline == nil { pipeline = .init(configuration: .init(topInset: top, bottomInset: bottom)) }
        guard let pipeline else { return }
        let gray = try grayFrame(source, width: min(144, width), height: height)
        let result = try pipeline.ingest(gray) {
            guard let image = imageContext.createCGImage(source, from: source.extent) else {
                throw CaptureStorageError.imageEncodingFailed
            }
            return image
        }
        if result.replacedProvisionalStart {
            manifest.startWarning = "画面变化后重新确定了起点，请检查图片开头是否完整。"
        }
        if let warning = result.regionWarning { _ = finishOnQueue(reason: warning, partial: true); return }
        if result.status == .rejected { registerRejection(now: now); return }
        if !result.isArming && (result.status == .advanced || result.status == .backtracked) {
            didMove = true; lastMotionUptime = now
        }
        for pending in result.strips {
            let region = pipeline.effectiveConfiguration
            let maximumHeight = (height - region.topInset - region.bottomInset) * configuration.maximumScreenCount
            let count = min(pending.image.height, max(0, maximumHeight - manifest.pixelHeight))
            if count > 0 {
                guard let image = pending.image.cropping(to: CGRect(x: 0, y: 0, width: width, height: count)) else {
                    throw CaptureStorageError.imageEncodingFailed
                }
                try repository.appendStrip(image: image, sourceTopPixel: pending.sourceTopPixel, to: &manifest)
            }
            if manifest.pixelHeight >= maximumHeight {
                _ = finishOnQueue(reason: "已达到设置的 \(configuration.maximumScreenCount) 屏上限。", partial: false)
                return
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
        return try GrayFrame(width: width, height: height,
                             pixels: Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self),
                                                               count: width * height)))
    }

    private func registerRejection(now: Double) {
        manifest.rejectedFrameCount += 1
        if rejectedSince == nil { rejectedSince = now }
        if now - (rejectedSince ?? now) >= 0.8 {
            _ = finishOnQueue(reason: "画面无法可靠衔接，已保存连续部分。请降低滑动速度或调整捕捉区域后重试。", partial: true)
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
            _ = finishOnQueue(reason: "捕捉已暂停，已保留成功捕捉的部分。请重新开始下一段。", partial: true); return
        }
        if repository.hasStopRequest(id: sessionID) {
            _ = finishOnQueue(reason: "已手动结束捕捉。", partial: false); return
        }
        if now - startedUptime >= manifest.configuration.maximumDurationSeconds {
            _ = finishOnQueue(reason: "已达到设置的时长上限。", partial: false); return
        }
        if didMove, let idle = manifest.configuration.idleStopSeconds, now - lastMotionUptime >= idle {
            _ = finishOnQueue(reason: "停止滑动 \(Int(idle)) 秒，已完成捕捉。", partial: false); return
        }
        manifest.updatedAt = Date()
        do { try repository.saveManifest(manifest) }
        catch { _ = finishOnQueue(reason: error.localizedDescription, partial: true) }
    }

    private func finishOnQueue(reason: String, partial: Bool) -> ScreenCaptureKit27Outcome {
        if let outcome { return outcome }
        timer?.cancel(); timer = nil
        manifest.status = partial || manifest.strips.isEmpty ? .partial : .completed
        manifest.stopReason = manifest.strips.isEmpty && !partial
            ? "未检测到可衔接的向下滚动。请停留在起点后缓慢向下滑动，再结束捕捉。" : reason
        manifest.updatedAt = Date()
        var persistenceError: String?
        do { try repository.saveManifest(manifest) }
        catch { persistenceError = error.localizedDescription }
        let result = ScreenCaptureKit27Outcome(manifest: manifest, persistenceError: persistenceError)
        outcome = result; pipeline = nil; imageContext.clearCaches(); lease = nil
        onFinish(result)
        return result
    }
}
#endif
