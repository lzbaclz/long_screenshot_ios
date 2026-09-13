import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: CaptureLibrary
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivacy = false
    @State private var showUpgrade = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("停止方式", selection: Binding(
                        get: { Int(library.configuration.idleStopSeconds ?? 0) },
                        set: { library.configuration.idleStopSeconds = $0 == 0 ? nil : Double($0); library.saveSettings() }
                    )) {
                        Text("手动停止").tag(0)
                        Text("静止 5 秒").tag(5)
                        Text("静止 10 秒").tag(10)
                    }
                    .accessibilityIdentifier("settings.idleStop")
                    Picker("最多捕捉", selection: Binding(
                        get: { library.configuration.maximumScreenCount },
                        set: { library.configuration.maximumScreenCount = $0; library.saveSettings() }
                    )) {
                        Text("5 屏").tag(5)
                        Text("10 屏").tag(10)
                        Text("20 屏").tag(20)
                    }
                    .accessibilityIdentifier("settings.maxScreens")
                } header: { Text("捕捉习惯") } footer: {
                    Text("新设置从下一次捕捉生效。静止自动停止可能在等待加载时提前结束，首次使用建议手动停止。单次捕捉最长 2 分钟。")
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("忽略顶部"); Spacer(); Text("\(Int(library.configuration.captureTopInsetFraction * 100))%") }
                        Slider(value: Binding(
                            get: { library.configuration.captureTopInsetFraction },
                            set: { library.configuration.captureTopInsetFraction = $0 }
                        ), in: 0...0.25, step: 0.01) { editing in if !editing { library.saveSettings() } }
                            .accessibilityLabel("忽略顶部百分比")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("忽略底部"); Spacer(); Text("\(Int(library.configuration.captureBottomInsetFraction * 100))%") }
                        Slider(value: Binding(
                            get: { library.configuration.captureBottomInsetFraction },
                            set: { library.configuration.captureBottomInsetFraction = $0 }
                        ), in: 0...0.25, step: 0.01) { editing in if !editing { library.saveSettings() } }
                            .accessibilityLabel("忽略底部百分比")
                    }
                } header: { Text("固定栏调整") } footer: {
                    Text("顶部和底部均为 0% 时，会在首次可衔接的滚动中尝试识别固定栏。任一区域设为非零后，使用手动范围。无法安全识别时会停止，请调整范围后重试；忽略的内容不会被保存。")
                }

                Section {
                    HStack {
                        Label("本周导出", systemImage: "square.and.arrow.up")
                        Spacer()
                        Group {
                            if purchases.unlimited { Text("不限次数") }
                            else { Text(String(format: L10n.text("剩余 %lld / 3"), Int64(purchases.remainingExports))) }
                        }.foregroundStyle(ScrollTheme.secondary)
                    }
                    if purchases.testingUnlimited {
                        Label("测试版本已开放无限导出", systemImage: "testtube.2")
                            .font(.subheadline)
                            .foregroundStyle(ScrollTheme.secondary)
                    }
                    Button { showUpgrade = true } label: {
                        Label(LocalizedStringKey(purchases.hasPro ? "管理已解锁功能" : "了解无限导出"), systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("settings.upgrade")
                } header: { Text("导出") } footer: {
                    Text("免费版每周可导出 3 次新捕捉。同一张长图重复保存或分享只计一次，取消或失败不计次数。")
                }

                Section {
                    Button { showPrivacy = true } label: { Label("隐私与数据", systemImage: "lock.shield") }
                        .accessibilityIdentifier("settings.privacy")
                    Link(destination: URL(string: "mailto:chestnutlee23@163.com")!) {
                        Label("联系支持", systemImage: "envelope")
                    }
                    .accessibilityIdentifier("settings.support")
                    HStack { Text("应用"); Spacer(); Text(L10n.appName).foregroundStyle(ScrollTheme.secondary) }
                    HStack { Text("版本"); Spacer(); Text(version).foregroundStyle(ScrollTheme.secondary) }
                }
            }
            .scrollContentBackground(.hidden)
            .paperBackground()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showPrivacy) { PrivacyView() }
            .sheet(isPresented: $showUpgrade) { UpgradeView() }
        }
    }

    private var version: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        return String(localized: "\(value) · 内测版")
    }
}

struct UpgradeView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(ScrollTheme.teal)
                        .padding(.top, 20)
                    Text("好内容，尽管留下")
                        .font(.largeTitle.bold())
                    Text("解锁无限导出，不再受每周次数限制。截图内容始终在本机处理。")
                        .font(.body)
                        .foregroundStyle(ScrollTheme.secondary)
                    PaperCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("无限次保存和分享", systemImage: "infinity")
                            Label("PNG 与 JPEG 格式", systemImage: "photo")
                            Label("无需账号，没有广告", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .font(.headline)
                    }
                    if purchases.hasPro {
                        Label("已解锁无限导出", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(ScrollTheme.teal)
                            .font(.headline)
                    } else if let product = purchases.product {
                        VStack(alignment: .leading, spacing: 9) {
                            Button {
                                Task { await purchases.purchase() }
                            } label: {
                                if purchases.isBusy { Text("请稍候…") }
                                else { Text(String(format: L10n.text("解锁 · %@"), product.displayPrice)) }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(purchases.isBusy)
                            Text(product.description)
                                .font(.caption)
                                .foregroundStyle(ScrollTheme.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("购买暂未开放").font(.headline)
                            Text("目前没有可购买的产品。你可以继续使用免费功能，稍后再来查看。")
                                .font(.subheadline)
                                .foregroundStyle(ScrollTheme.secondary)
                            Button("重新加载") { Task { await purchases.loadProduct() } }
                                .buttonStyle(.bordered)
                        }
                        .accessibilityIdentifier("purchase.unavailable")
                    }
                    if purchases.testingUnlimited {
                        Text("你正在使用测试版本，导出次数不受限制。")
                            .font(.caption)
                            .foregroundStyle(ScrollTheme.secondary)
                    }
                    Button("恢复购买") { Task { await purchases.restore() } }
                        .disabled(purchases.isBusy)
                        .accessibilityIdentifier("purchase.restore")
                    Text("免费版每周 3 次新捕捉导出；同一捕捉的重复导出不重复计数。裁剪、遮挡、查看和捕捉始终可以使用。")
                        .font(.caption)
                        .foregroundStyle(ScrollTheme.secondary)
                }
                .padding(25)
            }
            .paperBackground()
            .navigationTitle("无限导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .alert("购买状态", isPresented: Binding(
                get: { purchases.message != nil },
                set: { if !$0 { purchases.message = nil } }
            )) { Button("知道了") { purchases.message = nil } } message: { Text(purchases.message ?? "") }
        }
    }
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("只在你的设备上处理", systemImage: "lock.shield.fill")
                        .font(.title2.bold())
                        .foregroundStyle(ScrollTheme.teal)
                    paragraph("屏幕内容", "捕捉过程中，系统会持续显示捕捉提示。续页处理屏幕画面以拼接长图，不录制或保存音频，也不保存完整视频文件。切换到的应用和弹出的通知可能进入画面，请在开始前确认。")
                    paragraph("本机保存", "截图和可恢复草稿保存在本机，不上传至我们的服务器，也不用于广告。捕捉文件不参与应用数据备份；卸载应用会移除应用内保存的内容。你主动保存到照片或分享到其他应用后，对应服务可能自行同步。")
                    paragraph("编辑与删除", "隐私遮挡会以不透明色块写入导出的图片。为了能重新编辑，应用内仍保留原始画面；如需移除原始内容，请在导出后删除对应截图。删除应用内截图不会删除你已经导出的副本。")
                    paragraph("照片权限", "只有主动保存时，才请求向照片图库添加图片的权限。无需读取你的照片图库，也无需提供麦克风权限。")
                    paragraph("购买", "购买与恢复购买由 Apple 处理。续页只验证购买状态，不收集付款资料。每周导出计数保存在本机。")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("联系我们").font(.headline)
                        Link("chestnutlee23@163.com", destination: URL(string: "mailto:chestnutlee23@163.com")!)
                            .font(.subheadline)
                    }
                }
                .padding(24)
            }
            .paperBackground()
            .navigationTitle("隐私与数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func paragraph(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title)).font(.headline)
            Text(LocalizedStringKey(body)).font(.subheadline).foregroundStyle(ScrollTheme.secondary).lineSpacing(5)
        }
    }
}
