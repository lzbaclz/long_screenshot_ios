import Foundation
import Darwin

/// An advisory filesystem lease shared across the host and broadcast extension processes.
/// Keeping this object alive keeps its session exclusively owned; process death releases it automatically.
public final class CaptureSessionLease: @unchecked Sendable {
    private let descriptor: Int32
    fileprivate init(url: URL) throws {
        let opened = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard opened >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(opened)
            if code == EWOULDBLOCK { throw CaptureStorageError.sessionStillActive }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        descriptor = opened
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

/// The extension is the sole manifest writer while capturing. Host edits are allowed only after completion.
public final class CaptureSessionRepository: @unchecked Sendable {
    public let rootURL: URL
    private let fileManager = FileManager.default
    private var sessionsURL: URL { rootURL.appendingPathComponent("Sessions", isDirectory: true) }

    public init(rootURL: URL) throws {
        self.rootURL = rootURL
        try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        var excluded = rootURL
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }

    /// Physical devices always require the signed App Group. Local storage is for simulator/demo use.
    public static func application(allowLocalFallback: Bool = false) throws -> CaptureSessionRepository {
        #if os(iOS)
        if let group = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroupIdentifier") as? String,
           !group.isEmpty, let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            return try .init(rootURL: url.appendingPathComponent("ScrollCapture", isDirectory: true))
        }
        #if targetEnvironment(simulator)
        if allowLocalFallback {
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return try .init(rootURL: url.appendingPathComponent("ScrollCaptureDemo", isDirectory: true))
        }
        #endif
        #else
        if allowLocalFallback {
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return try .init(rootURL: url.appendingPathComponent("ScrollCaptureDemo", isDirectory: true))
        }
        #endif
        throw CaptureStorageError.missingAppGroup
    }

    public func loadConfiguration() throws -> CaptureConfiguration {
        let url = rootURL.appendingPathComponent("configuration.json")
        guard fileManager.fileExists(atPath: url.path) else { return .init() }
        return try JSONDecoder().decode(CaptureConfiguration.self, from: Data(contentsOf: url)).validated()
    }

    public func saveConfiguration(_ configuration: CaptureConfiguration) throws {
        try write(configuration.validated(), to: rootURL.appendingPathComponent("configuration.json"))
    }

    public func createSession(configuration: CaptureConfiguration, isDemo: Bool = false) throws -> CaptureSessionManifest {
        let manifest = CaptureSessionManifest(configuration: try configuration.validated(), isDemo: isDemo)
        try fileManager.createDirectory(at: sessionDirectory(id: manifest.id), withIntermediateDirectories: true)
        try saveManifest(manifest)
        return manifest
    }

    public func sessionDirectory(id: UUID) -> URL { sessionsURL.appendingPathComponent(id.uuidString, isDirectory: true) }

    public func acquireSessionLease(id: UUID) throws -> CaptureSessionLease {
        try CaptureSessionLease(url: sessionDirectory(id: id).appendingPathComponent(".writer.lock"))
    }

    public func loadSession(id: UUID) throws -> CaptureSessionManifest {
        let url = sessionDirectory(id: id).appendingPathComponent("manifest.json")
        let manifest = try JSONDecoder().decode(CaptureSessionManifest.self, from: Data(contentsOf: url))
        guard manifest.id == id else { throw CaptureStorageError.invalidManifest }
        try validateManifest(manifest)
        return manifest
    }

    public func listSessions() throws -> [CaptureSessionManifest] {
        let urls = try fileManager.contentsOfDirectory(at: sessionsURL, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles])
        // Corrupt/unfinished directories remain on disk for diagnosis; one bad item does not hide valid captures.
        return urls.compactMap { url in
            UUID(uuidString: url.lastPathComponent).flatMap { try? loadSession(id: $0) }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func saveManifest(_ manifest: CaptureSessionManifest) throws {
        try validateManifest(manifest)
        try write(manifest, to: sessionDirectory(id: manifest.id).appendingPathComponent("manifest.json"))
    }

    public func saveEdits(_ edits: CaptureEditMetadata, sessionID: UUID) throws {
        let lease = try acquireSessionLease(id: sessionID)
        defer { withExtendedLifetime(lease) {} }
        var manifest = try loadSession(id: sessionID)
        guard manifest.status != .capturing else { throw CaptureStorageError.sessionStillActive }
        try validateEdits(edits, strips: manifest.strips)
        manifest.edits = edits; manifest.updatedAt = Date()
        try saveManifest(manifest)
    }

    public func requestStop(id: UUID) throws {
        guard try loadSession(id: id).status == .capturing else { return }
        try Data().write(to: sessionDirectory(id: id).appendingPathComponent("stop.request"), options: .atomic)
    }

    public func hasStopRequest(id: UUID) -> Bool {
        fileManager.fileExists(atPath: sessionDirectory(id: id).appendingPathComponent("stop.request").path)
    }

    /// Only recover after acquiring the dead writer's lease, then reread its final atomic manifest.
    @discardableResult public func recoverInterruptedSessions(staleAfter: TimeInterval = 15) throws -> Int {
        var count = 0
        for candidate in try listSessions() where candidate.status == .capturing {
            let lease: CaptureSessionLease
            do { lease = try acquireSessionLease(id: candidate.id) }
            catch CaptureStorageError.sessionStillActive { continue }
            defer { withExtendedLifetime(lease) {} }
            var manifest = try loadSession(id: candidate.id)
            guard manifest.status == .capturing,
                  Date().timeIntervalSince(manifest.updatedAt) > max(15, staleAfter) else { continue }
            manifest.status = .interrupted
            manifest.stopReason = "捕捉意外中断，已保留最后一次成功写入的画面。"
            manifest.updatedAt = Date()
            try saveManifest(manifest); count += 1
        }
        return count
    }

    public func deleteSession(id: UUID) throws {
        let lease = try acquireSessionLease(id: id)
        defer { withExtendedLifetime(lease) {} }
        guard try loadSession(id: id).status != .capturing else { throw CaptureStorageError.sessionStillActive }
        try fileManager.removeItem(at: sessionDirectory(id: id))
    }

    public func stripURL(_ strip: CaptureStrip, sessionID: UUID) throws -> URL {
        guard strip.fileName == "\(strip.id.uuidString).png" else { throw CaptureStorageError.invalidManifest }
        return sessionDirectory(id: sessionID).appendingPathComponent(strip.fileName)
    }

    private func validateManifest(_ manifest: CaptureSessionManifest) throws {
        guard manifest.schemaVersion == 1, manifest.pixelWidth >= 0, manifest.pixelWidth <= 8_192,
              manifest.strips.count <= 10_000, Set(manifest.strips.map(\.id)).count == manifest.strips.count,
              manifest.strips.allSatisfy({ $0.pixelWidth > 0 && $0.pixelWidth == manifest.pixelWidth &&
                  $0.pixelHeight > 0 && $0.pixelHeight <= 16_384 && $0.sourceTopPixel >= 0 &&
                  $0.fileName == "\($0.id.uuidString).png" }),
              manifest.pixelHeight <= 200_000 else { throw CaptureStorageError.invalidManifest }
        _ = try manifest.configuration.validated()
        try validateEdits(manifest.edits, strips: manifest.strips)
    }

    func validateEdits(_ edits: CaptureEditMetadata, strips: [CaptureStrip]) throws {
        guard edits.crop?.isValid != false, edits.redactions.count <= 500,
              edits.redactions.allSatisfy(\.isValid),
              edits.seamTrimPixels.allSatisfy({ key, value in
                  guard let strip = strips.first(where: { $0.id.uuidString == key }) else { return false }
                  return value >= 0 && value < strip.pixelHeight
              }) else { throw CaptureStorageError.invalidEdits }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
