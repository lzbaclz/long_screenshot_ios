import SwiftUI
import UIKit

struct CaptureDetailView: View {
    @EnvironmentObject private var library: CaptureLibrary
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID
    @State private var session: CaptureSessionManifest?
    @State private var preview: UIImage?
    @State private var previewFailed = false
    @State private var isBusy = false
    @State private var message: String?
    @State private var showEditor = false
    @State private var showDelete = false
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
                } else if !session.hasImage {
                    ContentUnavailableView {
                        Label("未捕捉到可用画面", systemImage: "photo.badge.exclamationmark")
                    } description: {
                        Text("本次没有可编辑或导出的图片，也未扣除导出次数。请先查看上方结束原因，再返回首页重新捕捉。")
                    } actions: {
                        Button("返回首页") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(.white)
                    }
                    .accessibilityIdentifier("detail.noImage")
                } else if previewFailed {
                    unavailableImage
                } else {
                    ProgressView("正在准备预览…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if session.hasImage && preview != nil { exportBar }
            } else if previewFailed {
                unavailableImage
            } else {
                ProgressView("正在打开长图…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .paperBackground()
        .navigationTitle(LocalizedStringKey(session?.isDemo == true ? "长图示例" : "长图预览"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if session?.hasImage == true {
                    Button { showEditor = true } label: { Text("编辑") }
                        .disabled(isBusy || preview == nil)
                        .accessibilityIdentifier("detail.edit")
                }
                Button(role: .destructive) { showDelete = true } label: { Image(systemName: "trash") }
                    .disabled(isBusy || session == nil)
                    .accessibilityLabel("删除截图")
                    .accessibilityIdentifier("detail.delete")
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showEditor, onDismiss: { Task { await reload() } }) {
            if let session { CaptureEditorView(session: session) }
        }
        .sheet(item: $shareFile) { item in
            ShareImageSheet(url: item.url) { completed in
                purchases.recordShareCompletion(sessionID: sessionID, completed: completed)
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

    private var unavailableImage: some View {
        ContentUnavailableView {
            Label("暂时无法打开画面", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("这张长图暂时无法打开。原始文件仍保存在本机，请稍后重试。")
        } actions: {
            Button("重新加载") { Task { await reload() } }
        }
    }

    private func information(_ session: CaptureSessionManifest) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(LocalizedStringKey(session.stateLabel), systemImage: session.isFailedCapture || session.startWarning != nil ? "exclamationmark.circle.fill" :
                        (session.status == .completed ? "checkmark.circle.fill" : "arrow.clockwise.circle"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ScrollTheme.teal)
                Spacer()
                if session.hasImage {
                    Text(String(format: L10n.text("原图 %lld × %lld"), Int64(session.pixelWidth), Int64(session.pixelHeight)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ScrollTheme.secondary)
                }
            }
            if let notice = session.noticeText {
                Text(session.localizedNoticeText ?? notice)
                    .font(.caption)
                    .foregroundStyle(ScrollTheme.secondary)
                    .accessibilityIdentifier("detail.recoveredNotice")
            }
            if session.leadingEdgeStripID != nil || session.trailingEdgeStripID != nil {
                Text("自动衔接已保留首尾完整画面，顶部和底部可继续裁剪。")
                    .font(.caption)
                    .foregroundStyle(ScrollTheme.secondary)
            }
            if let diagnostics = session.diagnostics {
                DisclosureGroup("捕捉详情") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(String(format: L10n.text("停止阶段：%@"), L10n.text(diagnostics.stageLabel)))
                        Text(String(format: L10n.text("结束类型：%@"), L10n.text(diagnostics.terminationLabel)))
                        Text(String(format: L10n.text("已处理 %lld 帧 · 已衔接 %lld 帧"),
                                    Int64(diagnostics.observedFrames), Int64(diagnostics.acceptedFrames)))
                        Text(String(format: L10n.text("未衔接 %lld 帧 · 恢复 %lld 次"),
                                    Int64(diagnostics.rejectedFrames), Int64(diagnostics.recoveredGaps)))
                        Text(String(format: L10n.text("单帧最长处理 %.0f 毫秒"), diagnostics.maximumProcessingMilliseconds))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .font(.caption)
                    .foregroundStyle(ScrollTheme.secondary)
                }
                .font(.caption)
                .accessibilityIdentifier("detail.diagnostics")
            }
            if session.isDemo {
                Text(LocalizedStringKey(session.hasImage
                    ? "这是生成的示例图片，用来体验编辑和导出，并非真实跨应用捕捉。"
                    : "这是本机生成的失败示例，用来检查界面，并非真实跨应用捕捉。"))
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
        preview = nil
        previewFailed = false
        do {
            session = try repository.loadSession(id: sessionID)
            if session?.hasImage == true { preview = try await library.preview(sessionID: sessionID, maxDimension: 6000) }
        } catch {
            previewFailed = true
            message = String(localized: "这张长图暂时无法打开。原始文件仍保存在本机，请稍后重试。")
        }
    }

    private func beginExport(_ action: ExportAction) {
        guard !isBusy, session?.hasImage == true, preview != nil else { return }
        guard purchases.canExport(sessionID: sessionID) else {
            message = String(localized: "本周免费额度已用完，下周一恢复。已导出的作品仍可重复保存和分享；捕捉、查看和编辑不受影响。")
            return
        }
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
