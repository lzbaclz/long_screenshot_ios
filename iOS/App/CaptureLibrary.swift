import SwiftUI
import Combine

@MainActor
final class CaptureLibrary: ObservableObject {
    @Published private(set) var sessions: [CaptureSessionManifest] = []
    @Published var configuration = CaptureConfiguration()
    @Published var errorMessage: String?
    @Published private(set) var repository: CaptureSessionRepository?

    let isDemo: Bool
    let isSimulator: Bool

    init() {
        isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
        #if targetEnvironment(simulator)
        isSimulator = true
        #else
        isSimulator = false
        #endif
        do {
            if isDemo {
                let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("DemoCaptures", isDirectory: true)
                if ProcessInfo.processInfo.arguments.contains("--uitesting"),
                   FileManager.default.fileExists(atPath: root.path) {
                    try FileManager.default.removeItem(at: root)
                }
                repository = try CaptureSessionRepository(rootURL: root)
            } else {
                repository = try CaptureSessionRepository.application(allowLocalFallback: isSimulator)
            }
            if let repository {
                configuration = try repository.loadConfiguration()
                if isDemo { try DemoCaptureFactory.seed(repository: repository) }
            }
            refresh()
        } catch {
            errorMessage = String(localized: "无法打开本机保存空间。请检查设备剩余空间并重新打开应用。")
        }
    }

    var activeSession: CaptureSessionManifest? { sessions.first { $0.status == .capturing } }
    var completedSessions: [CaptureSessionManifest] {
        sessions.filter { $0.status == .completed && $0.hasImage && !$0.isSingleFrameFallback }
    }
    var draftSessions: [CaptureSessionManifest] {
        sessions.filter(\.isSavedPartialCapture)
    }
    var failedSessions: [CaptureSessionManifest] { sessions.filter(\.isFailedCapture) }

    func refresh() {
        guard let repository else { return }
        do {
            try repository.recoverInterruptedSessions(staleAfter: 15)
            sessions = try repository.listSessions()
        } catch {
            errorMessage = String(localized: "部分截图暂时无法读取，原始内容仍保存在本机。请稍后重试。")
        }
    }

    func saveSettings() {
        guard let repository else { return }
        do { try repository.saveConfiguration(configuration) }
        catch { errorMessage = String(localized: "设置没有保存成功，请检查剩余存储空间后重试。") }
    }

    func stopCapture() {
        guard let repository, let activeSession else { return }
        do { try repository.requestStop(id: activeSession.id) }
        catch { errorMessage = String(localized: "暂时无法停止。请点按系统的屏幕捕捉指示并选择停止。") }
    }

    func delete(_ session: CaptureSessionManifest) {
        guard let repository else { return }
        do {
            try repository.deleteSession(id: session.id)
            refresh()
        } catch {
            errorMessage = String(localized: "截图未删除。正在捕捉的内容需要先停止后才能删除。")
        }
    }

    func preview(sessionID: UUID, maxDimension: Int = 1800,
                 editsOverride: CaptureEditMetadata? = nil) async throws -> UIImage {
        guard let repository else { throw LibraryError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let image = try CaptureImageRenderer(repository: repository)
                        .preview(sessionID: sessionID, maxDimension: maxDimension, editsOverride: editsOverride)
                    continuation.resume(returning: image)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func export(sessionID: UUID, format: CaptureExportFormat, allowDownscale: Bool = false) async throws -> URL {
        guard let repository else { throw LibraryError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let url = try CaptureImageRenderer(repository: repository)
                        .export(sessionID: sessionID, format: format, maxPixelCount: 32_000_000,
                                allowDownscale: allowDownscale)
                    continuation.resume(returning: url)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    enum LibraryError: Error { case unavailable }
}

extension CaptureDiagnostics {
    var stageLabel: String {
        switch lastStage {
        case "starting": "等待屏幕画面"
        case "arming": "等待目标页面稳定"
        case "region": "确认滚动区域"
        case "alignment": "尝试衔接画面"
        case "foreground": "识别滚动消息"
        case "stitching": "连续拼接画面"
        case "frameConversion": "读取屏幕画面"
        case "missingVideoFrame": "未收到可读取的屏幕画面"
        case "provisionalImage", "provisionalWrite": "暂存起始画面"
        case "provisionalRead": "读取起始画面"
        case "frameRendering": "生成图片"
        case "firstCommit": "首次保存连续画面"
        case "storage", "stripCommit": "写入图片"
        case "manifestWrite": "保存捕捉记录"
        case "paused": "等待系统恢复捕捉"
        case "awaitingResumeOverlap": "恢复后重新确认画面衔接"
        default: "未记录"
        }
    }

    var terminationLabel: String {
        switch terminationCause {
        case "manual": "手动停止"
        case "systemPause", "paused": "系统暂停捕捉"
        case "systemInterruption", "interrupted": "系统中断捕捉"
        case "systemEnded", "systemStop": "系统结束捕捉"
        case "resumeOverlap": "恢复后的画面未能衔接"
        case "processingError": "画面处理或保存失败"
        case "geometry": "屏幕方向或尺寸改变"
        case "duration": "达到捕捉时长上限"
        case "idle": "达到静止停止时间"
        case "continuity": "画面未能连续衔接"
        case "screenLimit": "达到捕捉屏数上限"
        default: "未记录"
        }
    }
}

extension CaptureProcessingStage {
    var displayLabel: String {
        switch self {
        case .grayConversion: "读取屏幕画面"
        case .foregroundRegistration: "识别滚动消息"
        case .alignment: "尝试衔接画面"
        case .frameRendering: "生成图片"
        case .provisionalRead: "读取起始画面"
        case .provisionalWrite: "暂存起始画面"
        case .stripCommit: "写入图片"
        case .manifestWrite: "保存捕捉记录"
        }
    }
}

extension CaptureSessionManifest {
    var isFailedCapture: Bool { status != .capturing && !hasImage }
    var isSavedPartialCapture: Bool {
        hasImage && status != .capturing && (status != .completed || isSingleFrameFallback)
    }

    var displayTitle: String {
        createdAt.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
    }

    var stateLabel: String {
        if isFailedCapture { return "未捕捉到可用画面" }
        if status != .capturing && isSingleFrameFallback { return "仅保留单屏" }
        return switch status {
        case .capturing: "捕捉中"
        case .completed: startWarning == nil ? "已完成" : "请检查开头"
        case .partial: "部分内容已保留"
        case .interrupted: "待恢复"
        }
    }

    var noticeText: String? {
        if isFailedCapture { return failureNotice }
        var notices: [String] = []
        if status == .partial || status == .interrupted {
            notices.append(stopReason ?? "捕捉中途停止，以下已保存内容可以继续编辑和导出。")
        } else if startWarning != nil, let stopReason {
            notices.append(stopReason)
        }
        if let startWarning, !notices.contains(where: { $0.contains(startWarning) }) {
            notices.append(startWarning)
        }
        return notices.isEmpty ? nil : notices.joined(separator: "\n")
    }

    var localizedNoticeText: String? {
        if isFailedCapture { return L10n.captureReason(failureNotice) }
        guard var notice = noticeText else { return nil }
        if let startWarning { notice = notice.replacingOccurrences(of: startWarning, with: "") }
        var lines = notice.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(L10n.captureReason)
        if let startWarning { lines.append(L10n.captureReason(startWarning)) }
        return lines.joined(separator: "\n")
    }

    /// Earlier builds sometimes attached a "saved" notice to an empty manifest.
    /// Correct the presentation without rewriting or deleting the original record.
    private var failureNotice: String {
        guard let stopReason, !stopReason.isEmpty else {
            return "这次捕捉在保存画面前结束。请重新开始，切到目标应用后稍作停留，再上下滑动。"
        }
        switch stopReason {
        case "捕捉意外中断，已保留最后一次成功写入的画面。", "捕捉意外中断，已保留画面。":
            return "捕捉意外中断，未保存可用画面。请重新开始捕捉。"
        case "捕捉已暂停，已保留成功捕捉的部分。请重新开始下一段。":
            return "捕捉已暂停，未保存可用画面。请重新开始捕捉。"
        case "屏幕方向改变，已保存旋转前的内容。请重新开始下一段。":
            return "屏幕方向改变，未保存可用画面。请保持竖屏并重新开始捕捉。"
        case "画面尺寸发生变化，已保存变化前的内容。":
            return "画面尺寸发生变化，未保存可用画面。请重新开始捕捉。"
        case "画面无法可靠衔接，已保存连续部分。请降低滑动速度或调整捕捉区域后重试。":
            return "画面无法可靠衔接，未保存可用画面。请让前后画面保留重叠，或调整捕捉区域后重试。"
        case "未检测到可衔接的向下滚动。请停留在起点后缓慢向下滑动，再结束捕捉。":
            return "未检测到可衔接的滚动，未保存可用画面。请在目标应用稍作停留，再上下滑动后结束捕捉。"
        default:
            return stopReason
        }
    }
}
