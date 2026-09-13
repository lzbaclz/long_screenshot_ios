import Foundation

/// Pixel insets are expressed in the dimensions of the supplied analysis frames.
/// Crop fixed navigation, tab bars and other stationary UI before matching.
public struct AlignmentConfiguration: Sendable {
    public var topInset: Int
    public var bottomInset: Int
    public var minimumOverlap: Double
    public var maximumMeanAbsoluteError: Double
    public var ambiguityMargin: Double
    public var maxHistory: Int

    public init(
        topInset: Int = 0,
        bottomInset: Int = 0,
        minimumOverlap: Double = 0.4,
        maximumMeanAbsoluteError: Double = 15,
        ambiguityMargin: Double = 2,
        maxHistory: Int = 3
    ) {
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.minimumOverlap = minimumOverlap
        self.maximumMeanAbsoluteError = maximumMeanAbsoluteError
        self.ambiguityMargin = ambiguityMargin
        self.maxHistory = maxHistory
    }
}

public struct StitchDecision: Equatable, Sendable {
    public enum Status: String, Sendable {
        case started, advanced, unchanged, backtracked, rejected
    }

    public enum Rejection: String, Sendable {
        case insufficientOverlap, ambiguous, geometryChanged, invalidConfiguration
    }

    public let status: Status
    /// Rows to append from THIS frame. Nil means do not append anything.
    /// For the first frame this is the whole configured capture region.
    public let sourceRows: Range<Int>?
    /// Current viewport's position relative to the first accepted viewport.
    /// Negative positions may be visited but never prepend content.
    public let contentOffset: Int
    /// Furthest accepted viewport position, irrespective of subsequent backtracking.
    public let furthestOffset: Int
    public let confidence: Double
    public let rejection: Rejection?
}

/// Conservative streaming vertical alignment. Unknown/ambiguous gaps never append.
/// Memory is bounded by `maxHistory` grayscale frames (hard limit: 8).
/// This type performs no video recording, UI capture, file access or networking.
public struct StreamStitcher: Sendable {
    private struct Reference: Sendable {
        let frame: GrayFrame
        let offset: Int
    }

    private struct Candidate {
        let offset: Int
        let shift: Int
        let referenceIndex: Int
        let error: Double
    }

    public let configuration: AlignmentConfiguration
    public private(set) var contentOffset = 0
    public private(set) var furthestOffset = 0
    public var referenceCount: Int { references.count }
    private var references: [Reference] = []

    public init(configuration: AlignmentConfiguration = .init()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        references.removeAll(keepingCapacity: false)
        contentOffset = 0
        furthestOffset = 0
    }

    public mutating func ingest(_ frame: GrayFrame) -> StitchDecision {
        guard validConfiguration(for: frame) else { return reject(.invalidConfiguration) }
        let bodyHeight = frame.height - configuration.topInset - configuration.bottomInset
        guard let latest = references.last else {
            references.append(Reference(frame: frame, offset: 0))
            return decision(.started, rows: configuration.topInset..<(frame.height - configuration.bottomInset), confidence: 1)
        }
        guard frame.width == latest.frame.width, frame.height == latest.frame.height else {
            return reject(.geometryChanged)
        }

        // Exact cropped equality is safe even for blank or periodic content:
        // its visible pixels are already captured, so never infer hidden progress.
        if identicalBody(latest.frame, frame) {
            return decision(.unchanged, confidence: 1)
        }

        let overlap = Int(ceil(Double(bodyHeight) * configuration.minimumOverlap))
        let maximumShift = bodyHeight - overlap
        var refined: [Candidate] = []

        for (referenceIndex, reference) in references.enumerated() {
            var coarse: [Candidate] = []
            coarse.reserveCapacity(maximumShift * 2 + 1)
            // Search every integer displacement; coarse *spatial* sampling avoids
            // losing a correct odd-pixel shift on sharp text or fine textures.
            for shift in -maximumShift...maximumShift {
                let error = matchError(reference.frame, frame, shift: shift, columns: 16, rows: 24)
                coarse.append(Candidate(offset: reference.offset + shift, shift: shift,
                                        referenceIndex: referenceIndex, error: error))
            }
            coarse.sort(by: candidateOrder)
            for candidate in coarse.prefix(12) {
                let error = matchError(reference.frame, frame, shift: candidate.shift, columns: 48, rows: 96)
                refined.append(Candidate(offset: candidate.offset, shift: candidate.shift,
                                         referenceIndex: referenceIndex, error: error))
            }
        }

        refined.sort(by: candidateOrder)
        guard let best = refined.first,
              best.error <= configuration.maximumMeanAbsoluteError else {
            return reject(.insufficientOverlap)
        }
        // Multiple histories often produce the same coordinate. They support
        // one hypothesis, and must not count as competing positions.
        let alternative = refined.first { $0.offset != best.offset }
        let margin = alternative.map { $0.error - best.error } ?? 255
        guard margin >= configuration.ambiguityMargin else {
            return reject(.ambiguous)
        }

        let quality = max(0, 1 - best.error / configuration.maximumMeanAbsoluteError)
        let separation = min(1, margin / (configuration.ambiguityMargin * 3))
        let confidence = max(0, min(1, 0.65 * quality + 0.35 * separation))
        let previousOffset = contentOffset
        let oldFurthest = furthestOffset
        contentOffset = best.offset
        furthestOffset = max(furthestOffset, best.offset)

        // Keep the most recent trusted view, plus a small bounded history, for
        // short reversals and recovery after temporarily rejected frames.
        references.removeAll { $0.offset == best.offset }
        references.append(Reference(frame: frame, offset: best.offset))
        if references.count > configuration.maxHistory {
            references.removeFirst(references.count - configuration.maxHistory)
        }

        if best.offset > oldFurthest {
            let addedRows = best.offset - oldFurthest
            // A trusted overlap with any prior accepted view ensures continuity.
            // Use only the previously unseen tail even after backtracking.
            let end = frame.height - configuration.bottomInset
            return decision(.advanced, rows: (end - addedRows)..<end, confidence: confidence)
        }
        if best.offset == previousOffset {
            return decision(.unchanged, confidence: confidence)
        }
        return decision(.backtracked, confidence: confidence)
    }

    private func validConfiguration(for frame: GrayFrame) -> Bool {
        guard configuration.topInset >= 0, configuration.bottomInset >= 0,
              configuration.topInset < frame.height,
              configuration.bottomInset < frame.height - configuration.topInset,
              frame.height - configuration.topInset - configuration.bottomInset >= 12,
              configuration.minimumOverlap.isFinite,
              (0.2...0.9).contains(configuration.minimumOverlap),
              configuration.maximumMeanAbsoluteError.isFinite,
              (0.1...64).contains(configuration.maximumMeanAbsoluteError),
              configuration.ambiguityMargin.isFinite,
              (0.1...64).contains(configuration.ambiguityMargin),
              (1...8).contains(configuration.maxHistory) else { return false }
        return true
    }

    private func identicalBody(_ a: GrayFrame, _ b: GrayFrame) -> Bool {
        let start = configuration.topInset * a.width
        let end = (a.height - configuration.bottomInset) * a.width
        return a.pixels[start..<end].elementsEqual(b.pixels[start..<end])
    }

    /// Robust sampled mean absolute error: retain most of the raw error, while
    /// reducing the effect of a small number of animated/temporarily loaded rows.
    private func matchError(_ reference: GrayFrame, _ current: GrayFrame,
                            shift: Int, columns: Int, rows: Int) -> Double {
        let height = current.height - configuration.topInset - configuration.bottomInset
        let overlap = height - abs(shift)
        let rowCount = min(rows, overlap)
        let columnCount = min(columns, current.width)
        let referenceStart = configuration.topInset + max(shift, 0)
        let currentStart = configuration.topInset + max(-shift, 0)
        var rowErrors: [Double] = []
        rowErrors.reserveCapacity(rowCount)

        for rowIndex in 0..<rowCount {
            let y = rowCount == 1 ? 0 : rowIndex * (overlap - 1) / (rowCount - 1)
            let referenceRow = (referenceStart + y) * reference.width
            let currentRow = (currentStart + y) * current.width
            var total = 0
            for columnIndex in 0..<columnCount {
                let x = columnCount == 1 ? 0 : columnIndex * (current.width - 1) / (columnCount - 1)
                total += abs(Int(reference.pixels[referenceRow + x]) - Int(current.pixels[currentRow + x]))
            }
            rowErrors.append(Double(total) / Double(columnCount))
        }
        let mean = rowErrors.reduce(0, +) / Double(rowCount)
        rowErrors.sort()
        let retainedCount = max(1, Int(Double(rowCount) * 0.85))
        let trimmed = rowErrors.prefix(retainedCount).reduce(0, +) / Double(retainedCount)
        return mean * 0.35 + trimmed * 0.65
    }

    private func candidateOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.error != rhs.error { return lhs.error < rhs.error }
        if abs(lhs.offset - contentOffset) != abs(rhs.offset - contentOffset) {
            return abs(lhs.offset - contentOffset) < abs(rhs.offset - contentOffset)
        }
        if lhs.offset != rhs.offset { return lhs.offset < rhs.offset }
        return lhs.referenceIndex > rhs.referenceIndex
    }

    private func decision(_ status: StitchDecision.Status, rows: Range<Int>? = nil,
                          confidence: Double = 0, rejection: StitchDecision.Rejection? = nil) -> StitchDecision {
        StitchDecision(status: status, sourceRows: rows, contentOffset: contentOffset,
                       furthestOffset: furthestOffset, confidence: confidence, rejection: rejection)
    }

    private func reject(_ reason: StitchDecision.Rejection) -> StitchDecision {
        decision(.rejected, rejection: reason)
    }
}
