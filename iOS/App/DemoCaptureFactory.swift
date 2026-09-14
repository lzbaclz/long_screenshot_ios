import UIKit

/// Explicit --demo mode uses generated illustrations in an isolated repository.
/// It never claims to exercise ReplayKit or another application's screen.
@MainActor
enum DemoCaptureFactory {
    static func seed(repository: CaptureSessionRepository) throws {
        guard try repository.listSessions().isEmpty else { return }
        for index in 0..<3 {
            // Stable fixture identity and creation time make screenshots and UI assertions reproducible.
            let id = UUID(uuidString: "D3E00000-0000-4000-8000-00000000000\(index + 1)")!
            var manifest = CaptureSessionManifest(id: id,
                createdAt: Date(timeIntervalSince1970: 1_789_293_600 + Double(index) * 60),
                configuration: .init(), isDemo: true)
            try FileManager.default.createDirectory(at: repository.sessionDirectory(id: id),
                                                    withIntermediateDirectories: true)
            try repository.saveManifest(manifest)
            for page in 0..<(index == 2 ? 2 : 3) {
                let image = makePage(page: page, variant: index)
                guard let cgImage = image.cgImage else { continue }
                try repository.appendStrip(image: cgImage, to: &manifest)
            }
            manifest.status = index == 2 ? .interrupted : .completed
            manifest.stopReason = index == 2 ? "示例：捕捉中途停止，已保存的部分可以继续编辑和导出。" : nil
            try repository.saveManifest(manifest)
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-empty-capture") {
            // An explicit synthetic failure fixture exercises legacy zero-frame presentation.
            let id = UUID(uuidString: "D3E00000-0000-4000-8000-000000000004")!
            var manifest = CaptureSessionManifest(id: id,
                createdAt: Date(timeIntervalSince1970: 1_789_293_800), isDemo: true)
            try FileManager.default.createDirectory(at: repository.sessionDirectory(id: id),
                                                    withIntermediateDirectories: true)
            manifest.status = .partial
            manifest.stopReason = "画面无法可靠衔接，已保存连续部分。请降低滑动速度或调整捕捉区域后重试。"
            try repository.saveManifest(manifest)
        }
    }

    private static func makePage(page: Int, variant: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1100), format: format).image { context in
            UIColor(red: 0.985, green: 0.98, blue: 0.96, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 720, height: 1100))
            let ink = UIColor(red: 0.13, green: 0.21, blue: 0.24, alpha: 1)
            let teal = UIColor(red: 0.02, green: 0.47, blue: 0.43, alpha: 1)
            let subtitle = UIColor(red: 0.43, green: 0.49, blue: 0.49, alpha: 1)
            draw("SLOW NOTES  /  长截图示例", at: CGPoint(x: 52, y: 42), size: 20, color: teal, weight: .semibold)
            let titles = ["把日子过成\n喜欢的样子", "周末，留一点\n时间给自己", "那些想要\n留下的小事"]
            let title = page == 0 ? titles[variant] : (page == 1 ? "慢下来，\n才能看见更多" : "让值得的瞬间\n好好留下")
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 12
            (L10n.text(title) as NSString).draw(in: CGRect(x: 52, y: 104, width: 620, height: 190), withAttributes: [
                .font: UIFont.systemFont(ofSize: 57, weight: .bold), .foregroundColor: ink, .paragraphStyle: paragraph
            ])
            let panel = CGRect(x: 52, y: 325, width: 616, height: 270)
            UIColor(red: 0.83, green: 0.92, blue: 0.85, alpha: 1).setFill()
            UIBezierPath(roundedRect: panel, cornerRadius: 28).fill()
            let symbol = UIImage(systemName: page == 1 ? "sun.max.fill" : "mountain.2.fill",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 110, weight: .light))?
                .withTintColor(teal.withAlphaComponent(0.7), renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: 266, y: 365, width: 180, height: 155))
            draw(String(format: L10n.text("%02lld  记录生活里简单的美好"), Int64(page + 1)),
                 at: CGPoint(x: 52, y: 640), size: 28, color: ink, weight: .semibold)
            let lines = ["不赶时间的时候，沿着熟悉的小路散步。", "把看到的风景和想到的话，慢慢记下来。", "一本没读完的书，一杯刚刚好的咖啡，", "也可以成为今天最值得保留的片段。", "", "这是一张本地生成的演示图片。", "试试裁剪起止位置，或圈选需要遮挡的区域。"]
            for (index, line) in lines.enumerated() {
                draw(line, at: CGPoint(x: 52, y: 709 + CGFloat(index) * 43), size: 25, color: subtitle)
            }
            draw("DEMO  ·  \(page + 1) / 3", at: CGPoint(x: 52, y: 1050), size: 18, color: teal)
        }
    }

    private static func draw(_ text: String, at point: CGPoint, size: CGFloat, color: UIColor,
                             weight: UIFont.Weight = .regular) {
        (L10n.text(text) as NSString).draw(at: point, withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight),
                                                          .foregroundColor: color])
    }
}
