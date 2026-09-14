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
        // A transient overlay (recording indicator, clock, location arrow) can
        // make the first differing row sit INSIDE a fixed bar. Rows beyond it
        // that still share identical structure prove the bar continues, so
        // such a boundary is not exact.
        let band = fixedStructureBand(reference: reference, current: current)
        guard top >= band.top, bottom >= band.bottom else { return .ambiguous }
        return .resolved(Insets(top: top, bottom: bottom))
    }

    /// Fixed UI is structure drawn at the same screen position in both frames,
    /// whichever frame is "current". A row belongs to it when most of its
    /// horizontal structure is pixel-identical in both frames, even if an
    /// overlay (recording pill, clock digits) changes other columns of that
    /// row. The band is chained from each outer edge; blank rows and overlays
    /// may interrupt it by at most one support window. Returned extents are
    /// exclusive distances: a matching region must start at or beyond them.
    /// This describes whole-frame translation only; the layered wallpaper path
    /// must not apply it, because wallpaper showing between bubbles is also
    /// identical structure.
    public static func fixedStructureBand(reference: GrayFrame, current: GrayFrame) -> (top: Int, bottom: Int) {
        guard reference.width == current.width, reference.height == current.height,
              reference.height >= 40, reference.width >= 12 else { return (0, 0) }
        func extent(fromTop: Bool) -> Int {
            let supportWindow = max(12, reference.height / 12)
            let limit = reference.height * 3 / 10 + supportWindow
            var last = -1
            for distance in 0...min(reference.height - 1, limit) {
                if distance - max(last, 0) > supportWindow { break }
                let y = fromTop ? distance : reference.height - 1 - distance
                if sharesFixedStructure(reference, current, row: y) { last = distance }
            }
            return last + 1
        }
        return (extent(fromTop: true), extent(fromTop: false))
    }

    private static func sharesFixedStructure(_ a: GrayFrame, _ b: GrayFrame, row: Int) -> Bool {
        let edge = max(1, a.width / 24)
        let start = row * a.width
        var structure = 0, shared = 0
        for x in edge..<(a.width - edge) {
            let av = Int(a.pixels[start + x]), bv = Int(b.pixels[start + x])
            let aDetail = max(abs(av - Int(a.pixels[start + x - 1])), abs(av - Int(a.pixels[start + x + 1])))
            let bDetail = max(abs(bv - Int(b.pixels[start + x - 1])), abs(bv - Int(b.pixels[start + x + 1])))
            guard max(aDetail, bDetail) >= 16 else { continue }
            structure += 1
            if min(aDetail, bDetail) >= 16, abs(av - bv) <= 3 { shared += 1 }
        }
        // Repeated table borders or bubble edges share a few columns in
        // ordinary moving rows; fixed bars share nearly all of their glyphs.
        return shared > 4 && shared * 10 >= structure * 6
    }

    public enum CandidateSource: Equatable, Sendable {
        case wholePage
        case foreground
    }

    /// The source travels with the insets so callers can exempt fixed wallpaper
    /// from whole-page structure checks, including after reverse normalization.
    public struct CandidateSet: Equatable, Sendable {
        public let insets: [Insets]
        public let source: CandidateSource
    }

    /// Candidate boundaries delimit the part used for matching, not permission
    /// to discard pixels. Callers MUST preserve complete outer frame edges when
    /// using these candidates. Blank rows and a changing clock are intentionally
    /// allowed outside the moving evidence; replay must independently confirm
    /// that a candidate produces the same displacement.
    public static func candidates(reference: GrayFrame, current: GrayFrame,
                                  displacement: Int) -> [Insets] {
        candidateSet(reference: reference, current: current, displacement: displacement).insets
    }

    public static func candidateSet(reference: GrayFrame, current: GrayFrame,
                                    displacement: Int) -> CandidateSet {
        guard reference.width == current.width, reference.height == current.height,
              reference.height >= 40, displacement != 0,
              displacement > -(reference.height - 12), displacement < reference.height - 12 else { return CandidateSet(insets: [], source: .wholePage) }
        if displacement < 0 {
            return candidateSet(reference: current, current: reference, displacement: -displacement)
        }
        let foreground = ForegroundMotionRegistration.analyze(reference: reference, current: current)
        if foreground.status == .matched {
            guard foreground.displacement == displacement, let insets = foreground.matchingInsets else {
                return CandidateSet(insets: [], source: .foreground)
            }
            return CandidateSet(insets: [insets], source: .foreground)
        }
        if foreground.status == .rejected { return CandidateSet(insets: [], source: .foreground) }
        if case .resolved(let exact) = resolve(reference: reference, current: current,
                                               downwardDisplacement: displacement) {
            return CandidateSet(insets: [exact], source: .wholePage)
        }
        let limit = reference.height * 3 / 10
        let band = fixedStructureBand(reference: reference, current: current)
        func evidence(fromTop: Bool) -> Int? {
            var moving: [Int] = []
            let supportWindow = max(12, reference.height / 12)
            // The boundary may lie at the search limit. Collect its supporting
            // body rows beyond that limit rather than requiring all evidence
            // to fit inside the area we may exclude from matching.
            let evidenceLimit = min(reference.height - displacement - 1, limit + supportWindow)
            // A row inside the shared fixed structure can differ only because
            // of an overlay; it is never evidence of document motion.
            for distance in 0...evidenceLimit where distance >= (fromTop ? band.top : band.bottom) {
                let y = fromTop ? distance : reference.height - 1 - distance
                let stationary = rowError(reference, row: y, current, row: y)
                let motion = fromTop
                    ? rowError(reference, row: y + displacement, current, row: y)
                    : rowError(reference, row: y, current, row: y - displacement)
                // Keep the existing motion rule: displaced agreement alone is
                // insufficient; the same screen row must also have changed.
                // Blank document rows remain useful outside fixed structure.
                if motion <= 4, stationary - motion >= 4 { moving.append(distance) }
            }
            guard let first = moving.first, first <= limit,
                  moving.filter({ $0 <= first + supportWindow }).count >= 3 else { return nil }
            return first
        }
        var raw: [Insets] = []
        if let top = evidence(fromTop: true), let bottom = evidence(fromTop: false),
           top + bottom < reference.height - 12 {
            raw = [Insets(top: top, bottom: bottom),
                   Insets(top: max(band.top, top - 2), bottom: max(band.bottom, bottom - 2))]
        }
        // A loading photo or a keyboard can hide all motion at an outer edge.
        // A distributed, textured interior still supplies a valid matching
        // region. Its full original outer pixels MUST remain visible as caps.
        if let interior = movingInterior(reference: reference, current: current, displacement: displacement),
           interior.top >= band.top, interior.bottom >= band.bottom {
            raw.append(interior)
        }
        // This also protects future whole-page candidate sources and padding.
        let insets = raw.reduce(into: [Insets]()) { result, item in
            if item.top >= band.top, item.bottom >= band.bottom, !result.contains(item) { result.append(item) }
        }
        return CandidateSet(insets: insets, source: .wholePage)
    }

    private static func movingInterior(reference: GrayFrame, current: GrayFrame,
                                       displacement: Int) -> Insets? {
        var rows: [Int] = []
        for y in 0..<(reference.height - displacement) {
            guard let referenceSpan = AlignmentDetailSupport.horizontalSpan(in: reference, row: y + displacement),
                  let currentSpan = AlignmentDetailSupport.horizontalSpan(in: current, row: y) else { continue }
            let shifted = (y + displacement) * reference.width
            let stationary = y * reference.width
            var count = 0, motionError = 0, staticError = 0
            let lower = min(referenceSpan.lowerBound, currentSpan.lowerBound)
            let upper = max(referenceSpan.upperBound, currentSpan.upperBound)
            // Short messages may occupy only a dozen analysis columns. Scan
            // their actual feature support instead of a screen-wide grid that
            // can miss the glyphs. The shared support check still rejects a
            // single thin line, and replay must confirm the same displacement.
            for x in lower..<upper {
                let a = Int(reference.pixels[shifted + x]), b = Int(current.pixels[stationary + x])
                let aDetail = max(abs(a - Int(reference.pixels[shifted + x - 1])),
                                  abs(a - Int(reference.pixels[shifted + x + 1])))
                let bDetail = max(abs(b - Int(current.pixels[stationary + x - 1])),
                                  abs(b - Int(current.pixels[stationary + x + 1])))
                // Both aligned rows must contain real horizontal features;
                // matching white pixels alone cannot identify a moving region.
                if min(aDetail, bDetail) >= 16 {
                    count += 1; motionError += abs(a - b)
                    staticError += abs(Int(reference.pixels[stationary + x]) - b)
                }
            }
            guard count >= 3 else { continue }
            let motion = Double(motionError) / Double(count)
            let fixed = Double(staticError) / Double(count)
            if motion <= 4, fixed - motion >= 4 { rows.append(y) }
        }
        guard rows.count >= 4, let first = rows.first, let last = rows.last else { return nil }
        let end = last + displacement + 1
        guard end - first >= 12, last - first >= max(12, (end - first) / 4) else { return nil }
        return Insets(top: first, bottom: reference.height - end)
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
