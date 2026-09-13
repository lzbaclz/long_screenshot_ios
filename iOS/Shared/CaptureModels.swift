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
