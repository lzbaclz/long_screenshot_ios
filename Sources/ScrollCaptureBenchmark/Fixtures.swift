import Foundation
import ScrollCaptureCore

enum Pattern: String, CaseIterable {
    case texture, text, chat, table, sections, cards, sparseText
    case periodic, gradient

    static let stable: [Pattern] = [.texture, .text, .chat, .table, .sections, .cards, .sparseText]
}

struct Canvas {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(width: Int, height: Int, pattern: Pattern, seed: Int, period: Int = 24) {
        self.width = width
        self.height = height
        var pixels = [UInt8](repeating: 248, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = Self.pixel(x: x, y: y, width: width,
                                                  pattern: pattern, seed: seed, period: period)
            }
        }
        self.pixels = pixels
    }

    func frame(offset: Int, bodyHeight: Int, top: Int, bottom: Int) throws -> GrayFrame {
        var result = [UInt8](repeating: 0, count: width * (top + bodyHeight + bottom))
        for y in 0..<top {
            for x in 0..<width { result[y * width + x] = Self.hash(x: x, y: y, seed: 40_001) }
        }
        result.replaceSubrange((top * width)..<((top + bodyHeight) * width),
                               with: pixels[(offset * width)..<((offset + bodyHeight) * width)])
        for y in (top + bodyHeight)..<(top + bodyHeight + bottom) {
            for x in 0..<width { result[y * width + x] = Self.hash(x: x, y: y, seed: 80_001) }
        }
        return try GrayFrame(width: width, height: top + bodyHeight + bottom, pixels: result)
    }

    private static func pixel(x: Int, y: Int, width: Int, pattern: Pattern, seed: Int, period: Int) -> UInt8 {
        switch pattern {
        case .texture:
            return hash(x: x, y: y, seed: seed)
        case .periodic:
            return hash(x: x, y: y % period, seed: seed)
        case .gradient:
            return UInt8(30 + min(200, y))
        case .text:
            return glyph(x: x, y: y, seed: seed, lineHeight: 13, width: width)
        case .sparseText:
            guard x < width * 2 / 3 else { return 248 }
            return glyph(x: x, y: y, seed: seed, lineHeight: 43, width: width)
        case .chat:
            let block = y / 47
            let blockY = y % 47
            let left = block % 2 == 0 ? 8 : width / 5
            let right = block % 2 == 0 ? width * 4 / 5 : width - 8
            guard blockY < 41, x >= left, x < right else { return 245 }
            let ink = glyph(x: x - left, y: y + block * 3, seed: seed + 23, lineHeight: 12, width: width)
            return ink < 200 ? ink : UInt8(211 + Int(hash(x: block, y: 1, seed: seed)) % 22)
        case .table:
            if y % 23 == 22 || x % 31 == 30 { return 141 }
            let ink = glyph(x: x, y: y, seed: seed + 61, lineHeight: 23, width: width)
            return ink < 200 ? ink : (y / 23 % 2 == 0 ? 245 : 225)
        case .sections:
            let block = y / 67
            if y % 67 < 13 {
                return UInt8(40 + Int(hash(x: x / 3, y: block, seed: seed)) % 110)
            }
            return glyph(x: x, y: y, seed: seed + 101, lineHeight: 15, width: width)
        case .cards:
            let row = y % 113
            if row < 39 && x >= 5 && x < width - 5 {
                return hash(x: x, y: y, seed: seed + 503)
            }
            return glyph(x: x, y: y, seed: seed + 701, lineHeight: 14, width: width)
        }
    }

    private static func glyph(x: Int, y: Int, seed: Int, lineHeight: Int, width: Int) -> UInt8 {
        guard x >= 5, x < width - 5, y % lineHeight < 8, x % 7 < 5 else { return 248 }
        let code = Int(hash(x: x / 7, y: y / lineHeight, seed: seed))
        if code % 11 == 0 || (code + (y % lineHeight) * 3 + x % 7) % 7 >= 4 { return 248 }
        return UInt8(20 + code % 55)
    }

    static func hash(x: Int, y: Int, seed: Int) -> UInt8 {
        var value = UInt64(truncatingIfNeeded: y) &* 0x9E3779B185EBCA87
        value ^= UInt64(truncatingIfNeeded: x) &* 0xC2B2AE3D27D4EB4F
        value ^= UInt64(truncatingIfNeeded: seed) &* 0x165667B19E3779F9
        value ^= value >> 30
        value &*= 0xBF58476D1CE4E5B9
        value ^= value >> 27
        return UInt8(truncatingIfNeeded: value)
    }
}

struct FixtureStep {
    enum Input {
        case document, animatedDocument, changedScene, changedGeometry
    }
    let offset: Int
    var input: Input = .document
    var expectedRejection: StitchDecision.Rejection?
}

struct Fixture {
    let id: String
    let group: String
    let pattern: Pattern
    let variant: String
    let seed: Int
    let width: Int
    let bodyHeight: Int
    let depth: Int
    let top: Int
    let bottom: Int
    var period = 24
    let steps: [FixtureStep]

    static func all() -> [Fixture] {
        var result: [Fixture] = []
        let variants = ["steady", "odd_steps", "fixed_bars", "short_reversals", "pause_reverse_bars",
                        "upward_start", "upward_pause_reverse", "both_ends_crossing"]
        for (patternIndex, pattern) in Pattern.stable.enumerated() {
            for depth in [5, 10, 20] {
                for variant in variants.indices {
                    let bodyHeight = [180, 193, 216][patternIndex % 3]
                    let step = [73, 61, 87, 79, 69, 73, 61, 69][variant]
                    let end = bodyHeight * (depth - 1)
                    var positions = [0]
                    var current = 0
                    var count = 0
                    while current < end {
                        current = min(end, current + step)
                        positions.append(current)
                        count += 1
                        if (variant == 3 || variant == 4 || variant == 6) && count % 4 == 0 {
                            positions.append(max(0, current - bodyHeight / 4))
                            positions.append(max(0, current - bodyHeight / 9))
                            positions.append(current)
                        }
                        if (variant == 4 || variant == 6) && count % 3 == 0 { positions.append(current) }
                    }
                    if variant == 5 || variant == 6 {
                        positions = positions.map { end - $0 }
                    } else if variant == 7 {
                        let midpoint = end / 2
                        var crossing = [midpoint]
                        for target in [0, end, 0, end] {
                            while let last = crossing.last, last != target {
                                crossing.append(last < target ? min(target, last + step) : max(target, last - step))
                            }
                        }
                        positions = crossing
                    }
                    result.append(Fixture(
                        id: String(format: "core-%03d", result.count + 1), group: "core",
                        pattern: pattern, variant: variants[variant], seed: 1_003 + patternIndex * 101 + variant,
                        width: [96, 112, 144][patternIndex % 3], bodyHeight: bodyHeight, depth: depth,
                        top: variant == 2 || variant == 4 || variant == 6 ? 17 : 0,
                        bottom: variant == 2 || variant == 4 || variant == 6 ? 23 : 0,
                        steps: positions.map { FixtureStep(offset: $0) }
                    ))
                }
            }
        }

        for kind in 0..<9 {
            for variant in 0..<5 {
                let height = 160 + variant * 4
                let normal = [FixtureStep(offset: 0), FixtureStep(offset: 31)]
                let steps: [FixtureStep]
                let name: String
                let pattern: Pattern
                switch kind {
                case 0:
                    name = "periodic_ambiguity"
                    pattern = .periodic
                    steps = [FixtureStep(offset: 0), FixtureStep(offset: 7 + variant, expectedRejection: .ambiguous)]
                case 1:
                    name = "gap_then_recovery"
                    pattern = .texture
                    steps = normal + [FixtureStep(offset: height * 3, expectedRejection: .insufficientOverlap),
                                      FixtureStep(offset: 65)]
                case 2:
                    name = "scene_change"
                    pattern = .texture
                    steps = normal + [FixtureStep(offset: 41, input: .changedScene, expectedRejection: .insufficientOverlap)]
                case 3:
                    name = "geometry_change"
                    pattern = .texture
                    steps = normal + [FixtureStep(offset: 41, input: .changedGeometry, expectedRejection: .geometryChanged)]
                case 4:
                    name = "below_minimum_overlap"
                    pattern = .texture
                    steps = [FixtureStep(offset: 0), FixtureStep(offset: Int(Double(height) * 0.6) + 5,
                                                               expectedRejection: .insufficientOverlap)]
                case 5:
                    name = "low_contrast_ambiguity"
                    pattern = .gradient
                    steps = [FixtureStep(offset: 0), FixtureStep(offset: 7, expectedRejection: .ambiguous)]
                case 6:
                    name = "upward_gap_then_recovery"
                    pattern = .texture
                    steps = [FixtureStep(offset: height * 3), FixtureStep(offset: height * 3 - 31),
                             FixtureStep(offset: 0, expectedRejection: .insufficientOverlap),
                             FixtureStep(offset: height * 3 - 65)]
                case 7:
                    name = "upward_below_minimum_overlap"
                    pattern = .texture
                    steps = [FixtureStep(offset: height * 3),
                             FixtureStep(offset: height * 3 - Int(Double(height) * 0.6) - 5,
                                         expectedRejection: .insufficientOverlap)]
                default:
                    name = "upward_periodic_ambiguity"
                    pattern = .periodic
                    steps = [FixtureStep(offset: height * 3),
                             FixtureStep(offset: height * 3 - 7 - variant, expectedRejection: .ambiguous)]
                }
                result.append(Fixture(id: String(format: "stress-%03d", kind * 5 + variant + 1),
                                      group: "stress", pattern: pattern, variant: name, seed: 31_003 + variant * 103,
                                      width: 96, bodyHeight: height, depth: 5,
                                      top: variant % 2 == 0 ? 11 : 0, bottom: variant % 2 == 0 ? 13 : 0,
                                      period: 18 + variant * 2, steps: steps))
            }
        }
        for (index, pattern) in [Pattern.texture, .text, .cards, .sparseText].enumerated() {
            let height = 2_556
            let start = height * 2
            let positions = [start, start, start + 379, start + 379, start + 802,
                             start + 423, start, start - 379, start - 379, start - 802]
            result.append(Fixture(id: "stress-native-\(index + 1)", group: "stress", pattern: pattern,
                                  variant: "native_height_loading_pause", seed: 61_003 + index * 101,
                                  width: 144, bodyHeight: height, depth: 5, top: 127, bottom: 139,
                                  steps: positions.enumerated().map { step, offset in
                                      FixtureStep(offset: offset, input: step == 0 ? .document : .animatedDocument)
                                  }))
        }
        return result
    }
}
