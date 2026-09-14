import Foundation

public enum CaptureProcessingStage: String, CaseIterable, Sendable {
    case grayConversion, foregroundRegistration, alignment, frameRendering
    case provisionalRead, provisionalWrite, stripCommit, manifestWrite
}

/// Only bounded numeric aggregates are retained; no sample pixels or text.
public struct CaptureStageTiming: Codable, Equatable, Sendable {
    public private(set) var count = 0
    public private(set) var totalMilliseconds = 0.0
    public private(set) var maximumMilliseconds = 0.0
    public var meanMilliseconds: Double { count > 0 ? totalMilliseconds / Double(count) : 0 }
    public init() {}
    mutating func record(seconds: Double) {
        guard seconds.isFinite, seconds >= 0, count < 1_000_000 else { return }
        let milliseconds = seconds * 1_000
        guard milliseconds.isFinite else { return }
        count += 1; totalMilliseconds += milliseconds
        maximumMilliseconds = max(maximumMilliseconds, milliseconds)
    }
}

public struct CaptureStageTimings: Codable, Equatable, Sendable {
    public private(set) var values: [String: CaptureStageTiming] = [:]
    public init() {}
    public mutating func record(_ stage: CaptureProcessingStage, seconds: Double) {
        var value = values[stage.rawValue] ?? .init()
        value.record(seconds: seconds); values[stage.rawValue] = value
    }
    public subscript(_ stage: CaptureProcessingStage) -> CaptureStageTiming? { values[stage.rawValue] }

    /// The adapter owns conversion/commit/manifest timing and the pipeline owns
    /// matching/rendering/provisional timing. Overlay their disjoint aggregates;
    /// repeatedly publishing a manifest must not count the same work twice.
    public static func combined(pipeline: Self?, adapter: Self) -> Self {
        var result = pipeline ?? .init()
        for (key, value) in adapter.values { result.values[key] = value }
        return result
    }
}
