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

/// Shared matching evidence for the stitcher and automatic-region verifier.
/// A narrow row can be informative without spanning a fraction of the screen:
/// it must contain separate horizontal structures, not merely the two edges
/// of one 1–3 pixel indicator. Returned bounds never authorize output cropping.
enum AlignmentDetailSupport {
    static func horizontalSpan(in frame: GrayFrame, row: Int) -> Range<Int>? {
        let edge = max(1, frame.width / 24)
        guard row >= 0, row < frame.height, frame.width > edge * 2 else { return nil }
        let start = row * frame.width
        var first: Int?
        var last = 0
        var count = 0
        var separateStructures = false
        for x in edge..<(frame.width - edge) {
            let value = Int(frame.pixels[start + x])
            let detail = max(abs(value - Int(frame.pixels[start + x - 1])),
                             abs(value - Int(frame.pixels[start + x + 1])))
            if detail >= 16 {
                if first == nil { first = x }
                else if x - last >= 3 { separateStructures = true }
                last = x
                count += 1
            }
        }
        // A flat rectangle contributes only two step edges (at most four
        // gradient pixels). Its loading/unloading is not text-like structure.
        guard let first, count > 4,
              last - first >= frame.width / 6 || separateStructures else { return nil }
        return first..<(last + 1)
    }
}

/// Conservative bidirectional vertical alignment. Unknown/ambiguous gaps never add rows.
/// Memory is bounded by `maxHistory` grayscale frames (hard limit: 8).
/// This type performs no video recording, UI capture, file access or networking.
public struct StreamStitcher: Sendable {
    private struct Reference: Sendable {
        let frame: GrayFrame
        let offset: Int
        /// One optional pair of bounds per row, shared with the frame's lifetime.
        let detailSpans: [Range<Int>?]
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
    /// Numeric evidence from this ingest only; no additional frame is retained.
    public private(set) var lastForegroundRegistration: ForegroundMotionRegistration.Result?
    public var referenceCount: Int { references.count }
    /// Internal accounting for bounded-memory regression tests.
    var cachedDetailRowCount: Int { references.reduce(0) { $0 + $1.detailSpans.count } }
    private var references: [Reference] = []

    public init(configuration: AlignmentConfiguration = .init()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        references.removeAll(keepingCapacity: false)
        contentOffset = 0
        earliestOffset = 0
        furthestOffset = 0
        lastForegroundRegistration = nil
    }

    public mutating func ingest(_ frame: GrayFrame) -> StitchDecision {
        lastForegroundRegistration = nil
        guard validConfiguration(for: frame) else { return reject(.invalidConfiguration) }
        let bodyHeight = frame.height - configuration.topInset - configuration.bottomInset
        guard let latest = references.last else {
            references.append(Reference(frame: frame, offset: 0, detailSpans: detailSpans(for: frame)))
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
        let currentDetailSpans = detailSpans(for: frame)
        var refined: [Candidate] = []
        var sawStationaryLayer = false
        var foregroundConfidence: Double?

        for referenceIndex in references.indices.reversed() {
            let reference = references[referenceIndex]
            let previousForegroundEvidence = lastForegroundRegistration
            let foreground = ForegroundMotionRegistration.analyze(reference: reference.frame, current: frame,
                                                                    configuration: configuration)
            if foreground.status != .notLayered || !sawStationaryLayer {
                lastForegroundRegistration = foreground
            }
            if foreground.status == .matched, let shift = foreground.displacement {
                // The stationary layer cannot outvote verified foreground with
                // a zero/one-pixel whole-screen match. Latest trusted overlap
                // suffices; older references remain available after rejections.
                refined = [.init(offset: reference.offset + shift, shift: shift, referenceIndex: referenceIndex,
                                 error: (1 - foreground.confidence) * configuration.maximumMeanAbsoluteError,
                                 hasDistributedDetail: true)]
                foregroundConfidence = foreground.confidence
                break
            }
            if foreground.status == .rejected {
                // An older viewport can have no usable overlap even though a
                // newer reference already explains every overlapping pixel.
                // Keep its full candidate set (including ambiguity rivals);
                // an old layered rejection must not erase that exact proof.
                if refined.contains(where: { candidate in
                    candidate.shift != 0 && exactOverlap(references[candidate.referenceIndex].frame, frame,
                                                          shift: candidate.shift)
                }) {
                    lastForegroundRegistration = previousForegroundEvidence
                    continue
                }
                sawStationaryLayer = true
                refined.removeAll()
                continue
            }
            if foreground.status == .unchanged {
                refined = [.init(offset: reference.offset, shift: 0, referenceIndex: referenceIndex,
                                 error: 0, hasDistributedDetail: true)]
                foregroundConfidence = 1
                break
            }
            if sawStationaryLayer { continue }
            var coarse: [Candidate] = []
            coarse.reserveCapacity(maximumShift * 2 + 1)
            // Search every integer displacement; coarse *spatial* sampling avoids
            // losing a correct odd-pixel shift on sharp text or fine textures.
            for shift in -maximumShift...maximumShift {
                let score = matchScore(reference, frame, currentDetailSpans: currentDetailSpans,
                                       shift: shift, columns: 16, rows: 24)
                coarse.append(Candidate(offset: reference.offset + shift, shift: shift,
                                        referenceIndex: referenceIndex, error: score.error,
                                        hasDistributedDetail: score.hasDistributedDetail))
            }
            coarse.sort(by: candidateOrder)
            for candidate in coarse.prefix(12) {
                let score = matchScore(reference, frame, currentDetailSpans: currentDetailSpans,
                                       shift: candidate.shift, columns: 48, rows: 96)
                refined.append(Candidate(offset: candidate.offset, shift: candidate.shift,
                                         referenceIndex: referenceIndex, error: score.error,
                                         hasDistributedDetail: score.hasDistributedDetail))
            }
        }

        if refined.isEmpty && sawStationaryLayer { return reject(.ambiguous) }
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
        let confidence = foregroundConfidence ?? max(0, min(1, 0.65 * quality + 0.35 * separation))
        let previousOffset = contentOffset
        let oldEarliest = earliestOffset
        let oldFurthest = furthestOffset
        contentOffset = best.offset
        earliestOffset = min(earliestOffset, best.offset)
        furthestOffset = max(furthestOffset, best.offset)

        // Keep the most recent trusted view, plus a small bounded history, for
        // short reversals and recovery after temporarily rejected frames.
        references.removeAll { $0.offset == best.offset }
        references.append(Reference(frame: frame, offset: best.offset, detailSpans: currentDetailSpans))
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

    private func exactOverlap(_ a: GrayFrame, _ b: GrayFrame, shift: Int) -> Bool {
        let bodyHeight = a.height - configuration.topInset - configuration.bottomInset
        let overlap = bodyHeight - abs(shift)
        guard overlap > 0 else { return false }
        let startA = (configuration.topInset + max(shift, 0)) * a.width
        let startB = (configuration.topInset + max(-shift, 0)) * b.width
        return a.pixels[startA..<(startA + overlap * a.width)]
            .elementsEqual(b.pixels[startB..<(startB + overlap * b.width)])
    }

    private func detailSpans(for frame: GrayFrame) -> [Range<Int>?] {
        (0..<frame.height).map { AlignmentDetailSupport.horizontalSpan(in: frame, row: $0) }
    }

    /// Compare both raw pixels and horizontally detailed pixels. Blank rows
    /// must not dilute competing text alignments into equally good matches.
    /// Trimming limits transient row animations; spatial support prevents a
    /// single icon or narrow scroll indicator from authorizing a join.
    private func matchScore(_ reference: Reference, _ current: GrayFrame,
                            currentDetailSpans: [Range<Int>?],
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
        var supportedRows = 0
        var firstDetailRow: Int?
        var lastDetailRow = 0

        for rowIndex in 0..<rowCount {
            // Pair samples across the overlap midpoint. Flooring each index
            // independently selects different physical rows after a vertical
            // mirror, which can hide sparse text/detail in only one layout.
            // Keep the same sample count; short overlaps still visit every row.
            let pairedIndex = min(rowIndex, rowCount - 1 - rowIndex)
            let leadingY = rowCount == 1 ? 0 : pairedIndex * (overlap - 1) / (rowCount - 1)
            let y = rowIndex * 2 < rowCount ? leadingY : overlap - 1 - leadingY
            let referenceRow = (referenceStart + y) * reference.frame.width
            let currentRow = (currentStart + y) * current.width
            var total = 0
            for columnIndex in 0..<columnCount {
                let x = columnCount == 1 ? 0 : columnIndex * (current.width - 1) / (columnCount - 1)
                let referenceValue = Int(reference.frame.pixels[referenceRow + x])
                let currentValue = Int(current.pixels[currentRow + x])
                total += abs(referenceValue - currentValue)
            }
            rowErrors.append(Double(total) / Double(columnCount))
            let referenceSpan = reference.detailSpans[referenceStart + y]
            let currentSpan = currentDetailSpans[currentStart + y]
            // Penalize detail against blank space too: otherwise a wrong
            // displacement can win by avoiding all shared text rows. Actual
            // spatial support still requires structure in both input rows.
            if let first = referenceSpan ?? currentSpan {
                detailErrors.append(detailError(reference.frame, row: referenceRow, span: referenceSpan ?? first,
                                                 current, row: currentRow, span: currentSpan ?? first, columns: columns))
            }
            if referenceSpan != nil && currentSpan != nil {
                supportedRows += 1
                if firstDetailRow == nil { firstDetailRow = y }
                lastDetailRow = y
            }
        }
        let raw = robustError(rowErrors)
        let error = detailErrors.isEmpty ? raw : raw * 0.35 + robustError(detailErrors) * 0.65
        let distributed = supportedRows >= 4
            && lastDetailRow - (firstDetailRow ?? lastDetailRow) >= overlap / 4
        return MatchScore(error: error, hasDistributedDetail: distributed)
    }

    /// Spend the fixed detail-sampling budget inside informative bounds from
    /// both rows. Disjoint left/right bubbles do not turn the blank space
    /// between them into evidence, and neither input gets preferential sampling.
    private func detailError(_ reference: GrayFrame, row referenceRow: Int, span referenceSpan: Range<Int>,
                             _ current: GrayFrame, row currentRow: Int, span currentSpan: Range<Int>,
                             columns: Int) -> Double {
        var first = referenceSpan
        var second: Range<Int>?
        let left = referenceSpan.lowerBound <= currentSpan.lowerBound ? referenceSpan : currentSpan
        let right = referenceSpan.lowerBound <= currentSpan.lowerBound ? currentSpan : referenceSpan
        if left.upperBound >= right.lowerBound {
            first = left.lowerBound..<max(left.upperBound, right.upperBound)
        } else {
            first = left; second = right
        }
        let available = first.count + (second?.count ?? 0)
        let count = min(columns, available)
        var total = 0
        for index in 0..<count {
            let position = count == 1 ? 0 : index * (available - 1) / (count - 1)
            let x = position < first.count ? first.lowerBound + position
                : (second?.lowerBound ?? first.upperBound) + position - first.count
            total += abs(Int(reference.pixels[referenceRow + x]) - Int(current.pixels[currentRow + x]))
        }
        return Double(total) / Double(count)
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
