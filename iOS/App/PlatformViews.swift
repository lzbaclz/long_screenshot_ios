import SwiftUI
import ReplayKit
import Photos
import UIKit

/// Keep the system button visible and tappable. Do not invoke its private view hierarchy.
struct BroadcastPicker: UIViewRepresentable {
    let extensionIdentifier: String

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = extensionIdentifier
        picker.showsMicrophoneButton = false
        picker.tintColor = UIColor(ScrollTheme.teal)
        picker.accessibilityLabel = String(localized: "开始屏幕捕捉")
        picker.accessibilityHint = String(localized: "打开系统屏幕广播选项，选择续页并开始广播")
        picker.accessibilityIdentifier = "capture.systemPicker"
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

struct ShareImageSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            DispatchQueue.main.async { completion(completed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum PhotoExporter {
    enum ExportError: LocalizedError {
        case permissionDenied

        var errorDescription: String? {
            String(localized: "续页需要“添加照片”权限才能保存。你仍可使用分享，也可在系统设置中允许添加照片。")
        }
    }

    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ExportError.permissionDenied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
        }
    }
}

/// CATiledLayer asks for only the visible pieces, so zooming a 20-screen capture
/// does not require a full-resolution composite bitmap in memory.
struct TiledCapturePreview: UIViewRepresentable {
    let session: CaptureSessionManifest
    let repository: CaptureSessionRepository
    let fallback: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CaptureScrollView {
        let scroll = CaptureScrollView()
        scroll.delegate = context.coordinator
        scroll.backgroundColor = UIColor(ScrollTheme.paper)
        scroll.contentInsetAdjustmentBehavior = .never
        return scroll
    }

    func updateUIView(_ scroll: CaptureScrollView, context: Context) {
        guard scroll.revision != session.updatedAt else { return }
        scroll.canvas?.removeFromSuperview()
        let canvas = CaptureCanvas(session: session, repository: repository, fallback: fallback)
        scroll.canvas = canvas
        scroll.revision = session.updatedAt
        scroll.addSubview(canvas)
        context.coordinator.canvas = canvas
        scroll.needsCaptureLayout = true
        scroll.setNeedsLayout()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var canvas: CaptureCanvas?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }
    }

    final class CaptureScrollView: UIScrollView {
        var canvas: CaptureCanvas?
        var revision: Date?
        var needsCaptureLayout = true
        private var previousWidth: CGFloat = 0

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let canvas, bounds.width > 0, needsCaptureLayout || previousWidth != bounds.width else { return }
            needsCaptureLayout = false
            previousWidth = bounds.width
            minimumZoomScale = 0.001
            maximumZoomScale = 8
            setZoomScale(1, animated: false)
            canvas.frame = CGRect(origin: .zero, size: canvas.outputSize)
            contentSize = canvas.outputSize
            let fit = bounds.width / canvas.outputSize.width
            minimumZoomScale = fit
            maximumZoomScale = max(fit * 5, 2)
            setZoomScale(fit, animated: false)
            contentOffset = .zero
        }
    }

    final class CaptureCanvas: UIView {
        nonisolated let session: CaptureSessionManifest
        nonisolated let repository: CaptureSessionRepository
        nonisolated let fallback: UIImage
        nonisolated let outputSize: CGSize
        nonisolated private let sourceCrop: NormalizedRect

        override class var layerClass: AnyClass { CATiledLayer.self }

        init(session: CaptureSessionManifest, repository: CaptureSessionRepository, fallback: UIImage) {
            self.session = session
            self.repository = repository
            self.fallback = fallback
            let crop = session.edits.crop ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)
            sourceCrop = crop
            outputSize = CGSize(width: max(1, Double(session.pixelWidth) * crop.width),
                                height: max(1, Double(session.editedPixelHeight) * crop.height))
            super.init(frame: CGRect(origin: .zero, size: outputSize))
            isOpaque = true
            backgroundColor = .white
            if let tiles = layer as? CATiledLayer {
                tiles.tileSize = CGSize(width: 768, height: 768)
                tiles.levelsOfDetail = 5
                tiles.levelsOfDetailBias = 3
            }
            contentScaleFactor = 1
        }

        required init?(coder: NSCoder) { nil }

        // CATiledLayer invokes this on its drawing workers. Only immutable Sendable
        // snapshot state is accessed; UIKit view state remains on the main actor.
        nonisolated override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            let visible = rect.intersection(CGRect(origin: .zero, size: outputSize))
            guard !visible.isEmpty else { return }
            let crop = NormalizedRect(
                x: sourceCrop.x + visible.minX / outputSize.width * sourceCrop.width,
                y: sourceCrop.y + visible.minY / outputSize.height * sourceCrop.height,
                width: visible.width / outputSize.width * sourceCrop.width,
                height: visible.height / outputSize.height * sourceCrop.height
            )
            var edits = session.edits
            edits.crop = crop
            // A fixed upper bound keeps concurrent tile requests small even when zoomed.
            let dimension = max(128, min(1536, Int(ceil(max(visible.width, visible.height) * abs(context.ctm.a)))))
            if let image = try? CaptureImageRenderer(repository: repository)
                .preview(sessionID: session.id, maxDimension: dimension, editsOverride: edits) {
                image.draw(in: visible)
            } else {
                fallback.draw(in: CGRect(origin: .zero, size: outputSize))
            }
        }
    }
}
