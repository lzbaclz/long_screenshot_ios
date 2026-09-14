import Foundation

/// A conservative first-scroll boundary check, not a universal UI classifier.
/// Call only after obtaining a trusted positive displacement from the center of
/// the frame. Ambiguous stationary whitespace must not be silently cropped.
public enum FixedRegionDetector {
    public struct Insets: Equatable, Sendable {
        public let top: Int
        public let bottom: Int
    }

    public enum Resolution: Equatable, Sendable {
        case resolved(Insets)
        case ambiguous
    }

    public static func resolve(reference: GrayFrame, current: GrayFrame,
                               downwardDisplacement: Int) -> Resolution {
        let height = reference.height
        guard reference.width == current.width, height == current.height,
              height >= 40, downwardDisplacement != 0,
              downwardDisplacement > -(height / 2), downwardDisplacement < height / 2 else { return .ambiguous }
        if downwardDisplacement < 0 {
            return resolve(reference: current, current: reference, downwardDisplacement: -downwardDisplacement)
        }
        let limit = height * 3 / 10
        guard let top = boundary(reference: reference, current: current,
                                 displacement: downwardDisplacement, limit: limit, fromTop: true),
              let bottom = boundary(reference: reference, current: current,
                                    displacement: downwardDisplacement, limit: limit, fromTop: false),
              top + bottom < height - 12 else { return .ambiguous }
        return .resolved(Insets(top: top, bottom: bottom))
    }

    /// Candidate boundaries delimit the part used for matching, not permission
    /// to discard pixels. Callers MUST preserve complete outer frame edges when
    /// using these candidates. Blank rows and a changing clock are intentionally
    /// allowed outside the moving evidence; replay must independently confirm
    /// that a candidate produces the same displacement.
    public static func candidates(reference: GrayFrame, current: GrayFrame,
                                  displacement: Int) -> [Insets] {
        guard reference.width == current.width, reference.height == current.height,
              reference.height >= 40, displacement != 0,
              displacement > -(reference.height / 2), displacement < reference.height / 2 else { return [] }
        if displacement < 0 {
            return candidates(reference: current, current: reference, displacement: -displacement)
        }
        if case .resolved(let exact) = resolve(reference: reference, current: current,
                                               downwardDisplacement: displacement) {
            return [exact]
        }
        let limit = reference.height * 3 / 10
        func evidence(fromTop: Bool) -> Int? {
            var moving: [Int] = []
            let supportWindow = max(12, reference.height / 12)
            // The boundary may lie at the search limit. Collect its supporting
            // body rows beyond that limit rather than requiring all evidence
            // to fit inside the area we may exclude from matching.
            let evidenceLimit = min(reference.height - displacement - 1, limit + supportWindow)
            for distance in 0...evidenceLimit {
                let y = fromTop ? distance : reference.height - 1 - distance
                let stationary = rowError(reference, row: y, current, row: y)
                let motion = fromTop
                    ? rowError(reference, row: y + displacement, current, row: y)
                    : rowError(reference, row: y, current, row: y - displacement)
                // Require an actual moving feature. Merely similar white rows
                // cannot establish a boundary or a displacement.
                if motion <= 4, stationary - motion >= 4 { moving.append(distance) }
            }
            guard let first = moving.first, first <= limit,
                  moving.filter({ $0 <= first + supportWindow }).count >= 3 else { return nil }
            return first
        }
        guard let top = evidence(fromTop: true), let bottom = evidence(fromTop: false),
              top + bottom < reference.height - 12 else { return [] }
        // Offer conservative alternatives to the replay verifier. The first
        // preserves the largest matching body; the second excludes uncertain
        // leading/trailing blank runs while visible outer edges remain intact.
        let raw = [Insets(top: top, bottom: bottom),
                   Insets(top: max(0, top - 2), bottom: max(0, bottom - 2))]
        return raw.reduce(into: []) { result, item in if !result.contains(item) { result.append(item) } }
    }

    private static func boundary(reference: GrayFrame, current: GrayFrame,
                                 displacement: Int, limit: Int, fromTop: Bool) -> Int? {
        let staticTolerance = 1.5
        let motionTolerance = 4.0
        let fixedEvidence = 8.0
        var count = 0
        var lastMotionError = 0.0
        var stronglyFixedRows = 0
        for distance in 0...limit {
            let y = fromTop ? distance : reference.height - 1 - distance
            let stationary = rowError(reference, row: y, current, row: y)
            let motion = fromTop
                ? rowError(reference, row: y + displacement, current, row: y)
                : rowError(reference, row: y, current, row: y - displacement)
            if stationary > staticTolerance {
                // The first row outside the fixed band must be actual moving
                // content, not a clock, animation, translucent bar or overlay.
                guard motion <= motionTolerance, stationary - motion >= 4 else { return nil }
                if count == 0 { return 0 }
                // Exact boundary evidence prevents absorbing legitimate blank
                // document padding just because it also stays visually white.
                guard lastMotionError >= fixedEvidence,
                      stronglyFixedRows >= max(1, count / 5) else { return nil }
                return count
            }
            count += 1
            lastMotionError = motion
            if motion >= fixedEvidence { stronglyFixedRows += 1 }
        }
        // A band this large, or wholly uninformative whitespace, needs a manual
        // capture region. Neither implies permission to throw content away.
        return nil
    }

    private static func rowError(_ lhs: GrayFrame, row lhsRow: Int,
                                 _ rhs: GrayFrame, row rhsRow: Int) -> Double {
        guard lhsRow >= 0, lhsRow < lhs.height, rhsRow >= 0, rhsRow < rhs.height else { return 255 }
        // Avoid the very edge where transient vertical scroll indicators live.
        let inset = lhs.width >= 16 ? 2 : 0
        let available = lhs.width - inset * 2
        let columns = min(48, available)
        var total = 0
        for index in 0..<columns {
            let x = inset + (columns == 1 ? 0 : index * (available - 1) / (columns - 1))
            total += abs(Int(lhs.pixels[lhsRow * lhs.width + x]) - Int(rhs.pixels[rhsRow * rhs.width + x]))
        }
        return Double(total) / Double(columns)
    }
}
