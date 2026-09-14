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
    public enum Placement: String, Sendable {
        case append, prepend
    }

    public enum Status: String, Sendable {
        case started, advanced, unchanged, backtracked, rejected
    }

    public enum Rejection: String, Sendable {
        case insufficientOverlap, ambiguous, geometryChanged, invalidConfiguration
    }

    public let status: Status
    /// New rows from THIS frame, in top-to-bottom order. Insert at `placement`.
    /// Nil means the captured image must remain unchanged.
    /// For the first frame this is the whole configured capture region.
    public let sourceRows: Range<Int>?
    /// Where to insert `sourceRows`. Defaults to append when there are no rows.
    public let placement: Placement
    /// Current viewport's position relative to the first accepted viewport.
    public let contentOffset: Int
    /// Earliest accepted viewport position, irrespective of subsequent movement.
    public let earliestOffset: Int
    /// Furthest accepted viewport position, irrespective of subsequent movement.
    /// The captured interval is earliestOffset..<(furthestOffset + bodyHeight).
    public let furthestOffset: Int
    public let confidence: Double
    public let rejection: Rejection?

    public init(status: Status, sourceRows: Range<Int>?, contentOffset: Int,
                furthestOffset: Int, confidence: Double, rejection: Rejection?,
                placement: Placement = .append, earliestOffset: Int = 0) {
        self.status = status
        self.sourceRows = sourceRows
        self.placement = sourceRows == nil ? .append : placement
        self.contentOffset = contentOffset
        self.earliestOffset = earliestOffset
        self.furthestOffset = furthestOffset
        self.confidence = confidence
        self.rejection = rejection
    }
}

/// Conservative bidirectional vertical alignment. Unknown/ambiguous gaps never add rows.
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
        let hasDistributedDetail: Bool
    }

    private struct MatchScore {
        let error: Double
        let hasDistributedDetail: Bool
    }

    public let configuration: AlignmentConfiguration
    public private(set) var contentOffset = 0
    public private(set) var earliestOffset = 0
    public private(set) var furthestOffset = 0
    public var referenceCount: Int { references.count }
    private var references: [Reference] = []

    public init(configuration: AlignmentConfiguration = .init()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        references.removeAll(keepingCapacity: false)
        contentOffset = 0
        earliestOffset = 0
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
                let score = matchScore(reference.frame, frame, shift: shift, columns: 16, rows: 24)
                coarse.append(Candidate(offset: reference.offset + shift, shift: shift,
                                        referenceIndex: referenceIndex, error: score.error,
                                        hasDistributedDetail: score.hasDistributedDetail))
            }
            coarse.sort(by: candidateOrder)
            for candidate in coarse.prefix(12) {
                let score = matchScore(reference.frame, frame, shift: candidate.shift, columns: 48, rows: 96)
                refined.append(Candidate(offset: candidate.offset, shift: candidate.shift,
                                         referenceIndex: referenceIndex, error: score.error,
                                         hasDistributedDetail: score.hasDistributedDetail))
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
        // A blank overlap or one animated marker cannot establish a unique
        // document position, even if its absolute pixel error happens to be low.
        guard best.hasDistributedDetail else { return reject(.ambiguous) }

        let quality = max(0, 1 - best.error / configuration.maximumMeanAbsoluteError)
        let separation = min(1, margin / (configuration.ambiguityMargin * 3))
        let confidence = max(0, min(1, 0.65 * quality + 0.35 * separation))
        let previousOffset = contentOffset
        let oldEarliest = earliestOffset
        let oldFurthest = furthestOffset
        contentOffset = best.offset
        earliestOffset = min(earliestOffset, best.offset)
        furthestOffset = max(furthestOffset, best.offset)

        // Keep the most recent trusted view, plus a small bounded history, for
        // short reversals and recovery after temporarily rejected frames.
        references.removeAll { $0.offset == best.offset }
        references.append(Reference(frame: frame, offset: best.offset))
        if references.count > configuration.maxHistory {
            references.removeFirst(references.count - configuration.maxHistory)
        }

        if best.offset < oldEarliest {
            let addedRows = oldEarliest - best.offset
            // A trusted overlap keeps both ends continuous, even when the
            // first viewport and the old boundary references have been evicted.
            let start = configuration.topInset
            return decision(.advanced, rows: start..<(start + addedRows),
                            placement: .prepend, confidence: confidence)
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

    /// Compare both raw pixels and horizontally detailed pixels. Blank rows
    /// must not dilute competing text alignments into equally good matches.
    /// Trimming limits transient row animations; spatial support prevents a
    /// single icon or narrow scroll indicator from authorizing a join.
    private func matchScore(_ reference: GrayFrame, _ current: GrayFrame,
                            shift: Int, columns: Int, rows: Int) -> MatchScore {
        let height = current.height - configuration.topInset - configuration.bottomInset
        let overlap = height - abs(shift)
        let rowCount = min(rows, overlap)
        let columnCount = min(columns, current.width)
        let referenceStart = configuration.topInset + max(shift, 0)
        let currentStart = configuration.topInset + max(-shift, 0)
        var rowErrors: [Double] = []
        rowErrors.reserveCapacity(rowCount)
        var detailErrors: [Double] = []
        var firstDetailRow: Int?
        var lastDetailRow = 0
        let edgeInset = max(1, current.width / 24)

        for rowIndex in 0..<rowCount {
            let y = rowCount == 1 ? 0 : rowIndex * (overlap - 1) / (rowCount - 1)
            let referenceRow = (referenceStart + y) * reference.width
            let currentRow = (currentStart + y) * current.width
            var total = 0
            var detailTotal = 0
            var detailCount = 0
            var firstDetailColumn = current.width
            var lastDetailColumn = 0
            for columnIndex in 0..<columnCount {
                let x = columnCount == 1 ? 0 : columnIndex * (current.width - 1) / (columnCount - 1)
                let referenceValue = Int(reference.pixels[referenceRow + x])
                let currentValue = Int(current.pixels[currentRow + x])
                let difference = abs(referenceValue - currentValue)
                total += difference
                guard x >= edgeInset, x < current.width - edgeInset else { continue }
                let referenceDetail = max(abs(referenceValue - Int(reference.pixels[referenceRow + x - 1])),
                                          abs(referenceValue - Int(reference.pixels[referenceRow + x + 1])))
                let currentDetail = max(abs(currentValue - Int(current.pixels[currentRow + x - 1])),
                                        abs(currentValue - Int(current.pixels[currentRow + x + 1])))
                if max(referenceDetail, currentDetail) >= 16 {
                    detailTotal += difference
                    detailCount += 1
                    firstDetailColumn = min(firstDetailColumn, x)
                    lastDetailColumn = max(lastDetailColumn, x)
                }
            }
            rowErrors.append(Double(total) / Double(columnCount))
            if detailCount >= 3 && lastDetailColumn - firstDetailColumn >= current.width / 6 {
                detailErrors.append(Double(detailTotal) / Double(detailCount))
                if firstDetailRow == nil { firstDetailRow = y }
                lastDetailRow = y
            }
        }
        let raw = robustError(rowErrors)
        let error = detailErrors.isEmpty ? raw : raw * 0.35 + robustError(detailErrors) * 0.65
        let distributed = detailErrors.count >= 4
            && lastDetailRow - (firstDetailRow ?? lastDetailRow) >= overlap / 4
        return MatchScore(error: error, hasDistributedDetail: distributed)
    }

    private func robustError(_ errors: [Double]) -> Double {
        let mean = errors.reduce(0, +) / Double(errors.count)
        let retainedCount = max(1, Int(Double(errors.count) * 0.85))
        let trimmed = errors.sorted().prefix(retainedCount).reduce(0, +) / Double(retainedCount)
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
                          placement: StitchDecision.Placement = .append,
                          confidence: Double = 0, rejection: StitchDecision.Rejection? = nil) -> StitchDecision {
        StitchDecision(status: status, sourceRows: rows, contentOffset: contentOffset,
                       furthestOffset: furthestOffset, confidence: confidence, rejection: rejection,
                       placement: placement, earliestOffset: earliestOffset)
    }

    private func reject(_ reason: StitchDecision.Rejection) -> StitchDecision {
        decision(.rejected, rejection: reason)
    }
}
