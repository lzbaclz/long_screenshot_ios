import SwiftUI
import UIKit

@main
struct FixtureReaderApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--glass-grid") {
                GlassGridHost()
                    .ignoresSafeArea()
                    .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--glass-dark") ? .dark : .light)
            } else if ProcessInfo.processInfo.arguments.contains("--wallpaper-chat")
                || ProcessInfo.processInfo.arguments.contains("--same-color-header-chat") {
                WallpaperChatHost()
                    .statusBarHidden(ProcessInfo.processInfo.arguments.contains("--same-color-header-chat"))
                    .ignoresSafeArea()
                    .preferredColorScheme(.light)
            } else {
                FixtureReaderView()
            }
        }
    }
}

private struct FixtureReaderView: View {
    @State private var scenario = "聊天"
    @State private var dark = false
    @State private var rows = 120
    private let cases = ["聊天", "文章", "评论"]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    HStack {
                        Picker("场景", selection: $scenario) {
                            ForEach(cases, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.segmented)
                        Toggle("深色", isOn: $dark).labelsHidden()
                            .accessibilityLabel("深色测试页面")
                    }.padding()
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            Text("合成测试内容").font(.largeTitle.bold()).id("top")
                            Text("本页只包含生成的测试文字，用于在两个开发 App 之间验证滚动捕捉。编号应连续出现一次。")
                                .font(.callout).foregroundStyle(.secondary)
                            ForEach(0..<rows, id: \.self) { index in
                                fixtureRow(index).id(index)
                            }
                            Text("测试内容结束 END \(rows - 1)")
                                .font(.title2.bold()).id("bottom")
                        }.padding(20)
                    }
                    .accessibilityIdentifier("fixture.scroll")
                    HStack {
                        Text("固定底栏").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("回到起点") { proxy.scrollTo("top", anchor: .top) }
                            .accessibilityIdentifier("fixture.reset")
                    }.padding()
                }
            }
            .navigationTitle("截图测试页")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(dark ? .dark : .light)
    }

    @ViewBuilder
    private func fixtureRow(_ index: Int) -> some View {
        let code = String(format: "%04d", index)
        let paragraph = "条目 \(code) · 连续编号用于核对漏行和重复。内容色块、行距与长度按编号变化，所有文字均为测试生成。"
        if scenario == "聊天" {
            HStack(alignment: .top, spacing: 10) {
                if index.isMultiple(of: 3) { Spacer(minLength: 32) }
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hue: Double(index % 17) / 17, saturation: 0.45, brightness: 0.8))
                    .frame(width: 38, height: 38)
                    .overlay(Text(String(index % 10)).foregroundStyle(.white).bold())
                Text(paragraph)
                    .font(.body).padding(14)
                    .background(index.isMultiple(of: 3) ? Color.green.opacity(0.22) : Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if !index.isMultiple(of: 3) { Spacer(minLength: 32) }
            }.accessibilityIdentifier("fixture.row.\(code)")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(scenario) \(code)").font(.headline)
                Text(paragraph + (index.isMultiple(of: 4) ? " 多行内容测试：在原始屏幕尺寸下核对文字清晰度和行末边界。" : ""))
                if index.isMultiple(of: 5) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [.blue.opacity(0.5), .cyan.opacity(0.25)], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 100)
                        .overlay(Text("静态测试图片 \(code)").font(.title3.bold()))
                }
                Divider()
            }.accessibilityIdentifier("fixture.row.\(code)")
        }
    }
}

/// A separate, fully synthetic fixture: the wallpaper stays in screen coordinates
/// while opaque message bubbles move through a real, transparent UIScrollView.
private struct WallpaperChatHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WallpaperChatController { WallpaperChatController() }
    func updateUIViewController(_ controller: WallpaperChatController, context: Context) {}
}

private final class WallpaperChatController: UIViewController, UIScrollViewDelegate {
    private let sameColorHeader = ProcessInfo.processInfo.arguments.contains("--same-color-header-chat")
    private var hideIdentifiers: Bool {
        sameColorHeader || ProcessInfo.processInfo.arguments.contains("--wallpaper-hide-identifiers")
    }
    private let recordingIndicatorAfterFirstFrame = ProcessInfo.processInfo.arguments.contains("--recording-indicator-after-first-frame")
    private var indicatorVisible = ProcessInfo.processInfo.arguments.contains("--recording-indicator-in-first-frame")
    private let syntheticClock = UILabel()
    private let syntheticSignal = UIImageView(image: UIImage(systemName: "cellularbars"))
    private let syntheticWiFi = UIImageView(image: UIImage(systemName: "wifi"))
    private let syntheticBattery = UIImageView(image: UIImage(systemName: "battery.100"))
    private let syntheticBack = UIImageView(image: UIImage(systemName: "chevron.left"))
    private let syntheticIndicator = UIView()
    private let syntheticRecordingDot = UIView()
    private let indicatorButton = UIButton(type: .system)
    // This is a fixture-only status bar. It never controls the system capture
    // indicator or ReplayKit; the existing wallpaper mode retains system UI.
    override var prefersStatusBarHidden: Bool { sameColorHeader }
    private let wallpaper = UIImageView()
    private let header = UIView()
    private let footer = UIView()
    private let titleLabel = UILabel()
    private let metadataLabel = UILabel()
    private let footerLabel = UILabel()
    private let resetButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let documentView = UIView()
    private var messages: [MessageGeometry] = []
    private var previousViewportSize = CGSize.zero
    private var wallpaperSize = CGSize.zero
    private var hasPositionedInitially = false
    private var documentHeight: CGFloat = 0

    private struct MessageGeometry {
        let id: String
        let kind: String
        let alignment: String
        let bubble: UIView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = sameColorHeader ? UIColor(white: 237.0 / 255, alpha: 1) : .white
        wallpaper.isHidden = sameColorHeader
        wallpaper.contentMode = .scaleToFill
        wallpaper.isAccessibilityElement = false
        wallpaper.isUserInteractionEnabled = false
        view.addSubview(wallpaper)

        scrollView.backgroundColor = .clear
        scrollView.isOpaque = false
        scrollView.delegate = self
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
        scrollView.showsVerticalScrollIndicator = false
        scrollView.scrollsToTop = false
        scrollView.accessibilityIdentifier = "fixture.wallpaper.scroll"
        scrollView.accessibilityLabel = "合成固定壁纸聊天，可上下滚动"
        documentView.backgroundColor = .clear
        documentView.isOpaque = false
        scrollView.addSubview(documentView)
        view.addSubview(scrollView)

        for bar in [header, footer] {
            bar.backgroundColor = sameColorHeader ? UIColor(white: 237.0 / 255, alpha: 1)
                : UIColor(red: 0.95, green: 0.96, blue: 0.93, alpha: 1)
            view.addSubview(bar)
        }
        titleLabel.text = sameColorHeader ? "合成聊天" : "固定壁纸 · 合成聊天测试"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .black
        titleLabel.textAlignment = .center
        header.addSubview(titleLabel)
        metadataLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        metadataLabel.textColor = .darkGray
        metadataLabel.textAlignment = .center
        metadataLabel.isAccessibilityElement = true
        metadataLabel.accessibilityTraits = .staticText
        metadataLabel.accessibilityLabel = "合成壁纸聊天布局数据"
        metadataLabel.accessibilityIdentifier = "fixture.wallpaper.metadata"
        header.addSubview(metadataLabel)

        footerLabel.text = "程序生成壁纸与消息 · 不含私人内容"
        footerLabel.font = .systemFont(ofSize: 10)
        footerLabel.textColor = .darkGray
        footer.addSubview(footerLabel)
        resetButton.setTitle("回到中间", for: .normal)
        resetButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        resetButton.accessibilityIdentifier = "fixture.wallpaper.reset"
        resetButton.addTarget(self, action: #selector(resetToMiddle), for: .touchUpInside)
        footer.addSubview(resetButton)
        if sameColorHeader { configureSyntheticHeader() }
    }

    private func configureSyntheticHeader() {
        if recordingIndicatorAfterFirstFrame { indicatorVisible = false }
        syntheticClock.text = "09:41"
        syntheticClock.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        syntheticClock.textColor = .black
        let statusElements: [UIView] = [syntheticClock, syntheticSignal, syntheticWiFi, syntheticBattery, syntheticBack]
        for element in statusElements {
            element.tintColor = .black
            element.isAccessibilityElement = false
            header.addSubview(element)
        }
        syntheticIndicator.backgroundColor = .black
        syntheticIndicator.layer.cornerRadius = 16
        syntheticIndicator.isHidden = !indicatorVisible
        syntheticIndicator.isAccessibilityElement = false
        header.addSubview(syntheticIndicator)
        syntheticRecordingDot.backgroundColor = .systemRed
        syntheticRecordingDot.layer.cornerRadius = 5
        syntheticIndicator.addSubview(syntheticRecordingDot)
        // The test taps this only AFTER obtaining and ingesting the first
        // screenshot. No timer races the screenshot or first-scroll boundary.
        indicatorButton.setTitle("录屏指示", for: .normal)
        indicatorButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        indicatorButton.accessibilityIdentifier = "fixture.header.toggle-indicator"
        indicatorButton.accessibilityValue = indicatorVisible ? "visible" : "hidden"
        indicatorButton.addTarget(self, action: #selector(toggleSyntheticIndicator), for: .touchUpInside)
        footer.addSubview(indicatorButton)
        footerLabel.text = "纯程序生成"
    }

    @objc private func toggleSyntheticIndicator() {
        indicatorVisible.toggle()
        syntheticIndicator.isHidden = !indicatorVisible
        indicatorButton.accessibilityValue = indicatorVisible ? "visible" : "hidden"
        updateMetadata()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let headerHeight: CGFloat = sameColorHeader ? 100 : view.safeAreaInsets.top + 61
        let footerHeight = view.safeAreaInsets.bottom + 56
        header.frame = CGRect(x: 0, y: 0, width: width, height: headerHeight)
        footer.frame = CGRect(x: 0, y: view.bounds.height - footerHeight, width: width, height: footerHeight)
        titleLabel.frame = CGRect(x: 12, y: sameColorHeader ? 57 : view.safeAreaInsets.top + 7,
                                  width: width - 24, height: 23)
        metadataLabel.frame = CGRect(x: 8, y: headerHeight - 24, width: width - 16, height: 17)
        footerLabel.frame = CGRect(x: 13, y: 16, width: max(0, width - 120), height: 20)
        resetButton.frame = CGRect(x: width - 101, y: 6, width: 91, height: 43)
        if sameColorHeader {
            syntheticClock.frame = CGRect(x: 24, y: 17, width: 59, height: 23)
            syntheticSignal.frame = CGRect(x: width - 85, y: 21, width: 17, height: 15)
            syntheticWiFi.frame = CGRect(x: width - 63, y: 21, width: 17, height: 15)
            syntheticBattery.frame = CGRect(x: width - 41, y: 20, width: 25, height: 17)
            syntheticBack.frame = CGRect(x: 17, y: 60, width: 12, height: 20)
            // Extend beyond the simulator's Dynamic Island so the synthetic
            // change and red dot remain visible beside its system-owned mask.
            syntheticIndicator.frame = CGRect(x: (width - 200) / 2, y: 12, width: 200, height: 33)
            syntheticRecordingDot.frame = CGRect(x: 12, y: 11, width: 10, height: 10)
            indicatorButton.frame = CGRect(x: width / 2 - 46, y: 6, width: 92, height: 43)
        }
        wallpaper.frame = view.bounds
        if !sameColorHeader, wallpaperSize != view.bounds.size, width > 0, view.bounds.height > 0 {
            wallpaperSize = view.bounds.size
            wallpaper.image = SyntheticScenery.image(size: wallpaperSize, seed: 0xCAFE_0137)
        }

        let viewport = CGRect(x: 0, y: headerHeight, width: width,
                              height: max(1, view.bounds.height - headerHeight - footerHeight))
        let previousMaximum = max(1, documentHeight - previousViewportSize.height)
        let oldFraction = scrollView.contentOffset.y / previousMaximum
        scrollView.frame = viewport
        if previousViewportSize != viewport.size, width > 0 {
            previousViewportSize = viewport.size
            buildMessages(width: width)
            documentView.frame = CGRect(x: 0, y: 0, width: width, height: documentHeight)
            scrollView.contentSize = CGSize(width: width, height: documentHeight)
            let maximum = max(0, documentHeight - viewport.height)
            if !hasPositionedInitially {
                hasPositionedInitially = true
                let arguments = ProcessInfo.processInfo.arguments
                let initialFraction: CGFloat = arguments.contains("--wallpaper-start=top") ? 0
                    : (arguments.contains("--wallpaper-start=bottom") ? 1 : 0.5)
                scrollView.setContentOffset(CGPoint(x: 0, y: maximum * initialFraction), animated: false)
            } else {
                scrollView.setContentOffset(CGPoint(x: 0, y: maximum * min(1, max(0, oldFraction))), animated: false)
            }
        }
        updateMetadata()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateMetadata() }

    @objc private func resetToMiddle() {
        scrollView.setContentOffset(CGPoint(x: 0, y: max(0, documentHeight - scrollView.bounds.height) / 2), animated: false)
        updateMetadata()
    }

    private func buildMessages(width: CGFloat) {
        documentView.subviews.forEach { $0.removeFromSuperview() }
        messages.removeAll(keepingCapacity: true)
        let maximumBubbleWidth = min(268, width - 112)
        let paragraphs = [
            "好呀", "这是一段合成测试文字，用来观察消息与固定背景分别怎样移动。", "收到",
            "周末的小计划：沿着河边走一段，看看桥下的水面，再找一个安静的地方读书。",
            "图片是程序画出来的，没有使用任何人的照片。", "嗯嗯", "等一会儿，看看云。",
            "白色气泡、绿色气泡、短句和多行内容交替出现。这里没有真实姓名、私人聊天或账号。",
            "可以往上看，也可以往下读。", "这片颜色像清晨的山谷。"
        ]
        var y: CGFloat = 18
        for index in 0..<64 {
            let id = String(format: "M%03d", index)
            if index.isMultiple(of: 7) {
                let timestamp = UILabel(frame: CGRect(x: (width - 156) / 2, y: y, width: 156, height: 23))
                timestamp.text = String(format: "合成时间  %02d:%02d", 9 + index / 14, (index * 3) % 60)
                timestamp.font = .systemFont(ofSize: 10, weight: .medium)
                timestamp.textAlignment = .center
                timestamp.textColor = .white
                timestamp.backgroundColor = UIColor.black.withAlphaComponent(0.24)
                timestamp.layer.cornerRadius = 7
                timestamp.clipsToBounds = true
                documentView.addSubview(timestamp)
                y += 38
            }
            let outgoing = index % 4 == 1 || index % 4 == 2
            let picture = index % 9 == 4 || index % 13 == 9
            let bubble = UIView()
            bubble.backgroundColor = outgoing ? UIColor(red: 0.66, green: 0.92, blue: 0.40, alpha: 1) : .white
            bubble.isOpaque = true
            bubble.layer.cornerRadius = 13
            bubble.clipsToBounds = true
            bubble.accessibilityIdentifier = "fixture.wallpaper.message.\(id)"
            bubble.isAccessibilityElement = false
            let bubbleWidth: CGFloat
            let bubbleHeight: CGFloat
            if picture {
                bubbleWidth = min(226, maximumBubbleWidth)
                bubbleHeight = 172
                let image = UIImageView(frame: CGRect(x: 8, y: 8, width: bubbleWidth - 16, height: 126))
                image.image = SyntheticScenery.image(size: image.bounds.size, seed: UInt64(index + 91) * 131)
                image.layer.cornerRadius = 8
                image.clipsToBounds = true
                bubble.addSubview(image)
                let caption = UILabel(frame: CGRect(x: 12, y: 140, width: bubbleWidth - 24, height: 20))
                caption.font = .systemFont(ofSize: 12)
                caption.textColor = .black
                caption.text = index.isMultiple(of: 2) ? "合成风景 · 山间光影" : "合成图片 · 颜色练习"
                bubble.addSubview(caption)
            } else {
                let text = UILabel()
                // Some messages contain unique visible codes, while most short
                // phrases remain deliberately repeated and unnumbered.
                text.text = (index % 6 == 3 ? "测试片段 \(id)\n" : "") + paragraphs[index % paragraphs.count]
                text.numberOfLines = 0
                text.font = .systemFont(ofSize: 16)
                text.textColor = .black
                let fitted = text.sizeThatFits(CGSize(width: maximumBubbleWidth - 26, height: 1000))
                // Keep the same bubble dimensions and document positions in
                // both modes, while removing synthetic codes from rendered text.
                if hideIdentifiers { text.text = paragraphs[index % paragraphs.count] }
                bubbleWidth = max(58, min(maximumBubbleWidth, ceil(fitted.width) + 26))
                bubbleHeight = max(44, ceil(fitted.height) + 24)
                text.frame = CGRect(x: 13, y: 12, width: bubbleWidth - 26, height: bubbleHeight - 24)
                bubble.addSubview(text)
            }
            let bubbleX = outgoing ? width - 52 - bubbleWidth : 52
            bubble.frame = CGRect(x: bubbleX, y: y, width: bubbleWidth, height: bubbleHeight)
            documentView.addSubview(bubble)
            let avatar = UILabel(frame: CGRect(x: outgoing ? width - 43 : 11, y: y, width: 32, height: 32))
            avatar.text = outgoing ? "叶" : "山"
            avatar.textColor = .white
            avatar.textAlignment = .center
            avatar.font = .systemFont(ofSize: 17, weight: .semibold)
            avatar.backgroundColor = outgoing ? UIColor(red: 0.38, green: 0.54, blue: 0.26, alpha: 1)
                                              : UIColor(red: 0.43, green: 0.45, blue: 0.69, alpha: 1)
            avatar.layer.cornerRadius = 7
            avatar.clipsToBounds = true
            documentView.addSubview(avatar)
            let identifier = UILabel(frame: CGRect(x: bubbleX + 3, y: y + bubbleHeight + 2,
                                                   width: bubbleWidth - 6, height: 11))
            identifier.text = id
            identifier.textColor = UIColor(white: 0.12, alpha: 1)
            identifier.font = .monospacedSystemFont(ofSize: 8, weight: .semibold)
            identifier.textAlignment = outgoing ? .right : .left
            identifier.backgroundColor = .clear
            identifier.isHidden = hideIdentifiers
            documentView.addSubview(identifier)
            messages.append(MessageGeometry(id: id, kind: picture ? "image" : "text",
                                            alignment: outgoing ? "right" : "left", bubble: bubble))
            y += bubbleHeight + 26
        }
        documentHeight = y + 24
    }

    private func updateMetadata() {
        guard scrollView.bounds.width > 0, documentHeight > 0 else { return }
        let viewport = scrollView.convert(scrollView.bounds, to: nil)
        let geometry: [[String: Any]] = messages.map { message in
            let rectangle = message.bubble.convert(message.bubble.bounds, to: documentView)
            return ["id": message.id, "kind": message.kind, "alignment": message.alignment,
                    "bubbleRect": rectangleJSON(rectangle),
                    // The 14-point inset excludes rounded corners. Every point
                    // inside this rectangle has an opaque bubble/image backdrop.
                    "opaqueInnerRect": rectangleJSON(rectangle.insetBy(dx: 14, dy: 14))]
        }
        let payload: [String: Any] = [
            "formatVersion": 1,
            "source": sameColorHeader ? "synthetic-same-color-header-chat" : "synthetic-fixed-wallpaper-chat",
            "indicatorVisible": indicatorVisible,
            "units": "points",
            "contentOffset": ["x": Double(scrollView.contentOffset.x), "y": Double(scrollView.contentOffset.y)],
            "viewport": rectangleJSON(viewport),
            "contentHeight": Double(scrollView.contentSize.height),
            "screenScale": Double(view.window?.screen.scale ?? UIScreen.main.scale),
            "messages": geometry
        ]
        // Keep the oracle accessible without adding artificial fixed glyphs
        // beside the ordinary title or overlapping its rendered pixels.
        metadataLabel.text = sameColorHeader ? nil
            : String(format: "offset %.1f / %.1f pt · %d 条合成消息",
                     scrollView.contentOffset.y, documentHeight, messages.count)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            metadataLabel.accessibilityValue = json
        }
    }

    private func rectangleJSON(_ rect: CGRect) -> [String: Double] {
        ["x": Double(rect.minX), "y": Double(rect.minY),
         "width": Double(rect.width), "height": Double(rect.height)]
    }
}

/// Deterministic, program-drawn landscape texture. No external media or user
/// images are loaded. The same screen point remains unchanged during scrolling.
private enum SyntheticScenery {
    static func image(size: CGSize, seed: UInt64) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            var random = TextureRandom(seed: seed)
            let colors = [UIColor(red: 0.32, green: 0.58, blue: 0.72, alpha: 1).cgColor,
                          UIColor(red: 0.87, green: 0.70, blue: 0.51, alpha: 1).cgColor,
                          UIColor(red: 0.22, green: 0.43, blue: 0.30, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                         locations: [0, 0.52, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            for _ in 0..<95 {
                let radius = 10 + random.unit() * 90
                let rectangle = CGRect(x: random.unit() * size.width - radius / 2,
                                       y: random.unit() * size.height, width: radius * 1.7, height: radius)
                context.setFillColor(UIColor(red: 0.75 + random.unit() * 0.25,
                                             green: 0.60 + random.unit() * 0.35,
                                             blue: 0.39 + random.unit() * 0.5, alpha: 0.08 + random.unit() * 0.19).cgColor)
                context.fillEllipse(in: rectangle)
            }
            for layer in 0..<6 {
                let baseline = size.height * (0.26 + CGFloat(layer) * 0.115)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: -30, y: baseline))
                var x: CGFloat = -30
                while x < size.width + 60 {
                    x += 20 + random.unit() * 36
                    path.addLine(to: CGPoint(x: x, y: baseline + random.unit() * size.height * 0.13))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.close()
                UIColor(red: 0.15 + CGFloat(layer) * 0.035, green: 0.31 + random.unit() * 0.23,
                        blue: 0.29 + random.unit() * 0.23, alpha: 0.32 + CGFloat(layer) * 0.075).setFill()
                path.fill()
            }
            // Fine, irregular color detail supplies stationary high-frequency
            // structure, unlike the old mostly flat-color scrolling fixture.
            for _ in 0..<4500 {
                let x = random.unit() * size.width
                let y = random.unit() * size.height
                let radius = 0.7 + random.unit() * 4.3
                context.setFillColor(UIColor(hue: 0.06 + random.unit() * 0.44,
                                             saturation: 0.16 + random.unit() * 0.57,
                                             brightness: 0.34 + random.unit() * 0.62,
                                             alpha: 0.12 + random.unit() * 0.46).cgColor)
                context.fillEllipse(in: CGRect(x: x, y: y, width: radius * 1.8, height: radius))
            }
            for _ in 0..<130 {
                let x = random.unit() * size.width
                let y = random.unit() * size.height
                let length = 14 + random.unit() * 58
                context.setStrokeColor(UIColor(red: 0.12, green: 0.25 + random.unit() * 0.2,
                                               blue: 0.16, alpha: 0.2 + random.unit() * 0.3).cgColor)
                context.setLineWidth(0.7 + random.unit() * 1.4)
                context.move(to: CGPoint(x: x, y: y))
                context.addQuadCurve(to: CGPoint(x: x + length * 0.44, y: y - length),
                                     control: CGPoint(x: x - length * 0.21, y: y - length * 0.4))
                context.strokePath()
            }
        }
    }

    private struct TextureRandom {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func unit() -> CGFloat {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(Double(state >> 32) / Double(UInt32.max))
        }
    }
}
