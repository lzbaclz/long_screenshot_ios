import SwiftUI
import UIKit

/// A program-drawn App Library-like layout. Only the cards move; the soft
/// colored backdrop stays in screen coordinates. No user media is loaded.
struct GlassGridHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GlassGridController { GlassGridController() }
    func updateUIViewController(_ controller: GlassGridController, context: Context) {}
}

final class GlassGridController: UIViewController, UIScrollViewDelegate {
    private let dark = ProcessInfo.processInfo.arguments.contains("--glass-dark")
    private let backdrop = UIImageView()
    private let header = UIView()
    private let titleLabel = UILabel()
    private let search = UILabel()
    private let footer = UILabel()
    private let metadata = UILabel()
    private let scroll = UIScrollView()
    private let document = UIView()
    private var builtSize = CGSize.zero
    private var cards: [(id: String, view: UIView)] = []
    private var icons: [(id: String, view: UIView)] = []
    private var documentHeight: CGFloat = 0
    private var positioned = false
    private var glassOpacity: CGFloat { dark ? 0.32 : 0.52 }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBlue
        backdrop.contentMode = .scaleToFill
        view.addSubview(backdrop)
        scroll.backgroundColor = .clear
        scroll.isOpaque = false
        scroll.bounces = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = self
        scroll.accessibilityIdentifier = "fixture.glass.scroll"
        scroll.accessibilityLabel = "合成玻璃分类，可上下滚动"
        document.backgroundColor = .clear
        document.isOpaque = false
        scroll.addSubview(document)
        view.addSubview(scroll)
        header.backgroundColor = UIColor(white: dark ? 0.12 : 0.94, alpha: 0.96)
        view.addSubview(header)
        titleLabel.text = "App 资源库"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = dark ? .white : .black
        header.addSubview(titleLabel)
        search.text = "⌕  搜索 App"
        search.font = .systemFont(ofSize: 15)
        search.textColor = dark ? .lightGray : .darkGray
        search.backgroundColor = UIColor(white: dark ? 0.25 : 0.86, alpha: 1)
        search.layer.cornerRadius = 10
        search.clipsToBounds = true
        header.addSubview(search)
        footer.text = "合成分类 · 程序生成"
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = dark ? .white : .darkGray
        footer.textAlignment = .center
        footer.backgroundColor = header.backgroundColor
        view.addSubview(footer)
        metadata.text = nil
        metadata.isAccessibilityElement = true
        metadata.accessibilityTraits = .staticText
        metadata.accessibilityIdentifier = "fixture.glass.metadata"
        metadata.accessibilityLabel = "合成玻璃分类布局数据"
        view.addSubview(metadata)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let headerHeight = view.safeAreaInsets.top + 82
        let footerHeight = view.safeAreaInsets.bottom + 30
        backdrop.frame = view.bounds
        header.frame = CGRect(x: 0, y: 0, width: width, height: headerHeight)
        titleLabel.frame = CGRect(x: 20, y: view.safeAreaInsets.top + 3, width: width - 40, height: 30)
        search.frame = CGRect(x: 18, y: headerHeight - 43, width: width - 36, height: 34)
        footer.frame = CGRect(x: 0, y: view.bounds.height - footerHeight, width: width, height: footerHeight)
        metadata.frame = CGRect(x: 4, y: footer.frame.minY + 4, width: 8, height: 8)
        scroll.frame = CGRect(x: 0, y: headerHeight, width: width,
                              height: view.bounds.height - headerHeight - footerHeight)
        if builtSize != view.bounds.size, width > 0 {
            builtSize = view.bounds.size
            backdrop.image = makeBackdrop(size: builtSize)
            buildCards(width: width)
            document.frame = CGRect(x: 0, y: 0, width: width, height: documentHeight)
            scroll.contentSize = CGSize(width: width, height: documentHeight)
            if !positioned {
                positioned = true
                scroll.setContentOffset(CGPoint(x: 0, y: (documentHeight - scroll.bounds.height) / 2), animated: false)
            }
        }
        updateMetadata()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateMetadata() }

    private func buildCards(width: CGFloat) {
        document.subviews.forEach { $0.removeFromSuperview() }
        cards.removeAll(); icons.removeAll()
        let names = ["建议", "最近添加", "社交", "创意", "娱乐", "旅游", "效率", "工具", "信息与阅读", "购物与美食",
                     "教育", "健康健身", "游戏", "生活", "财务", "摄影", "音乐", "导航", "运动", "天气"]
        let symbols = ["camera.fill", "airplane", "music.note", "book.fill", "map.fill", "leaf.fill", "bicycle", "cloud.sun.fill",
                       "heart.fill", "cart.fill", "paintbrush.fill", "bell.fill", "pencil", "cup.and.saucer.fill", "headphones", "lightbulb.fill",
                       "building.2.fill", "flame.fill", "pawprint.fill", "scissors", "gift.fill", "sun.max.fill", "tram.fill", "gamecontroller.fill"]
        let cardWidth = (width - 48) / 2
        let cardHeight = cardWidth * 0.86
        let iconSide = min(58, (cardWidth - 40) / 2)
        let period = cardHeight + 54
        for row in 0..<20 {
            for column in 0..<2 {
                let index = row * 2 + column
                let card = UIView(frame: CGRect(x: 16 + CGFloat(column) * (cardWidth + 16),
                                                y: 22 + CGFloat(row) * period, width: cardWidth, height: cardHeight))
                card.backgroundColor = UIColor(white: dark ? 0.08 : 1, alpha: glassOpacity)
                card.layer.cornerRadius = 24
                card.layer.borderWidth = 1
                card.layer.borderColor = UIColor.white.withAlphaComponent(dark ? 0.22 : 0.48).cgColor
                card.clipsToBounds = true
                document.addSubview(card)
                cards.append((String(format: "C%02d", index), card))
                for slot in 0..<4 {
                    let iconIndex = index * 4 + slot
                    let icon = UIView(frame: CGRect(x: slot % 2 == 0 ? 14 : cardWidth - 14 - iconSide,
                                                    y: slot / 2 == 0 ? 12 : cardHeight - 12 - iconSide,
                                                    width: iconSide, height: iconSide))
                    icon.backgroundColor = UIColor(hue: CGFloat((iconIndex * 17 + index * 7) % 101) / 101,
                                                   saturation: 0.58, brightness: 0.72 + CGFloat(iconIndex % 3) * 0.08, alpha: 1)
                    icon.layer.cornerRadius = 12
                    icon.clipsToBounds = true
                    let symbol = UIImageView(image: UIImage(systemName: symbols[iconIndex % symbols.count]))
                    symbol.tintColor = .white
                    symbol.contentMode = .scaleAspectFit
                    symbol.frame = icon.bounds.insetBy(dx: 13, dy: 13)
                    icon.addSubview(symbol)
                    card.addSubview(icon)
                    icons.append((String(format: "I%03d", iconIndex), icon))
                }
                let label = UILabel(frame: CGRect(x: card.frame.minX, y: card.frame.maxY + 7, width: cardWidth, height: 23))
                label.text = names[index % names.count]
                label.font = .systemFont(ofSize: 14, weight: .medium)
                label.textColor = dark ? .white : UIColor(white: 0.12, alpha: 1)
                label.textAlignment = .center
                document.addSubview(label)
            }
        }
        documentHeight = 22 + 20 * period + 16
    }

    private func updateMetadata() {
        guard documentHeight > 0, let window = view.window else { return }
        let viewport = scroll.convert(scroll.bounds, to: window)
        let payload: [String: Any] = [
            "source": "synthetic-glass-grid", "variant": dark ? "dark" : "light", "glassOpacity": glassOpacity,
            "screenScale": window.screen.scale, "contentOffset": scroll.contentOffset.y,
            "viewport": rect(viewport), "contentHeight": documentHeight,
            "cards": cards.map { card -> [String: Any] in
                ["id": card.id, "rect": rect(card.view.convert(card.view.bounds, to: document))]
            },
            "icons": icons.map { icon -> [String: Any] in
                ["id": icon.id, "opaqueInnerRect": rect(icon.view.convert(icon.view.bounds.insetBy(dx: 6, dy: 6), to: document))]
            }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
            metadata.accessibilityValue = String(data: data, encoding: .utf8)
        }
    }

    private func rect(_ rectangle: CGRect) -> [String: Double] {
        ["x": Double(rectangle.minX), "y": Double(rectangle.minY),
         "width": Double(rectangle.width), "height": Double(rectangle.height)]
    }

    private func makeBackdrop(size: CGSize) -> UIImage {
        // Render a smooth blue/purple glow plus subtle broad color ripples.
        // The ripple is part of a normal fixed background, not a content ID.
        let width = Int(size.width.rounded(.up)), height = Int(size.height.rounded(.up))
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let px = Double(x), py = Double(y)
                let glow = exp(-pow((px - Double(width) * 0.25) / 210, 2) - pow((py - Double(height) * 0.48) / 260, 2))
                let wave = sin(py / 145 + 0.7)
                let ripple = 8 * sin(px / 7.5 + 0.5 * sin(py / 30)) * sin(py / 6 + 0.7)
                let base = dark ? 30.0 : 105.0
                let values = [base + 65 * glow + 20 * wave + ripple,
                              base + 25 * glow + 30 * wave + ripple,
                              base + 65 + 25 * glow + 15 * wave + ripple]
                let start = (y * width + x) * 4
                for channel in 0..<3 { pixels[start + channel] = UInt8(clamping: Int(values[channel].rounded())) }
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
}
