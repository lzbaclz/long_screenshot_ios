import Foundation

/// Chooses which original frame supplies rows at a trusted document boundary.
/// Both patches MUST describe the same document coordinates in the same order.
/// `retained` is the actual composed body frontier, possibly from several strips,
/// not merely an alignment reference. Neither patch may include fixed outer caps.
/// This scorer never estimates motion, blends pixels, or authorizes extra rows.
public enum SeamSelector {
    public enum Direction: Sendable { case prepend, append }

    public enum Reason: String, Equatable, Sendable {
        case selected, identicalOverlap, defaultAlreadyQuiet
        case noSafeCandidate, insufficientGain, invalidGeometry, insufficientOverlap
    }

    public struct Metrics: Equatable, Sendable {
        public let pixelDifference: Double
        public let structureOccupancy: Double
        public let verticalActivity: Double

        public var score: Double {
            // A zero-error opaque icon is still a poor place to split a glass
            // card. Occupied structure dominates small background mismatches.
            pixelDifference + 120 * min(1, structureOccupancy / 0.08)
                + 8 * min(16, verticalActivity)
        }

        fileprivate var quiet: Bool { structureOccupancy <= 0.02 && verticalActivity <= 2.5 }
        fileprivate static let zero = Metrics(pixelDifference: 0, structureOccupancy: 0, verticalActivity: 0)
    }

    public struct Decision: Equatable, Sendable {
        /// Nonnegative count of old BODY rows replaced by incoming BODY rows.
        /// Prepend moves the boundary down; append moves it up.
        public let shift: Int
        public let defaultRow: Int
        public let selectedRow: Int
        public let defaultScore: Double
        public let selectedScore: Double
        public let candidateCount: Int
        public let reason: Reason
        public let defaultMetrics: Metrics
        public let selectedMetrics: Metrics
    }

    /// Searches at most 480 rows and 35% of the available, aligned body overlap.
    /// `overlapLength` is the complete trusted overlap, which may exceed these
    /// bounded frontier patches. Only the searched rows plus a six-row halo
    /// need loading. Nil uses the patch height as the overlap length.
    /// The caller additionally limits `maximumShift` to its safe trim capacity.
    /// Boundaries are exclusive row positions: 0 for prepend, height for append.
    public static func select(retained: GrayFrame, incoming: GrayFrame, direction: Direction,
                              overlapLength: Int? = nil, maximumShift: Int = 480) -> Decision {
        let height = retained.height
        let defaultRow = direction == .prepend ? 0 : height
        func fallback(_ reason: Reason, metrics: Metrics = .zero, count: Int = 0) -> Decision {
            Decision(shift: 0, defaultRow: defaultRow, selectedRow: defaultRow,
                     defaultScore: metrics.score, selectedScore: metrics.score, candidateCount: count,
                     reason: reason, defaultMetrics: metrics, selectedMetrics: metrics)
        }
        guard retained.width == incoming.width, height == incoming.height,
              retained.width >= 12 else { return fallback(.invalidGeometry) }
        let overlap = overlapLength ?? height
        guard overlap >= height else { return fallback(.invalidGeometry) }
        guard height >= 24, maximumShift > 0 else { return fallback(.insufficientOverlap) }
        let radius = 6
        let overlapLimit = overlap / 100 * 35 + overlap % 100 * 35 / 100
        let limit = min(480, maximumShift, overlapLimit, height - radius)
        guard limit > 0 else { return fallback(.insufficientOverlap) }
        // Preserve ordinary translated documents exactly, including their
        // textured rows. No criterion should move a seam with zero benefit.
        if retained.pixels == incoming.pixels { return fallback(.identicalOverlap) }

        let range = direction == .prepend
            ? 0..<min(height, limit + radius)
            : max(0, height - limit - radius)..<height
        var rows: [Metrics] = []
        rows.reserveCapacity(range.count)
        for row in range { rows.append(rowMetrics(retained: retained, incoming: incoming, row: row)) }
        func metrics(at boundary: Int) -> Metrics {
            let first = max(range.lowerBound, boundary - radius)
            let last = min(range.upperBound, boundary + radius)
            var difference = 0.0, structure = 0.0, vertical = 0.0
            for row in first..<last {
                let value = rows[row - range.lowerBound]
                difference += value.pixelDifference
                // Demand an actual quiet neighborhood, not a single white
                // scanline through an icon, a label, or a rounded card edge.
                structure = max(structure, value.structureOccupancy)
                vertical = max(vertical, value.verticalActivity)
            }
            return Metrics(pixelDifference: difference / Double(last - first),
                           structureOccupancy: structure, verticalActivity: vertical)
        }
        let baseline = metrics(at: defaultRow)
        guard !baseline.quiet else { return fallback(.defaultAlreadyQuiet, metrics: baseline, count: 1) }
        // Tiny grayscale conversion/quantization changes in an otherwise
        // ordinary document do not justify replacing already retained pixels.
        guard baseline.pixelDifference > 1 else { return fallback(.insufficientGain, metrics: baseline, count: 1) }
        var best: (shift: Int, row: Int, metrics: Metrics)?
        for shift in 1...limit {
            let row = direction == .prepend ? shift : height - shift
            let candidate = metrics(at: row)
            guard candidate.quiet else { continue }
            // Strict improvement plus ascending shifts makes ties favor the
            // existing boundary. This has no dependence on fixture geometry.
            if best == nil || candidate.score < best!.metrics.score - 0.000_001 {
                best = (shift, row, candidate)
            }
        }
        guard let best else { return fallback(.noSafeCandidate, metrics: baseline, count: limit + 1) }
        let gain = baseline.score - best.metrics.score
        guard gain >= 8, gain >= baseline.score * 0.15 else {
            return fallback(.insufficientGain, metrics: baseline, count: limit + 1)
        }
        return Decision(shift: best.shift, defaultRow: defaultRow, selectedRow: best.row,
                        defaultScore: baseline.score, selectedScore: best.metrics.score, candidateCount: limit + 1,
                        reason: .selected, defaultMetrics: baseline, selectedMetrics: best.metrics)
    }

    private static func rowMetrics(retained: GrayFrame, incoming: GrayFrame, row: Int) -> Metrics {
        let width = retained.width
        // Bounded samples at native or analysis width; the horizontal probe
        // spacing scales with width so subpixel antialiasing is not structure.
        let step = max(1, width / 144)
        let lower = step, upper = width - step
        let count = min(144, upper - lower)
        let y0 = max(0, row - 1), y1 = min(retained.height - 1, row + 1)
        var difference = 0, occupied = 0, vertical = 0
        for sample in 0..<count {
            let x = lower + sample * (upper - lower - 1) / max(1, count - 1)
            let i = row * width + x
            let a = Int(retained.pixels[i]), b = Int(incoming.pixels[i])
            difference += abs(a - b)
            let aHorizontal = max(abs(a - Int(retained.pixels[i + step])), abs(a - Int(retained.pixels[i - step])))
            let bHorizontal = max(abs(b - Int(incoming.pixels[i + step])), abs(b - Int(incoming.pixels[i - step])))
            // Low-contrast glass can have real boundaries below eight gray
            // levels. A weaker gradient must also bend locally; smooth ramps
            // and +/-1 quantization noise do not qualify. Both differences are
            // invariant to inversion and an unclipped global brightness shift.
            let aCurvature = abs(2 * a - Int(retained.pixels[i + step]) - Int(retained.pixels[i - step]))
            let bCurvature = abs(2 * b - Int(incoming.pixels[i + step]) - Int(incoming.pixels[i - step]))
            if max(aHorizontal, bHorizontal) >= 8
                || (aHorizontal >= 3 && aCurvature >= 3)
                || (bHorizontal >= 3 && bCurvature >= 3) { occupied += 1 }
            let aVertical = max(abs(a - Int(retained.pixels[y1 * width + x])), abs(a - Int(retained.pixels[y0 * width + x])))
            let bVertical = max(abs(b - Int(incoming.pixels[y1 * width + x])), abs(b - Int(incoming.pixels[y0 * width + x])))
            vertical += max(aVertical, bVertical)
        }
        return Metrics(pixelDifference: Double(difference) / Double(count),
                       structureOccupancy: Double(occupied) / Double(count),
                       verticalActivity: Double(vertical) / Double(count))
    }
}
