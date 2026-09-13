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
    var completedSessions: [CaptureSessionManifest] { sessions.filter { $0.status == .completed } }
    var draftSessions: [CaptureSessionManifest] {
        sessions.filter { $0.status == .partial || $0.status == .interrupted }
    }

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

extension CaptureSessionManifest {
    var displayTitle: String {
        createdAt.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
    }

    var stateLabel: String {
        switch status {
        case .capturing: "捕捉中"
        case .completed: startWarning == nil ? "已完成" : "请检查开头"
        case .partial: "部分内容已保留"
        case .interrupted: "待恢复"
        }
    }

    var noticeText: String? {
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
        guard var notice = noticeText else { return nil }
        if let startWarning { notice = notice.replacingOccurrences(of: startWarning, with: "") }
        var lines = notice.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(L10n.captureReason)
        if let startWarning { lines.append(L10n.captureReason(startWarning)) }
        return lines.joined(separator: "\n")
    }
}
