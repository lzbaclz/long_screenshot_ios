import Foundation
@testable import ScrollCaptureCore

/// A synthetic chat at analysis resolution (144 x 2556) modelled on a plain
/// WeChat conversation on an iPhone 15 Pro: status bar, navigation bar and chat
/// background share ONE gray (237). No private screenshot pixels are used.
enum FixedStructureChatFixture {
    static let width = 144, height = 2_556
    static let statusBarEnd = 162, navBarEnd = 300, inputBarStart = 2_406
    static let background: UInt8 = 237

    /// Deterministic pseudo-random document: bubbles, avatars, picture cards
    /// and blank gaps. `documentY` is the vertical position in the document.
    private static func documentPixel(x: Int, documentY: Int) -> UInt8 {
        // 900-row repeating "message period" with per-period variation so the
        // content is not vertically periodic within one screen.
        let period = 1_000
        let block = documentY / period
        let row = documentY % period
        func hash(_ a: Int, _ b: Int) -> Int {
            var v = UInt64(bitPattern: Int64(a)) &* 0x9E3779B185EBCA87 ^ UInt64(bitPattern: Int64(b)) &* 0xC2B2AE3D27D4EB4F
            v ^= v >> 29; v &*= 0xBF58476D1CE4E5B9; v ^= v >> 32
            return Int(v & 0xFFFF)
        }
        // Message slots inside one period: (startRow, height, side, kind)
        let slots: [(Int, Int, Int, Int)] = [
            (40, 90, 0, 0), (170, 70, 1, 0), (280, 60, 1, 0), (380, 250, 0, 1),
            (680, 120, 1, 2), (840, 70, 0, 0)
        ]
        for (index, slot) in slots.enumerated() {
            let (start, slotHeight, side, kind) = slot
            // Vary each block a little so no two screens repeat exactly.
            let jitter = hash(block, index) % 23
            let s = start + jitter, e = s + slotHeight
            guard row >= s, row < e else { continue }
            let local = row - s
            // Avatar: 18 analysis px square with 2D texture.
            let avatarRange = side == 0 ? 4..<22 : 122..<140
            if avatarRange.contains(x), local < 18 {
                return UInt8(90 + hash(x / 3 + block * 7, local / 3 + index) % 120)
            }
            let bubbleRange = side == 0 ? 27..<(27 + 30 + hash(block, index + 50) % 60)
                                        : (118 - 30 - hash(block, index + 50) % 60)..<118
            guard bubbleRange.contains(x) else { return background }
            switch kind {
            case 1: // picture card: textured
                return UInt8(40 + hash(x / 2 + block, local / 2 + index * 3) % 170)
            case 2: // sticker: mostly white with dark strokes
                return hash(x / 2, local / 2 + block) % 7 == 0 ? 60 : 250
            default: // text bubble: white/green with glyph rows
                let bubble: UInt8 = side == 0 ? 255 : 205
                let textRow = local % 46
                if textRow >= 12, textRow < 34, x > bubbleRange.lowerBound + 4, x < bubbleRange.upperBound - 4 {
                    if hash(x / 2 + block * 3, textRow / 4 + index * 11 + local / 46) % 3 == 0 { return 40 }
                }
                return bubble
            }
        }
        return background
    }

    static func frame(offset: Int, pill: Bool, arrow: Bool = false, minute: Int = 24) throws -> GrayFrame {
        var pixels = [UInt8](repeating: background, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var value = background
                if y < statusBarEnd {
                    // Clock "19:24" digits at left; signal/wifi/battery at right.
                    if (66..<114).contains(y), (14..<30).contains(x), (x + y / 6 + minute) % 3 != 0 { value = 20 }
                    if (70..<110).contains(y), (103..<134).contains(x), (x / 3 + y / 5) % 4 != 0 { value = 20 }
                    if arrow, (78..<100).contains(y), (33..<38).contains(x) { value = 40 }
                    if pill, (49..<128).contains(y), (38..<103).contains(x) {
                        value = 0
                        if (80..<98).contains(y), (43..<48).contains(x) { value = 76 } // red dot
                    }
                } else if y < navBarEnd {
                    if (205..<255).contains(y), (6..<11).contains(x) { value = 30 } // back chevron
                    if (200..<252).contains(y), (56..<88).contains(x), (x / 2 + y / 7) % 3 != 0 { value = 30 } // title
                    if (225..<235).contains(y), (130..<137).contains(x), x % 3 == 0 { value = 30 } // "..." button
                } else if y >= inputBarStart {
                    value = 247
                    if (2_440..<2_510).contains(y), (18..<115).contains(x) { value = 255 } // text field
                    if (2_450..<2_500).contains(y), ((4..<15).contains(x) || (120..<131).contains(x) || (133..<141).contains(x)) {
                        value = 60 // voice / emoji / plus icons
                    }
                } else {
                    value = documentPixel(x: x, documentY: offset + (y - navBarEnd))
                }
                pixels[y * width + x] = value
            }
        }
        return try GrayFrame(width: width, height: height, pixels: pixels)
    }
}
