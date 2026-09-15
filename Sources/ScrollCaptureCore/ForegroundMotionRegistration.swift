import Foundation

/// Registration of moving, opaque foreground over a textured stationary layer.
/// No output pixels are synthesized: callers still retain original frame strips.
public enum ForegroundMotionRegistration {
    public enum Status: String, Sendable { case notLayered, unchanged, matched, rejected }

    public struct Result: Sendable {
        public let status: Status
        public let displacement: Int?
        public let confidence: Double
        public let rejection: StitchDecision.Rejection?
        /// An interior supported by moving foreground, not a fixed-UI classifier.
        /// Outer pixels must be preserved when this region is used automatically.
        public let matchingInsets: FixedRegionDetector.Insets?
        public let candidateCount: Int
        public let supportCount: Int
    }

    private struct Point { let x: Int; let y: Int; let strength: Int }
    private struct Feature { let x: Int; let y: Int; let hashes: (UInt64, UInt64) }
    private struct Key: Hashable { let x: Int; let hash: UInt64; let phase: Int }
    private struct Bucket { var indices: [Int]; var firstY: Int; var lastY: Int }
    private struct Score {
        let shift: Int
        let error: Double
        let support: Int
        let valid: Bool
        let firstRow: Int
        let lastRow: Int
    }

    /// Motion features, validation and overlap always stay inside configuration.
    /// An automatic foreground capture may explicitly retain its original
    /// allowed source range for stationary context after narrowing the ROI.
    /// Nil preserves ROI-only analysis. Every pair revalidates this context;
    /// a prior layer classification is never carried forward as evidence.
    public static func analyze(reference: GrayFrame, current: GrayFrame,
                               configuration: AlignmentConfiguration = .init(),
                               stationaryEvidenceRows: Range<Int>? = nil) -> Result {
        func result(_ status: Status, rejection: StitchDecision.Rejection? = nil,
                    candidates: Int = 0) -> Result {
            .init(status: status, displacement: nil, confidence: status == .unchanged ? 1 : 0, rejection: rejection,
                  matchingInsets: nil, candidateCount: candidates, supportCount: 0)
        }
        guard reference.width == current.width, reference.height == current.height else {
            return result(.rejected, rejection: .geometryChanged)
        }
        let width = current.width, height = current.height
        let top = configuration.topInset, bottom = configuration.bottomInset
        guard top >= 0, top < height, bottom >= 0, bottom < height - top,
              configuration.minimumOverlap.isFinite, (0.2...0.9).contains(configuration.minimumOverlap),
              configuration.maximumMeanAbsoluteError.isFinite, (0.1...64).contains(configuration.maximumMeanAbsoluteError),
              configuration.ambiguityMargin.isFinite, (0.1...64).contains(configuration.ambiguityMargin) else {
            return result(.rejected, rejection: .invalidConfiguration)
        }
        let end = height - bottom
        let evidenceRows = stationaryEvidenceRows ?? top..<end
        guard evidenceRows.lowerBound >= 0, evidenceRows.upperBound <= height,
              evidenceRows.lowerBound <= top, evidenceRows.upperBound >= end else {
            return result(.rejected, rejection: .invalidConfiguration)
        }
        guard end - top >= 12, width >= 12 else { return result(.notLayered) }
        let firstPixel = top * width, lastPixel = end * width
        if reference.pixels[firstPixel..<lastPixel].elementsEqual(current.pixels[firstPixel..<lastPixel]) {
            return result(.unchanged)
        }
        var changed = [Bool](repeating: false, count: width * height)
        var changedCount = 0
        for index in firstPixel..<lastPixel {
            changed[index] = abs(Int(reference.pixels[index]) - Int(current.pixels[index])) >= 8
            if changed[index] { changedCount += 1 }
        }
        // Constant white background is not evidence for a stationary texture
        // layer. Require unchanged 2D detail distributed through the viewport.
        let edge = max(4, width / 24)
        var detailed = 0
        var stablePatterns: [UInt64: (count: Int, bands: Set<Int>, firstX: Int, lastX: Int)] = [:]
        for y in stride(from: evidenceRows.lowerBound + 8, to: evidenceRows.upperBound - 8, by: 4) {
            for x in stride(from: edge, to: width - edge, by: 2) {
                let p = y * width + x
                let probes = [p, p - 4, p + 4, p - width * 8, p + width * 8]
                let values = probes.map { Int(reference.pixels[$0]) }
                let horizontal = max(values[0], values[1], values[2]) - min(values[0], values[1], values[2])
                let vertical = max(values[0], values[3], values[4]) - min(values[0], values[3], values[4])
                guard horizontal >= 8, vertical >= 4 else { continue }
                detailed += 1
                if probes.allSatisfy({
                    abs(Int(reference.pixels[$0]) - Int(current.pixels[$0])) <= 3
                }) {
                    var signature: UInt64 = 0
                    for value in values { signature = signature << 6 | UInt64(value / 4) }
                    var pattern = stablePatterns[signature] ?? (0, [], x, x)
                    pattern.count += 1; pattern.bands.insert((y - evidenceRows.lowerBound) * 8 / evidenceRows.count)
                    pattern.firstX = min(pattern.firstX, x); pattern.lastX = max(pattern.lastX, x)
                    stablePatterns[signature] = pattern
                }
            }
        }
        var stationary = 0
        var stationaryBands: Set<Int> = []
        var stationaryFirstX = width, stationaryLastX = 0
        for pattern in stablePatterns.values where pattern.bands.count <= 2 {
            stationary += pattern.count
            stationaryBands.formUnion(pattern.bands)
            stationaryFirstX = min(stationaryFirstX, pattern.firstX)
            stationaryLastX = max(stationaryLastX, pattern.lastX)
        }
        // Foreground occlusion may cover most of the wallpaper. A motion
        // layer need not be the majority; many distributed stable observations
        // suffice, while a clock or a footer alone cannot activate this path.
        guard stationary >= max(48, detailed / 20), stationaryBands.count >= 3,
              stationaryLastX - stationaryFirstX >= width / 3 else { return result(.notLayered) }
        if changedCount == 0 { return result(.unchanged) }
        var changedFirstY = end, changedLastY = top, changedFirstX = width, changedLastX = 0
        for y in top..<end {
            for x in edge..<(width - edge) where changed[y * width + x] {
                changedFirstY = min(changedFirstY, y); changedLastY = max(changedLastY, y)
                changedFirstX = min(changedFirstX, x); changedLastX = max(changedLastX, x)
            }
        }
        if changedLastX - changedFirstX < 6 { return result(.notLayered) }
        if changedLastY - changedFirstY < max(12, (end - top) / 4) {
            return result(.unchanged)
        }
        func rejected(_ reason: StitchDecision.Rejection, candidates: Int = 0) -> Result {
            // Repeated grids can look stationary at isolated coordinates. A
            // unique, full-pixel overlap proves a single translating canvas;
            // let its existing matcher handle it, without accepting a zero
            // wallpaper fit or relaxing any approximate-error threshold.
            if hasExactWholeTranslation(reference, current, configuration: configuration) {
                return result(.notLayered)
            }
            return result(.rejected, rejection: reason, candidates: candidates)
        }

        let a = features(reference, changed: changed, top: top, end: end)
        let b = features(current, changed: changed, top: top, end: end)
        guard a.count >= 12, b.count >= 12 else { return rejected(.ambiguous) }
        let aMap = index(a), bMap = index(b)
        let maximumShift = end - top - Int(ceil(Double(end - top) * configuration.minimumOverlap))
        let repetitionRadius = max(12, min(64, height / 24))
        var votes: [Int: Int] = [:]
        var pairs: Set<UInt64> = []
        var eligibleA: Set<Int> = [], eligibleB: Set<Int> = []
        for (ai, feature) in a.enumerated() {
            for phase in 0..<2 {
                let key = Key(x: feature.x, hash: phase == 0 ? feature.hashes.0 : feature.hashes.1, phase: phase)
                guard let own = aMap[key], let other = bMap[key],
                      own.lastY - own.firstY <= repetitionRadius,
                      other.lastY - other.firstY <= repetitionRadius,
                      own.indices.count <= 12, other.indices.count <= 12 else { continue }
                for bi in other.indices {
                    let shift = feature.y - b[bi].y
                    guard shift != 0, abs(shift) <= maximumShift else { continue }
                    let pair = UInt64(ai) << 32 | UInt64(bi)
                    guard pairs.insert(pair).inserted else { continue }
                    votes[shift, default: 0] += 1
                    eligibleA.insert(ai); eligibleB.insert(bi)
                }
            }
        }
        guard !votes.isEmpty else { return rejected(.ambiguous) }
        let shifts = proposedShifts(votes: votes, maximumShift: maximumShift)
        let sourceA = eligibleA.sorted().map { a[$0] }, sourceB = eligibleB.sorted().map { b[$0] }
        var scores: [Score] = []
        for shift in shifts {
            scores.append(validate(reference, current, a: sourceA, b: sourceB, shift: shift,
                                   top: top, end: end, maximumError: configuration.maximumMeanAbsoluteError))
        }
        scores.sort { lhs, rhs in lhs.error == rhs.error ? lhs.shift < rhs.shift : lhs.error < rhs.error }
        guard let best = scores.first(where: { $0.valid }), best.error <= configuration.maximumMeanAbsoluteError else {
            return rejected(.insufficientOverlap, candidates: shifts.count)
        }
        let alternative = scores.first { $0.shift != best.shift }
        let margin = alternative.map { $0.error - best.error } ?? 255
        guard margin >= configuration.ambiguityMargin else {
            return rejected(.ambiguous, candidates: shifts.count)
        }
        let quality = max(0, 1 - best.error / configuration.maximumMeanAbsoluteError)
        let separation = min(1, margin / (configuration.ambiguityMargin * 3))
        // Never pad support outward into stationary navigation/input pixels.
        // Automatic callers retain the omitted original edges separately.
        let regionTop = max(top, best.firstRow)
        let regionEnd = min(end, best.lastRow + 1)
        return .init(status: .matched, displacement: best.shift, confidence: 0.65 * quality + 0.35 * separation,
                     rejection: nil, matchingInsets: .init(top: regionTop, bottom: height - regionEnd),
                     candidateCount: shifts.count, supportCount: best.support)
    }

    /// Preserve all original high-vote hypotheses, then cover distinct peaks.
    /// Quantization can spread one repeated motif across adjacent vote bins;
    /// those shoulders must not consume every opportunity to test a different
    /// displacement. Existing +/-1 rivals remain in the set, so this does not
    /// weaken one-pixel ambiguity checks. At most 2 * 8 * 3 = 48 validations.
    static func proposedShifts(votes: [Int: Int], maximumShift: Int) -> Set<Int> {
        let peaks = votes.keys.sorted {
            if votes[$0] != votes[$1] { return votes[$0, default: 0] > votes[$1, default: 0] }
            return abs($0) == abs($1) ? $0 < $1 : abs($0) < abs($1)
        }
        let peakBudget = 8, radius = 1
        var shifts: Set<Int> = []
        func include(_ peak: Int) {
            for shift in (peak - radius)...(peak + radius) where shift != 0 && abs(shift) <= maximumShift {
                shifts.insert(shift)
            }
        }
        for peak in peaks.prefix(peakBudget) { include(peak) }
        var separated: [Int] = []
        for peak in peaks where separated.allSatisfy({ abs($0 - peak) > 2 * radius }) {
            separated.append(peak); include(peak)
            if separated.count == peakBudget { break }
        }
        return shifts
    }

    /// Linear row fingerprints propose positions; full pixel equality verifies
    /// every retained-overlap pixel. Repeated/blank rows never propose a join.
    private static func hasExactWholeTranslation(_ a: GrayFrame, _ b: GrayFrame,
                                                 configuration: AlignmentConfiguration) -> Bool {
        let top = configuration.topInset, end = a.height - configuration.bottomInset
        let bodyHeight = end - top
        let maximum = bodyHeight - Int(ceil(Double(bodyHeight) * configuration.minimumOverlap))
        func rowIndex(_ frame: GrayFrame) -> [UInt64: [Int]] {
            var index: [UInt64: [Int]] = [:]
            for y in top..<end where AlignmentDetailSupport.horizontalSpan(in: frame, row: y) != nil {
                var hash: UInt64 = 14_695_981_039_346_656_037
                for value in frame.pixels[(y * frame.width)..<((y + 1) * frame.width)] {
                    hash = (hash ^ UInt64(value)) &* 1_099_511_628_211
                }
                if index[hash, default: []].count <= 4 { index[hash, default: []].append(y) }
            }
            return index
        }
        let left = rowIndex(a), right = rowIndex(b)
        var proposals: [Int: (count: Int, first: Int, last: Int)] = [:]
        for (hash, aRows) in left where aRows.count <= 4 {
            guard let bRows = right[hash], bRows.count <= 4 else { continue }
            for ay in aRows {
                for by in bRows {
                    let shift = ay - by
                    guard shift != 0, abs(shift) <= maximum else { continue }
                    var support = proposals[shift] ?? (0, by, by)
                    support.count += 1; support.first = min(support.first, by); support.last = max(support.last, by)
                    proposals[shift] = support
                }
            }
        }
        var matches = 0
        let qualified = proposals.filter { shift, support in
            support.count >= 8 && support.last - support.first >= (bodyHeight - abs(shift)) / 4
        }
        guard qualified.count <= 32 else { return false }
        for (shift, _) in qualified {
            let overlap = bodyHeight - abs(shift)
            let startA = (top + max(shift, 0)) * a.width
            let startB = (top + max(-shift, 0)) * b.width
            if a.pixels[startA..<(startA + overlap * a.width)].elementsEqual(b.pixels[startB..<(startB + overlap * b.width)]) {
                matches += 1
                if matches > 1 { return false }
            }
        }
        return matches == 1
    }

    private static func strength(_ frame: GrayFrame, x: Int, y: Int) -> Int {
        let p = y * frame.width + x, value = Int(frame.pixels[p])
        let horizontal = max(abs(value - Int(frame.pixels[p - 2])), abs(value - Int(frame.pixels[p + 2])))
        let vertical = max(abs(value - Int(frame.pixels[p - frame.width * 2])),
                           abs(value - Int(frame.pixels[p + frame.width * 2])))
        return min(horizontal, vertical) * 2
    }

    /// At most 64 features in each of 16 vertical bands. Texture extraction is
    /// linear in input pixels; descriptors and later validation have hard caps.
    private static func features(_ frame: GrayFrame, changed: [Bool], top: Int, end: Int) -> [Feature] {
        let edge = max(4, frame.width / 24)
        let bandHeight = max(8, (end - top + 15) / 16)
        var output: [Feature] = []
        for start in stride(from: top + 4, to: end - 4, by: bandHeight) {
            var points: [Point] = []
            for y in start..<min(end - 4, start + bandHeight) {
                for x in stride(from: edge, to: frame.width - edge, by: 2) where changed[y * frame.width + x] {
                    let score = strength(frame, x: x, y: y)
                    guard score >= 48 else { continue }
                    points.append(.init(x: x, y: y, strength: score))
                }
            }
            points.sort {
                if $0.strength != $1.strength { return $0.strength > $1.strength }
                return $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
            }
            for point in points.prefix(64) {
                var a: UInt64 = 14_695_981_039_346_656_037
                var b = a
                for dy in [-4, -2, 0, 2, 4] {
                    for dx in [-3, -1, 0, 1, 3] {
                        let value = UInt64(frame.pixels[(point.y + dy) * frame.width + point.x + dx])
                        a = (a ^ (value / 16)) &* 1_099_511_628_211
                        b = (b ^ ((value + 8) / 16)) &* 1_099_511_628_211
                    }
                }
                output.append(.init(x: point.x, y: point.y, hashes: (a, b)))
            }
        }
        return output
    }

    private static func index(_ features: [Feature]) -> [Key: Bucket] {
        var result: [Key: Bucket] = [:]
        for (i, feature) in features.enumerated() {
            for phase in 0..<2 {
                let key = Key(x: feature.x, hash: phase == 0 ? feature.hashes.0 : feature.hashes.1, phase: phase)
                if var bucket = result[key] {
                    bucket.firstY = min(bucket.firstY, feature.y); bucket.lastY = max(bucket.lastY, feature.y)
                    if bucket.indices.count <= 12 { bucket.indices.append(i) }
                    result[key] = bucket
                } else { result[key] = .init(indices: [i], firstY: feature.y, lastY: feature.y) }
            }
        }
        return result
    }

    private static func validate(_ reference: GrayFrame, _ current: GrayFrame, a: [Feature], b: [Feature],
                                 shift: Int, top: Int, end: Int, maximumError: Double) -> Score {
        var errors: [Double] = []
        var support = 0, first = end, last = top, firstX = current.width, lastX = 0
        var firstCurrent = end, lastCurrent = top
        var bands: Set<Int> = []
        let bandHeight = max(8, (end - top) / 16)
        func compare(_ point: Feature, fromReference: Bool) {
            let referenceY = fromReference ? point.y : point.y + shift
            let currentY = fromReference ? point.y - shift : point.y
            guard referenceY >= top + 4, referenceY < end - 4,
                  currentY >= top + 4, currentY < end - 4 else { return }
            var total = 0
            for dy in [-4, -2, 0, 2, 4] {
                for dx in [-3, -1, 0, 1, 3] {
                    total += abs(Int(reference.pixels[(referenceY + dy) * reference.width + point.x + dx])
                                 - Int(current.pixels[(currentY + dy) * current.width + point.x + dx]))
                }
            }
            let error = Double(total) / 25
            errors.append(min(64, error))
            if error <= maximumError {
                support += 1
                first = min(first, referenceY, currentY); last = max(last, referenceY, currentY)
                firstCurrent = min(firstCurrent, currentY); lastCurrent = max(lastCurrent, currentY)
                firstX = min(firstX, point.x); lastX = max(lastX, point.x)
                bands.insert((currentY - top) / bandHeight)
            }
        }
        for point in a { compare(point, fromReference: true) }
        for point in b { compare(point, fromReference: false) }
        let error = errors.isEmpty ? 255 : errors.reduce(0, +) / Double(errors.count)
        let valid = support >= 12 && Double(support) >= Double(errors.count) * 0.65
            && bands.count >= 3 && lastCurrent - firstCurrent >= (end - top - abs(shift)) / 4
            && lastX - firstX >= 6
        return .init(shift: shift, error: error, support: support, valid: valid, firstRow: first, lastRow: last)
    }
}
