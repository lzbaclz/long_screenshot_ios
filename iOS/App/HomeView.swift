import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: CaptureLibrary
    @EnvironmentObject private var purchases: PurchaseStore
    @AppStorage("hasSeenCaptureGuide") private var hasSeenGuide = false
    @State private var showGuide = false
    @State private var showSettings = false
    @State private var showAll = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    captureCard
                    if let active = library.activeSession { activeCard(active) }
                    if !library.draftSessions.isEmpty { draftSection }
                    recentSection
                    privacyFooter
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .paperBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { sessionID in
                CaptureDetailView(sessionID: sessionID)
            }
            .sheet(isPresented: $showGuide) {
                CaptureGuideView {
                    hasSeenGuide = true
                    showGuide = false
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showAll) {
                NavigationStack {
                    CaptureListView()
                        .navigationDestination(for: UUID.self) { CaptureDetailView(sessionID: $0) }
                }
            }
            .alert("请稍后重试", isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )) {
                Button("知道了") { library.errorMessage = nil }
            } message: { Text(library.errorMessage ?? "") }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ScrollTheme.teal)
                    Text(L10n.appName).font(.title2.weight(.bold))
                    if library.isDemo { PillLabel(title: "示例", symbol: "play.rectangle") }
                }
                Text("把值得留下的，连成一张。")
                    .font(.subheadline)
                    .foregroundStyle(ScrollTheme.secondary)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
            }
            .accessibilityLabel("设置")
            .accessibilityIdentifier("home.settings")
        }
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                PillLabel(title: "自己滑动，自然成图", symbol: "hand.draw")
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.title2.weight(.light))
                    .foregroundStyle(ScrollTheme.teal)
            }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("滑到哪里\n就留到哪里")
                        .font(.system(size: 33, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .lineSpacing(5)
                    Text("聊天、文章、清单\n无需导入录屏视频")
                        .font(.subheadline)
                        .foregroundStyle(ScrollTheme.secondary)
                        .lineSpacing(5)
                }
                Spacer(minLength: 0)
                ScrollIllustration().frame(width: 106, height: 170).accessibilityHidden(true)
            }

            if library.isSimulator || library.isDemo {
                VStack(alignment: .leading, spacing: 9) {
                    Label(LocalizedStringKey(library.isDemo ? "正在浏览示例内容" : "在 iPhone 上开始捕捉"), systemImage: "iphone")
                        .font(.headline)
                    Text("模拟器不支持跨应用屏幕捕捉。连接真实 iPhone 后，可从系统按钮启动。")
                        .font(.caption)
                        .foregroundStyle(ScrollTheme.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("capture.simulatorNotice")
            } else if !hasSeenGuide {
                Button { showGuide = true } label: {
                    Label("开始长截图", systemImage: "record.circle")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("capture.startGuide")
            } else if let identifier = Bundle.main.object(forInfoDictionaryKey: "BroadcastExtensionIdentifier") as? String,
                      library.repository != nil {
                HStack(spacing: 12) {
                    BroadcastPicker(extensionIdentifier: identifier)
                        .frame(width: 60, height: 60)
                        .background(.white, in: Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        Text("点按左侧按钮开始").font(.headline)
                        Text("开始广播后，切到目标应用慢慢下滑")
                            .font(.caption)
                            .foregroundStyle(ScrollTheme.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 22))
            } else {
                Text("当前安装暂时无法启用屏幕捕捉，请重新安装完整版本。")
                    .font(.subheadline)
            }

            Button { showGuide = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "questionmark.circle")
                    Text("第一次使用？了解 3 个步骤")
                }
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("home.guide")
        }
        .padding(23)
        .background(
            LinearGradient(colors: [ScrollTheme.mint, Color(red: 0.91, green: 0.96, blue: 0.89)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 30)
        )
    }

    private func activeCard(_ session: CaptureSessionManifest) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(LocalizedStringKey(session.strips.isEmpty ? "准备捕捉，请切到目标应用" : "正在为你保留内容"), systemImage: "record.circle.fill")
                    .font(.headline)
                    .foregroundStyle(ScrollTheme.teal)
                Text("返回目标应用继续向下滑动。结束时点按系统捕捉指示，或在这里停止。")
                    .font(.subheadline)
                    .foregroundStyle(ScrollTheme.secondary)
                Button("停止并生成长图") { library.stopCapture() }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("capture.stop")
            }
        }
    }

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("可恢复的内容", systemImage: "arrow.clockwise.circle")
                    .font(.headline)
                Spacer()
                Text("\(library.draftSessions.count)").foregroundStyle(ScrollTheme.secondary)
            }
            Text("中途停止也没关系，已捕捉的部分还在。")
                .font(.caption)
                .foregroundStyle(ScrollTheme.secondary)
            ForEach(library.draftSessions.prefix(2)) { session in
                NavigationLink(value: session.id) { CaptureRow(session: session) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("capture.row.\(session.id.uuidString)")
            }
        }
        .accessibilityIdentifier("home.drafts")
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("最近的长图").font(.title3.weight(.bold))
                Spacer()
                Button { showAll = true } label: {
                    HStack(spacing: 4) { Text("全部"); Image(systemName: "arrow.up.right") }
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityIdentifier("home.allCaptures")
            }
            if library.completedSessions.isEmpty {
                PaperCard {
                    HStack(spacing: 15) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title)
                            .foregroundStyle(ScrollTheme.teal.opacity(0.7))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("第一张长图，从这里开始").font(.subheadline.weight(.semibold))
                            Text("完成捕捉后，会自动出现在这里。")
                                .font(.caption)
                                .foregroundStyle(ScrollTheme.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .accessibilityIdentifier("home.emptyState")
            } else {
                ForEach(library.completedSessions.prefix(3)) { session in
                    NavigationLink(value: session.id) { CaptureRow(session: session) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("capture.row.\(session.id.uuidString)")
                }
            }
        }
    }

    private var privacyFooter: some View {
        VStack(spacing: 8) {
            Label("内容只在你的设备上处理", systemImage: "lock.shield")
                .font(.caption.weight(.medium))
            Text("无账号 · 无广告 · 不上传屏幕内容")
                .font(.caption2)
        }
        .foregroundStyle(ScrollTheme.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }
}

struct CaptureRow: View {
    @EnvironmentObject private var library: CaptureLibrary
    let session: CaptureSessionManifest
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 15) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10).fill(ScrollTheme.mint.opacity(0.7))
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 67, alignment: .top)
                        .clipped()
                } else {
                    Image(systemName: "doc.text.image")
                        .font(.title2)
                        .foregroundStyle(ScrollTheme.teal)
                        .padding(.top, 19)
                }
            }
            .frame(width: 52, height: 67)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 7) {
                Text(session.displayTitle).font(.subheadline.weight(.semibold))
                Text("\(session.pixelWidth) × \(session.pixelHeight) · \(L10n.text(session.stateLabel))")
                    .font(.caption)
                    .foregroundStyle(ScrollTheme.secondary)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(ScrollTheme.secondary.opacity(0.6))
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .task(id: session.updatedAt) {
            thumbnail = try? await library.preview(sessionID: session.id, maxDimension: 500)
        }
    }
}

private struct ScrollIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 4) {
                Circle().fill(ScrollTheme.teal).frame(width: 20, height: 20)
                RoundedRectangle(cornerRadius: 3).fill(ScrollTheme.teal.opacity(0.2)).frame(width: 38, height: 6)
            }
            RoundedRectangle(cornerRadius: 8).fill(ScrollTheme.mint).frame(height: 32)
                .overlay(Image(systemName: "mountain.2.fill").foregroundStyle(ScrollTheme.teal.opacity(0.55)))
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(ScrollTheme.ink.opacity(index == 2 ? 0.18 : 0.08))
                    .frame(width: index == 4 ? 40 : nil, height: 5)
            }
            HStack(spacing: 5) {
                ForEach(0..<3) { _ in
                    RoundedRectangle(cornerRadius: 5).fill(ScrollTheme.mint).frame(height: 20)
                }
            }
        }
        .padding(13)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .rotationEffect(.degrees(6))
        .shadow(color: ScrollTheme.teal.opacity(0.13), radius: 13, x: 0, y: 9)
    }
}

struct CaptureListView: View {
    @EnvironmentObject private var library: CaptureLibrary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(library.sessions.filter { $0.status != .capturing }) { session in
                    NavigationLink(value: session.id) { CaptureRow(session: session) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("capture.row.\(session.id.uuidString)")
                }
                if library.sessions.isEmpty {
                    ContentUnavailableView("还没有长图", systemImage: "photo.stack", description: Text("完成一次捕捉后，长图会保存在这里。"))
                }
            }
            .padding(20)
        }
        .paperBackground()
        .navigationTitle("我的长图")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}
