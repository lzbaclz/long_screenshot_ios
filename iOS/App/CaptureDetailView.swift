import SwiftUI
import UIKit

struct CaptureDetailView: View {
    @EnvironmentObject private var library: CaptureLibrary
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    @State private var session: CaptureSessionManifest?
    @State private var preview: UIImage?
    @State private var isBusy = false
    @State private var message: String?
    @State private var showEditor = false
    @State private var showDelete = false
    @State private var showUpgrade = false
    @State private var showSizeChoice = false
    @State private var shareFile: SharedImage?
    @State private var format = CaptureExportFormat.png
    @State private var pendingAction = ExportAction.photos

    private enum ExportAction { case photos, share }
    private struct SharedImage: Identifiable { let id = UUID(); let url: URL }

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                information(session)
                if let preview, let repository = library.repository {
                    TiledCapturePreview(session: session, repository: repository, fallback: preview)
                        .accessibilityLabel("长截图预览，可双指缩放和上下滑动")
                        .accessibilityIdentifier("detail.preview")
                        .overlay(alignment: .bottomTrailing) {
                            Label("双指放大查看", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: Capsule())
                                .padding(15)
                                .allowsHitTesting(false)
                        }
                } else if session.strips.isEmpty {
                    ContentUnavailableView("还没有可用画面", systemImage: "photo.badge.exclamationmark",
                                           description: Text("这次捕捉在保存画面前结束，请返回首页重新开始。"))
                } else {
                    ProgressView("正在准备预览…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                exportBar
            } else {
                ProgressView("正在打开长图…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .paperBackground()
        .navigationTitle(LocalizedStringKey(session?.isDemo == true ? "长图示例" : "长图预览"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showEditor = true } label: { Text("编辑") }
                    .disabled(isBusy || preview == nil)
                    .accessibilityIdentifier("detail.edit")
                Button(role: .destructive) { showDelete = true } label: { Image(systemName: "trash") }
                    .disabled(isBusy)
                    .accessibilityLabel("删除截图")
                    .accessibilityIdentifier("detail.delete")
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await reload() } }) {
            if let session { CaptureEditorView(session: session) }
        }
        .sheet(isPresented: $showUpgrade) { UpgradeView() }
        .sheet(item: $shareFile) { item in
            ShareImageSheet(url: item.url) { completed in
                if completed { purchases.recordSuccessfulExport(sessionID: sessionID) }
            }
        }
        .confirmationDialog("删除这张长图？", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除长图与原始画面", role: .destructive) {
                guard let session else { return }
                library.delete(session)
                if library.errorMessage == nil { dismiss() }
            }
        } message: { Text("删除后无法恢复。已保存到照片或其他应用的副本会保留。") }
        .alert("导出较小图片", isPresented: $showSizeChoice) {
            Button("导出较小图片") { Task { await runExport(allowDownscale: true) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这张长图超过单张图片的安全导出尺寸。可以等比例缩小后导出，原始画面会继续保留；也可以先裁剪需要的部分。")
        }
        .alert("续页", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("知道了") { message = nil } } message: { Text(message ?? "") }
    }

    private func information(_ session: CaptureSessionManifest) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(LocalizedStringKey(session.stateLabel), systemImage: session.startWarning != nil ? "exclamationmark.circle.fill" :
                        (session.status == .completed ? "checkmark.circle.fill" : "arrow.clockwise.circle"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ScrollTheme.teal)
                Spacer()
                Text(String(format: L10n.text("原图 %lld × %lld"), Int64(session.pixelWidth), Int64(session.pixelHeight)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ScrollTheme.secondary)
            }
            if let notice = session.noticeText {
                Text(session.localizedNoticeText ?? notice)
                    .font(.caption)
                    .foregroundStyle(ScrollTheme.secondary)
                    .accessibilityIdentifier("detail.recoveredNotice")
            }
            if session.isDemo {
                Text("这是生成的示例图片，用来体验编辑和导出，并非真实跨应用捕捉。")
                    .font(.caption2)
                    .foregroundStyle(ScrollTheme.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(.white)
    }

    private var exportBar: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("导出格式", selection: $format) {
                    Text("PNG · 清晰文字").tag(CaptureExportFormat.png)
                    Text("JPEG · 较小文件").tag(CaptureExportFormat.jpeg)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("detail.format")
            }
            HStack(spacing: 12) {
                Button { beginExport(.share) } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3.weight(.medium))
                        .frame(width: 57, height: 54)
                        .background(ScrollTheme.mint, in: RoundedRectangle(cornerRadius: 17))
                }
                .accessibilityLabel("分享长图")
                .accessibilityIdentifier("detail.share")
                Button { beginExport(.photos) } label: {
                    HStack(spacing: 8) {
                        if isBusy { ProgressView().tint(.white) }
                        else { Image(systemName: "square.and.arrow.down") }
                        Text(LocalizedStringKey(isBusy ? "正在处理…" : "保存到照片"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("detail.savePhotos")
            }
            .disabled(isBusy || preview == nil)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.white)
    }

    private func reload() async {
        guard let repository = library.repository else { return }
        do {
            session = try repository.loadSession(id: sessionID)
            if session?.strips.isEmpty == false { preview = try await library.preview(sessionID: sessionID, maxDimension: 6000) }
        } catch {
            message = String(localized: "这张长图暂时无法打开。原始文件仍保存在本机，请稍后重试。")
        }
    }

    private func beginExport(_ action: ExportAction) {
        guard !isBusy else { return }
        guard purchases.canExport(sessionID: sessionID) else { showUpgrade = true; return }
        pendingAction = action
        Task { await runExport() }
    }

    private func runExport(allowDownscale: Bool = false) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let url = try await library.export(sessionID: sessionID, format: format, allowDownscale: allowDownscale)
            switch pendingAction {
            case .photos:
                try await PhotoExporter.save(url)
                purchases.recordSuccessfulExport(sessionID: sessionID)
                message = String(localized: "已保存到照片。")
            case .share:
                shareFile = SharedImage(url: url)
            }
        } catch CaptureStorageError.exportTooLarge {
            showSizeChoice = true
        } catch let error as PhotoExporter.ExportError {
            message = error.localizedDescription
        } catch {
            message = String(localized: "导出没有完成，请检查剩余存储空间后重试。本次不会扣除导出次数。")
        }
    }
}

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ImageScrollView {
        let scrollView = ImageScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5
        scrollView.backgroundColor = UIColor(ScrollTheme.paper)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(scrollView.imageView)
        context.coordinator.imageView = scrollView.imageView
        return scrollView
    }

    func updateUIView(_ scrollView: ImageScrollView, context: Context) {
        guard scrollView.imageView.image !== image else { return }
        scrollView.imageView.image = image
        scrollView.needsImageLayout = true
        scrollView.setNeedsLayout()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }

    final class ImageScrollView: UIScrollView {
        let imageView = UIImageView()
        var needsImageLayout = true
        private var previousWidth: CGFloat = 0

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let image = imageView.image, bounds.width > 0,
                  needsImageLayout || previousWidth != bounds.width else { return }
            needsImageLayout = false
            previousWidth = bounds.width
            setZoomScale(1, animated: false)
            let width = max(1, bounds.width - 32)
            let height = width * image.size.height / max(1, image.size.width)
            imageView.frame = CGRect(x: 16, y: 16, width: width, height: height)
            contentSize = CGSize(width: bounds.width, height: height + 32)
            minimumZoomScale = 1
            contentOffset = .zero
        }
    }
}
