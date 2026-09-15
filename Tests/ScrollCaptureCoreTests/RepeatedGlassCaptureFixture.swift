import Foundation

/// The native seam regression's procedural glass page, at analysis width.
/// Its repeated icon rows are intentional adversarial content. Keep this
/// geometry aligned with GlassCaptureFixture; no private source pixels.
struct RepeatedGlassCaptureFixture {
    let width: Int
    let height: Int
    var fixedBackground = true
    var top: Int { height / 10 }
    var bottom: Int { height / 12 }
    var bodyHeight: Int { height - top - bottom }
    var period: Int { height / 5 }
    func isCardRow(_ documentY: Int) -> Bool { (period / 12..<period * 3 / 4).contains(documentY % period) }

    func frame(offset: Int) -> [UInt8] {
        var values = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            var row = [UInt8](repeating: 0, count: 144)
            for x in 0..<144 {
                if y < top || y >= height - bottom {
                    row[x] = (x / 5 + y / 7) % 3 == 0 ? 35 : 235
                    continue
                }
                let documentY = offset + y - top
                let screenY = fixedBackground ? y : documentY
                let background = 115 + 24 * sin(Double(x) / 9) + 18 * sin(Double(screenY) / 31)
                    + 24 * sin((Double(x) + Double(screenY) / 8) / 25)
                var value = background
                let localY = documentY % period
                if isCardRow(documentY), (7..<66).contains(x) || (78..<137).contains(x) {
                    value = 0.45 * background + 0.55 * 240
                    let localX = x < 70 ? x - 7 : x - 78
                    let iconY = (localY - period / 12) % max(1, period / 4)
                    if (6..<25).contains(localX) || (33..<52).contains(localX),
                       (period / 20..<period / 5).contains(iconY) {
                        let block = documentY / period
                        value = (localX / 3 + iconY / 7 + block * 11) % 5 < 3 ? Double(20 + (block * 17 + localX * 3) % 100) : 240
                    }
                }
                row[x] = UInt8(max(0, min(255, value.rounded())))
            }
            for x in 0..<width { values[y * width + x] = row[x * 144 / width] }
        }
        return values
    }
}
