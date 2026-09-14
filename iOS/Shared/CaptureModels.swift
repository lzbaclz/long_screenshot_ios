import Foundation

public struct CaptureConfiguration: Codable, Equatable, Sendable {
    public var idleStopSeconds: Double?
    public var maximumDurationSeconds: Double
    public var maximumScreenCount: Int
    public var captureTopInsetFraction: Double
    public var captureBottomInsetFraction: Double

    public init(idleStopSeconds: Double? = nil, maximumDurationSeconds: Double = 120,
                maximumScreenCount: Int = 20, captureTopInsetFraction: Double = 0,
                captureBottomInsetFraction: Double = 0) {
        self.idleStopSeconds = idleStopSeconds
        self.maximumDurationSeconds = maximumDurationSeconds
        self.maximumScreenCount = maximumScreenCount
        self.captureTopInsetFraction = captureTopInsetFraction
        self.captureBottomInsetFraction = captureBottomInsetFraction
    }

    /// Automatic matching may use only a small moving interior. Its size is
    /// not the user's screen size; the capture limit still counts full viewports.
    /// Manual ignored regions keep their explicitly cropped-screen meaning.
    public func maximumBodyPixelHeight(frameHeight: Int, matchingTopInset: Int,
                                       matchingBottomInset: Int) -> Int {
        guard (1...4_096).contains(frameHeight), (2...20).contains(maximumScreenCount),
              matchingTopInset >= 0, matchingBottomInset >= 0,
              matchingTopInset < frameHeight, matchingBottomInset < frameHeight - matchingTopInset else { return 0 }
        let automatic = captureTopInsetFraction == 0 && captureBottomInsetFraction == 0
        let edgeHeight = matchingTopInset + matchingBottomInset
        if automatic { return frameHeight * maximumScreenCount - edgeHeight }
        return (frameHeight - edgeHeight) * maximumScreenCount
    }

    public func validated() throws -> Self {
        guard maximumDurationSeconds.isFinite, (5...120).contains(maximumDurationSeconds),
              (2...20).contains(maximumScreenCount),
              idleStopSeconds == nil || idleStopSeconds == 5 || idleStopSeconds == 10,
              captureTopInsetFraction.isFinite, captureBottomInsetFraction.isFinite,
              (0...0.4).contains(captureTopInsetFraction),
              (0...0.4).contains(captureBottomInsetFraction),
              captureTopInsetFraction + captureBottomInsetFraction <= 0.6 else {
            throw CaptureStorageError.invalidConfiguration
        }
        return self
    }
}

public struct NormalizedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && x < 1 && y < 1 && width > 0 &&
        height > 0 && x + width <= 1.000001 && y + height <= 1.000001
    }
}

/// Coordinates refer to the assembled, seam-trimmed source image, before the final crop.
public struct CaptureEditMetadata: Codable, Equatable, Sendable {
    public var crop: NormalizedRect?
    public var redactions: [NormalizedRect]
    /// Additional rows removed from the top of a strip; keys are strip UUID strings.
    public var seamTrimPixels: [String: Int]
    public init(crop: NormalizedRect? = nil, redactions: [NormalizedRect] = [],
                seamTrimPixels: [String: Int] = [:]) {
        self.crop = crop; self.redactions = redactions; self.seamTrimPixels = seamTrimPixels
    }
}

public enum CaptureSessionStatus: String, Codable, Sendable {
    case capturing, completed, partial, interrupted
}

public struct CaptureStrip: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let fileName: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let sourceTopPixel: Int
    public let createdAt: Date
    public init(id: UUID = UUID(), fileName: String, pixelWidth: Int, pixelHeight: Int,
                sourceTopPixel: Int = 0, createdAt: Date = Date()) {
        self.id = id; self.fileName = fileName; self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight; self.sourceTopPixel = sourceTopPixel; self.createdAt = createdAt
    }
}

/// Numeric diagnostics only: never image pixels, recognized text, or app names.
public struct CaptureDiagnostics: Codable, Equatable, Sendable {
    public var observedFrames = 0
    public var acceptedFrames = 0
    public var rejectedFrames = 0
    public var regionAttempts = 0
    public var recoveredGaps = 0
    public var provisionalReplacements = 0
    public var skippedSamples = 0
    public var maximumProcessingMilliseconds = 0.0
    public var terminationCause: String?
    public var lastStage = "starting"
    public init() {}
}

/// Brief interruptions may recover only through the stitcher's unchanged
/// trusted references. Waiting itself never grants permission to bridge a gap.
public struct CaptureContinuityPolicy: Sendable {
    public private(set) var rejectedSince: Double?
    public private(set) var consecutiveRejections = 0
    public var isAwaitingBridge: Bool { rejectedSince != nil }
    public init() {}
    public mutating func reject(at now: Double, hasStarted: Bool) -> Bool {
        guard hasStarted else { return false }
        if rejectedSince == nil { rejectedSince = now }
        consecutiveRejections += 1
        return now - (rejectedSince ?? now) >= 8 && consecutiveRejections >= 6
    }
    public mutating func accept() { rejectedSince = nil; consecutiveRejections = 0 }
}

public enum CaptureOutputKind: String, Codable, Sendable { case stitched, singleFrame }

public struct CaptureSessionManifest: Identifiable, Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public var status: CaptureSessionStatus
    public var stopReason: String?
    /// A provisional scene was replaced before scrolling was confirmed; the original intended start is unknown.
    public var startWarning: String?
    public var pixelWidth: Int
    public var strips: [CaptureStrip]
    public var edits: CaptureEditMetadata
    public let configuration: CaptureConfiguration
    public var rejectedFrameCount: Int
    public var isDemo: Bool
    /// Optional additions keep existing schema-1 manifests readable.
    /// Lossless provisional still, atomically published before scrolling is
    /// confirmed; not a strip and never counted as a completed long image.
    public var provisionalFrame: CaptureStrip?
    public var outputKind: CaptureOutputKind?
    public var diagnostics: CaptureDiagnostics?
    public var leadingEdgeStripID: UUID?
    public var trailingEdgeStripID: UUID?
    public var hasImage: Bool { pixelWidth > 0 && pixelHeight > 0 && !strips.isEmpty }
    public var isSingleFrameFallback: Bool { outputKind == .singleFrame }
    public var bodyPixelHeight: Int {
        strips.filter { $0.id != leadingEdgeStripID && $0.id != trailingEdgeStripID }
            .reduce(0) { $0 + $1.pixelHeight }
    }
    public var pixelHeight: Int { strips.reduce(0) { $0 + $1.pixelHeight } }
    public var editedPixelHeight: Int {
        strips.reduce(0) { $0 + $1.pixelHeight - (edits.seamTrimPixels[$1.id.uuidString] ?? 0) }
    }
    public init(id: UUID = UUID(), createdAt: Date = Date(), configuration: CaptureConfiguration = .init(),
                isDemo: Bool = false) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = createdAt
        self.status = .capturing; self.pixelWidth = 0; self.strips = []
        self.edits = .init(); self.configuration = configuration
        self.rejectedFrameCount = 0; self.isDemo = isDemo
    }
}

extension CaptureSessionManifest {
    /// Shared terminal semantics for both capture adapters and storage tests.
    /// An empty manifest must never describe already-preserved image content.
    public mutating func finalizeCapture(reason: String, partial: Bool) {
        status = partial || !hasImage || isSingleFrameFallback ? .partial : .completed
        var actualReason = reason
        if !hasImage || isSingleFrameFallback,
           reason == "捕捉已暂停，已保留成功捕捉的部分。请重新开始下一段。" {
            actualReason = "捕捉已暂停，请重新开始下一段。"
        }
        if !hasImage {
            stopReason = "未写入可用画面。" + " " + actualReason
        } else if isSingleFrameFallback {
            stopReason = "未确认连续滚动，仅保留一张完整单屏。请查看后重新捕捉长图。"
            if partial { stopReason = (stopReason ?? "") + " " + actualReason }
        } else {
            stopReason = actualReason
        }
        if let startWarning, hasImage { stopReason = (stopReason ?? "") + " " + startWarning }
        updatedAt = Date()
    }
}

public enum CaptureExportFormat: String, CaseIterable, Sendable { case png, jpeg }

public enum CaptureStorageError: LocalizedError {
    case missingAppGroup, invalidConfiguration, invalidManifest, sessionStillActive
    case invalidEdits, noImage, imageEncodingFailed, exportTooLarge
    public var errorDescription: String? {
        switch self {
        case .missingAppGroup: return "无法访问共享存储。请检查 App 与广播扩展的 App Group 签名配置。"
        case .invalidConfiguration: return "捕捉设置超出允许范围。"
        case .invalidManifest: return "捕捉记录或图片分块损坏，原文件已保留。"
        case .sessionStillActive: return "请先停止当前捕捉，再编辑或删除。"
        case .invalidEdits: return "裁剪、遮挡或接缝参数无效。"
        case .noImage: return "尚未捕捉到可用画面。"
        case .imageEncodingFailed: return "图片写入失败，请检查剩余空间。"
        case .exportTooLarge: return "图片尺寸超出安全范围，请缩小导出尺寸。"
        }
    }
}
