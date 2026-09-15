import Foundation
@testable import ScrollCaptureCore

/// Independent, program-generated document geometry. Cards/icons move in
/// document coordinates while a gradient stays at each frame's screen position.
/// Geometry is used by assertions only; SeamSelector receives just GrayFrames.
enum GlassSeamFixture {
    static let width = 144
    struct Pair {
        let retained: GrayFrame
        let incoming: GrayFrame
        let cardRows: [Range<Int>]
        let iconRows: [Range<Int>]
    }

    static func pair(height: Int = 1_400, phase: Double = 0, cardHeight: Int = 300,
                     gap: Int = 72, startWithinCard: Int = 24,
                     backgroundBase: Double = 115, materialTone: Double = 233,
                     waveAmplitude: Double = 40, horizontalSlope: Double = 0.1, verticalSlope: Double = 1.0 / 90,
                     direction: SeamSelector.Direction = .prepend) throws -> Pair {
        let period = cardHeight + gap
        var old = [UInt8](repeating: 0, count: width * height)
        var new = old
        let origins = stride(from: -startWithinCard, to: height, by: period)
        let cards = origins.map { $0..<($0 + cardHeight) }
        let icons = cards.flatMap { card in [45, 125, 215].map { (card.lowerBound + $0)..<(card.lowerBound + $0 + 54) } }
        for y in 0..<height {
            let documentY = y + startWithinCard
            let localY = documentY % period
            for x in 0..<width {
                func pixel(screenY: Int) -> UInt8 {
                    let wave = waveAmplitude * sin(Double(screenY) / 310 + phase)
                    let background = backgroundBase + wave + Double(x) * horizontalSlope + Double(screenY) * verticalSlope
                    var value = background
                    let left = (7..<66).contains(x), right = (78..<137).contains(x)
                    if localY < cardHeight, left || right {
                        // The material changes with the fixed background.
                        value = 0.48 * background + 0.52 * materialTone
                        let localX = left ? x - 7 : x - 78
                        let inIconColumn = (7..<25).contains(localX) || (33..<51).contains(localX)
                        for top in [45, 125, 215] where (top..<(top + 54)).contains(localY) && inIconColumn {
                            // Opaque icon interiors have ZERO aligned frame
                            // difference, despite being unsafe places to cut.
                            let seed = (localX / 3 + (localY - top) / 5 + documentY / period * 3) % 7
                            value = Double(35 + seed * 23)
                        }
                    }
                    return UInt8(clamping: Int(value.rounded()))
                }
                old[y * width + x] = pixel(screenY: y + 200)
                new[y * width + x] = pixel(screenY: y + 500)
            }
        }
        func reversed(_ values: [UInt8]) -> [UInt8] {
            (0..<height).reversed().flatMap { Array(values[($0 * width)..<(($0 + 1) * width)]) }
        }
        let append = direction == .append
        func mapped(_ ranges: [Range<Int>]) -> [Range<Int>] {
            append ? ranges.map { (height - $0.upperBound)..<(height - $0.lowerBound) } : ranges
        }
        return Pair(retained: try GrayFrame(width: width, height: height, pixels: append ? reversed(old) : old),
                    incoming: try GrayFrame(width: width, height: height, pixels: append ? reversed(new) : new),
                    cardRows: mapped(cards), iconRows: mapped(icons))
    }
}
