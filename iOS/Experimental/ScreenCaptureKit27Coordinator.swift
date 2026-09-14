#if CAPTUREKIT_IOS27 && os(iOS)
@preconcurrency import ScreenCaptureKit
import Combine
import Foundation

/// Experimental iOS 27 host adapter. This type is absent unless CAPTUREKIT_IOS27 is explicitly set.
/// Keep it alive in the host scene; presenting the picker must follow a direct user action.
@available(iOS 27.0, *)
@MainActor
public final class ScreenCaptureKit27Coordinator: ObservableObject {
    public enum Phase: String, Sendable { case idle, choosing, starting, capturing, stopping, finished, failed }
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var sessionID: UUID?
    @Published public private(set) var message: String?

    private let repository: CaptureSessionRepository
    private let picker = SCContentSharingPicker.shared
    private var observer: ScreenCaptureKit27Observer?
    private var pendingConfiguration: CaptureConfiguration?
    private var stream: SCStream?
    private var sink: ScreenCaptureKit27FrameSink?
    private var generation = UUID()

    public init(repository: CaptureSessionRepository) { self.repository = repository }

    /// Unlike the in-app-only picker API, present() requests the entire display on iOS 27.
    public func presentEntireDisplayPicker(configuration: CaptureConfiguration = .init()) throws {
        guard phase != .choosing, phase != .starting, phase != .capturing, phase != .stopping else {
            throw CaptureStorageError.sessionStillActive
        }
        guard picker.isAvailable else {
            throw adapterError("Screen capture is unavailable on this device or is restricted by the system.")
        }
        _ = try repository.recoverInterruptedSessions()
        guard try repository.listSessions().allSatisfy({ $0.status != .capturing }) else {
            throw CaptureStorageError.sessionStillActive
        }
        pendingConfiguration = try configuration.validated()
        generation = UUID(); sessionID = nil; message = nil; phase = .choosing
        let currentObserver = ScreenCaptureKit27Observer(coordinator: self, generation: generation)
        observer = currentObserver
        var options = SCContentSharingPickerConfiguration()
        options.showsMicrophoneControl = false
        options.showsCameraControl = false
        picker.defaultConfiguration = options
        picker.add(currentObserver)
        picker.isActive = true
        picker.present()
    }

    /// Stops the system stream and persists accepted strips. Safe when the picker is cancelled or idle.
    public func stop() async { await stopCurrent(reason: "已手动结束捕捉。", partial: false) }

    /// The host should await this before discarding the coordinator or switching capture backends.
    public func invalidate() async {
        await stopCurrent(reason: "已手动结束捕捉。", partial: false)
        deactivatePicker()
    }

    fileprivate func selected(_ filter: SCContentFilter, updating existing: SCStream?, token: UUID) async {
        guard generation == token else { return }
        if let existing {
            guard stream === existing else { return }
            await stopCurrent(reason: "画面无法可靠衔接，已保存连续部分。请降低滑动速度或调整捕捉区域后重试。", partial: true)
            return
        }
        guard phase == .choosing, let configuration = pendingConfiguration, let observer else { return }
        phase = .starting
        let attempt = generation
        do {
            // Reject an unexpected selection rather than silently treating in-app content as a full display.
            guard filter.style == .display else {
                throw adapterError("Choose the entire display to create a screenshot across apps.")
            }
            _ = try repository.recoverInterruptedSessions()
            guard try repository.listSessions().allSatisfy({ $0.status != .capturing }) else {
                throw CaptureStorageError.sessionStillActive
            }
            let scale = CGFloat(filter.pointPixelScale)
            let width = (filter.contentRect.width * scale).rounded()
            let height = (filter.contentRect.height * scale).rounded()
            guard scale.isFinite, scale > 0, width.isFinite, height.isFinite,
                  width > 0, height > 0, width <= 4_096, height <= 4_096,
                  width * height <= 9_000_000 else { throw CaptureStorageError.exportTooLarge }

            let settings = SCStreamConfiguration()
            settings.width = Int(width); settings.height = Int(height)
            settings.capturesAudio = false
            // iOS 27 beta 6 does not expose pixel-format, cadence, queue-depth,
            // microphone-capture or aspect-ratio setters. Use system defaults;
            // the sink accepts CVPixelBuffer formats through Core Image and
            // throttles processing without adding a retained-sample queue.

            let output = try ScreenCaptureKit27FrameSink(repository: repository, configuration: configuration) {
                [weak self] outcome in
                Task { @MainActor [weak self] in await self?.sinkFinished(outcome) }
            }
            let created = SCStream(filter: filter, configuration: settings, delegate: observer)
            sink = output; stream = created; sessionID = output.sessionID
            try created.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
            try await created.startCapture()
            guard generation == attempt, phase == .starting, stream === created else {
                // A stop/cancel can arrive while startCapture is awaiting the system.
                try? await created.stopCapture()
                return
            }
            pendingConfiguration = nil; phase = .capturing
        } catch {
            guard generation == attempt else { return }
            await stopCurrent(reason: error.localizedDescription, partial: true)
            phase = .failed; message = error.localizedDescription
        }
    }

    fileprivate func pickerCancelled(for existing: SCStream?, token: UUID) {
        guard generation == token, existing == nil, phase == .choosing else { return }
        generation = UUID(); pendingConfiguration = nil; phase = .idle
        deactivatePicker()
    }

    fileprivate func pickerFailed(_ description: String, token: UUID) async {
        guard generation == token else { return }
        await stopCurrent(reason: description, partial: true)
        phase = .failed; message = description
    }

    fileprivate func systemStopped(_ stopped: SCStream, description: String, partial: Bool = true) async {
        guard stream === stopped else { return }
        await stopCurrent(reason: description, partial: partial)
    }

    private func stopCurrent(reason: String, partial: Bool) async {
        generation = UUID(); pendingConfiguration = nil
        let current = stream, output = sink
        stream = nil; sink = nil
        guard current != nil || output != nil else {
            deactivatePicker()
            if phase == .choosing || phase == .starting { phase = .idle }
            return
        }
        phase = .stopping
        let outcome = await output?.finish(reason: reason, partial: partial)
        do { try await current?.stopCapture() }
        catch { message = error.localizedDescription }
        deactivatePicker()
        if let outcome { apply(outcome) }
        else { phase = .finished }
    }

    private func sinkFinished(_ outcome: ScreenCaptureKit27Outcome) async {
        guard sink?.sessionID == outcome.manifest.id else { return }
        let current = stream
        stream = nil; sink = nil; generation = UUID(); phase = .stopping
        try? await current?.stopCapture()
        deactivatePicker()
        apply(outcome)
    }

    private func apply(_ outcome: ScreenCaptureKit27Outcome) {
        sessionID = outcome.manifest.id
        phase = outcome.persistenceError == nil ? .finished : .failed
        let canonical = outcome.persistenceError ?? outcome.manifest.stopReason ?? ""
        var lines = [CaptureMessageLocalization.text(canonical)]
        if let warning = outcome.manifest.startWarning {
            lines.append(CaptureMessageLocalization.text(warning))
        }
        message = lines.joined(separator: "\n")
    }

    private func deactivatePicker() {
        if let observer { picker.remove(observer); self.observer = nil }
        picker.isActive = false
    }

    private func adapterError(_ description: String) -> NSError {
        NSError(domain: "Longlet.ScreenCaptureKit27", code: 1,
                userInfo: [NSLocalizedDescriptionKey: description])
    }
}

/// Apple invokes picker and stream delegate methods off the main actor. This bridge
/// holds only a weak actor reference; captured framework objects are used on the main actor.
@available(iOS 27.0, *)
private final class ScreenCaptureKit27Observer: NSObject, SCContentSharingPickerObserver, SCStreamDelegate,
                                                @unchecked Sendable {
    private weak var coordinator: ScreenCaptureKit27Coordinator?
    private let generation: UUID
    init(coordinator: ScreenCaptureKit27Coordinator, generation: UUID) {
        self.coordinator = coordinator; self.generation = generation
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter,
                                         for stream: SCStream?) {
        let token = generation
        Task { @MainActor [weak coordinator] in await coordinator?.selected(filter, updating: stream, token: token) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        let token = generation
        Task { @MainActor [weak coordinator] in coordinator?.pickerCancelled(for: stream, token: token) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        let description = error.localizedDescription
        let token = generation
        Task { @MainActor [weak coordinator] in await coordinator?.pickerFailed(description, token: token) }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let userStopped = (error as? SCStreamError)?.code == .userStopped
        let description = userStopped ? "已手动结束捕捉。" : error.localizedDescription
        Task { @MainActor [weak coordinator] in
            await coordinator?.systemStopped(stream, description: description, partial: !userStopped)
        }
    }

    nonisolated func streamDidBecomeInactive(_ stream: SCStream) {
        Task { @MainActor [weak coordinator] in
            await coordinator?.systemStopped(stream, description: "捕捉已暂停，已保留成功捕捉的部分。请重新开始下一段。")
        }
    }
}
#endif
