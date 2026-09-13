import SwiftUI

@main
struct FixtureReaderApp: App {
    var body: some Scene {
        WindowGroup { FixtureReaderView() }
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
