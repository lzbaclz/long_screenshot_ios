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
              height >= 40, downwardDisplacement > 0,
              downwardDisplacement < height / 2 else { return .ambiguous }
        let limit = height * 3 / 10
        guard let top = boundary(reference: reference, current: current,
                                 displacement: downwardDisplacement, limit: limit, fromTop: true),
              let bottom = boundary(reference: reference, current: current,
                                    displacement: downwardDisplacement, limit: limit, fromTop: false),
              top + bottom < height - 12 else { return .ambiguous }
        return .resolved(Insets(top: top, bottom: bottom))
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
