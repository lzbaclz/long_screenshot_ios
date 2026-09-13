import SwiftUI

struct CaptureEditorView: View {
    @EnvironmentObject private var library: CaptureLibrary
    @Environment(\.dismiss) private var dismiss
    let session: CaptureSessionManifest
    @State private var edits: CaptureEditMetadata
    @State private var sourcePreview: UIImage?
    @State private var previewGeneration = 0
    @State private var isPreviewLoading = true
    @State private var mode = EditorMode.crop
    @State private var selectionEnabled = false
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var selectedSeam: String = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var confirmReset = false

    private enum EditorMode: String, CaseIterable {
        case crop = "裁剪", redact = "隐私遮挡", seam = "接缝"
    }

    init(session: CaptureSessionManifest) {
        self.session = session
        _edits = State(initialValue: session.edits)
        _selectedSeam = State(initialValue: session.strips.dropFirst().first?.id.uuidString ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("编辑工具", selection: $mode) {
                        ForEach(EditorMode.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("editor.mode")
                    Group {
                        switch mode {
                        case .crop: cropControls
                        case .redact: redactionControls
                        case .seam: seamControls
                        }
                    }
                    .font(.subheadline)
                }
                .padding(18)
                .background(.white)
                GeometryReader { geometry in
                    ScrollView {
                        if let sourcePreview {
                            let width = max(1, geometry.size.width - 32)
                            let height = width * sourcePreview.size.height / max(1, sourcePreview.size.width)
                            editorCanvas(sourcePreview, size: CGSize(width: width, height: height))
                                .padding(16)
                        } else {
                            ProgressView("正在准备编辑…").frame(width: geometry.size.width, height: 240)
                        }
                    }
                    .scrollDisabled(mode == .redact && selectionEnabled)
                }
                Text("修改只在点按“完成”后保存，原始画面会保留。")
                    .font(.caption2)
                    .foregroundStyle(ScrollTheme.secondary)
                    .padding(12)
            }
            .paperBackground()
            .navigationTitle("编辑长图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey(isBusy ? "保存中…" : "完成")) { save() }
                        .disabled(isBusy || sourcePreview == nil || isPreviewLoading)
                        .accessibilityIdentifier("editor.save")
                }
            }
            .task { await loadSourcePreview() }
            .onChange(of: mode) { _, _ in selectionEnabled = false; dragStart = nil; dragEnd = nil }
            .alert("无法完成编辑", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("知道了") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
            .confirmationDialog("重置裁剪和遮挡？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("重置裁剪和遮挡", role: .destructive) {
                    edits.crop = nil
                    edits.redactions = []
                }
            } message: { Text("接缝调整会改变画面位置。重新调整后，请再次检查并遮挡隐私。") }
        }
    }

    private var cropControls: some View {
        VStack(spacing: 12) {
            HStack {
                Label("保留范围", systemImage: "crop")
                Spacer()
                Button("还原") { edits.crop = nil }
                    .accessibilityIdentifier("editor.resetCrop")
            }
            HStack {
                Text("起点").frame(width: 35)
                Slider(value: Binding(get: { cropStart }, set: { setCrop(start: $0, end: cropEnd) }),
                       in: 0...max(0.01, cropEnd - 0.02), step: 0.001)
                    .accessibilityLabel("裁剪起点")
                    .accessibilityIdentifier("editor.cropStart")
                Text("\(Int(cropStart * 100))%").font(.caption.monospacedDigit()).frame(width: 40)
            }
            HStack {
                Text("终点").frame(width: 35)
                Slider(value: Binding(get: { cropEnd }, set: { setCrop(start: cropStart, end: $0) }),
                       in: min(0.99, cropStart + 0.02)...1, step: 0.001)
                    .accessibilityLabel("裁剪终点")
                    .accessibilityIdentifier("editor.cropEnd")
                Text("\(Int(cropEnd * 100))%").font(.caption.monospacedDigit()).frame(width: 40)
            }
            Text("灰色区域不会出现在导出的长图中。")
                .font(.caption)
                .foregroundStyle(ScrollTheme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var redactionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    selectionEnabled.toggle()
                } label: {
                    Label(LocalizedStringKey(selectionEnabled ? "完成圈选，继续滑动" : "圈选遮挡区域"), systemImage: selectionEnabled ? "checkmark" : "rectangle.dashed")
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.white)
                .disabled(isPreviewLoading)
                .accessibilityIdentifier("editor.selectRedaction")
                Spacer()
                Button("撤销") { if !edits.redactions.isEmpty { edits.redactions.removeLast() } }
                    .disabled(edits.redactions.isEmpty)
                    .accessibilityIdentifier("editor.undoRedaction")
            }
            Text(LocalizedStringKey(selectionEnabled ? "在图片上拖动圈选。完成后关闭圈选，才能继续上下滑动。" : "先滑到需要的位置，再点按圈选。黑色遮挡会永久写入导出的图片。"))
                .font(.caption)
                .foregroundStyle(ScrollTheme.secondary)
            Text(String(format: L10n.text("已遮挡 %lld 处 · 导出前请检查隐私"), Int64(edits.redactions.count)))
                .font(.caption.weight(.medium))
                .accessibilityIdentifier("editor.redactionCount")
        }
    }

    private var seamControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.strips.count < 2 {
                Text("这张图只有一个画面，无需调整接缝。")
                    .foregroundStyle(ScrollTheme.secondary)
            } else if edits.crop != nil || !edits.redactions.isEmpty {
                Text("已有裁剪或遮挡。调整接缝前需先重置，以免遮挡位置发生变化。")
                    .font(.caption)
                    .foregroundStyle(ScrollTheme.secondary)
                Button("重置后调整接缝") { confirmReset = true }
                    .buttonStyle(.bordered)
            } else {
                Picker("接缝位置", selection: $selectedSeam) {
                    ForEach(Array(session.strips.dropFirst().enumerated()), id: \.element.id) { index, strip in
                        Text(String(format: L10n.text("第 %lld 处接缝"), Int64(index + 1))).tag(strip.id.uuidString)
                    }
                }
                if let strip = session.strips.first(where: { $0.id.uuidString == selectedSeam }) {
                    HStack {
                        Text("去除重复行")
                        Spacer()
                        Text("\(edits.seamTrimPixels[selectedSeam] ?? 0) px")
                            .font(.caption.monospacedDigit())
                    }
                    Slider(value: Binding(
                        get: { Double(edits.seamTrimPixels[selectedSeam] ?? 0) },
                        set: {
                            edits.seamTrimPixels[selectedSeam] = Int($0)
                            previewGeneration += 1
                            isPreviewLoading = true
                            selectionEnabled = false
                            dragStart = nil; dragEnd = nil
                        }
                    ), in: 0...Double(max(1, min(strip.pixelHeight - 1, 300))), step: 1) { editing in
                        if !editing { Task { await loadSourcePreview() } }
                    }
                    .disabled(strip.pixelHeight <= 1)
                    .accessibilityLabel("接缝去除重复行数")
                    .accessibilityIdentifier("editor.seamTrim")
                }
                Text("去除接缝处重复的内容。滑动过快而遗漏的内容，需要重新捕捉。")
                    .font(.caption)
                    .foregroundStyle(ScrollTheme.secondary)
            }
        }
    }

    private func editorCanvas(_ image: UIImage, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
            if cropStart > 0 {
                Color.black.opacity(0.4).frame(width: size.width, height: size.height * cropStart)
            }
            if cropEnd < 1 {
                Color.black.opacity(0.4)
                    .frame(width: size.width, height: size.height * (1 - cropEnd))
                    .offset(y: size.height * cropEnd)
            }
            ForEach(Array(edits.redactions.enumerated()), id: \.offset) { _, rect in
                Color.black
                    .frame(width: size.width * rect.width, height: size.height * rect.height)
                    .offset(x: size.width * rect.x, y: size.height * rect.y)
            }
            if let selection = selectionRect(size: size) {
                Rectangle().fill(.black.opacity(0.8))
                    .overlay(Rectangle().stroke(ScrollTheme.teal, lineWidth: 2))
                    .frame(width: selection.width, height: selection.height)
                    .offset(x: selection.minX, y: selection.minY)
            }
            if isPreviewLoading {
                Color.white.opacity(0.65)
                ProgressView("正在更新画面…")
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
                    .offset(x: max(0, size.width / 2 - 85), y: 30)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard mode == .redact && selectionEnabled && !isPreviewLoading else { return }
                dragStart = value.startLocation
                dragEnd = value.location
            }
            .onEnded { _ in
                guard mode == .redact && selectionEnabled && !isPreviewLoading else { return }
                if let rect = selectionRect(size: size), rect.width >= 3, rect.height >= 3, edits.redactions.count < 500 {
                    edits.redactions.append(NormalizedRect(x: rect.minX / size.width, y: rect.minY / size.height,
                                                          width: rect.width / size.width, height: rect.height / size.height))
                }
                dragStart = nil; dragEnd = nil
            }, including: mode == .redact && selectionEnabled ? .all : .none)
        .accessibilityIdentifier("editor.canvas")
    }

    private var cropStart: Double { edits.crop?.y ?? 0 }
    private var cropEnd: Double { (edits.crop?.y ?? 0) + (edits.crop?.height ?? 1) }

    private func setCrop(start: Double, end: Double) {
        let clippedStart = max(0, min(start, end - 0.02))
        let clippedEnd = min(1, max(end, clippedStart + 0.02))
        edits.crop = NormalizedRect(x: 0, y: clippedStart, width: 1, height: clippedEnd - clippedStart)
    }

    private func selectionRect(size: CGSize) -> CGRect? {
        guard let start = dragStart, let end = dragEnd else { return nil }
        let left = max(0, min(size.width, min(start.x, end.x)))
        let right = max(0, min(size.width, max(start.x, end.x)))
        let top = max(0, min(size.height, min(start.y, end.y)))
        let bottom = max(0, min(size.height, max(start.y, end.y)))
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private func loadSourcePreview() async {
        previewGeneration += 1
        let generation = previewGeneration
        let trims = edits.seamTrimPixels
        isPreviewLoading = true
        selectionEnabled = false
        dragStart = nil; dragEnd = nil
        do {
            let image = try await library.preview(sessionID: session.id, maxDimension: 6000,
                                                  editsOverride: CaptureEditMetadata(seamTrimPixels: trims))
            guard generation == previewGeneration, trims == edits.seamTrimPixels else { return }
            sourcePreview = image
            isPreviewLoading = false
        } catch {
            guard generation == previewGeneration else { return }
            errorMessage = String(localized: "原始画面暂时无法读取，请稍后重试。")
        }
    }

    private func save() {
        guard let repository = library.repository, !isPreviewLoading else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try repository.saveEdits(edits, sessionID: session.id)
            library.refresh()
            dismiss()
        } catch { errorMessage = String(localized: "修改未保存，请检查剩余空间后重试。原始画面没有改变。") }
    }
}
