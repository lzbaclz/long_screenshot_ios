import SwiftUI

struct CaptureGuideView: View {
    @EnvironmentObject private var library: CaptureLibrary
    let completion: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(ScrollTheme.teal)
                        .frame(width: 82, height: 82)
                        .background(ScrollTheme.mint, in: RoundedRectangle(cornerRadius: 25))
                    Text("像平时一样滑动\n剩下的交给续页")
                        .font(.system(size: 29, weight: .bold))
                    step("01", title: "打开系统捕捉", detail: "回到首页，点按圆形捕捉按钮，在系统面板选择续页并点按“开始广播”。系统会倒计时并显示捕捉指示。", symbol: "record.circle")
                    step("02", title: "切到目标应用，慢慢向下滑", detail: "先让希望保留的起点画面稳定，再从这里开始缓慢向下滑动。保持竖屏，让前后画面有重叠；等图片加载完成后再继续。", symbol: "hand.draw")
                    step("03", title: "停止，长图就绪", detail: "点按屏幕顶部的系统捕捉指示结束，或返回续页点按停止。回到应用后即可裁剪、遮挡隐私和保存。", symbol: "checkmark.rectangle.stack")
                    PaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("开始前，留意这两件事", systemImage: "lightbulb")
                                .font(.subheadline.weight(.semibold))
                            Text("开启专注模式，减少通知进入画面。只捕捉你愿意保留的内容；整个捕捉过程都会有系统提示。")
                            Text("首页和控制中心中的入口使用同一种系统能力。音频不会被保存，也无需导入视频。")
                        }
                        .font(.subheadline)
                        .foregroundStyle(ScrollTheme.secondary)
                    }
                    if library.isSimulator {
                        Label("模拟器仅支持查看示例和编辑，真实捕捉需要 iPhone。", systemImage: "iphone")
                            .font(.caption)
                            .foregroundStyle(ScrollTheme.secondary)
                    }
                    Button("我知道了") { completion() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("guide.done")
                }
                .padding(24)
            }
            .paperBackground()
            .navigationTitle("使用指南")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: completion) } }
        }
    }

    private func step(_ number: String, title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(ScrollTheme.teal)
                .frame(width: 39, height: 39)
                .background(ScrollTheme.mint.opacity(0.7), in: Circle())
            VStack(alignment: .leading, spacing: 9) {
                Label(LocalizedStringKey(title), systemImage: symbol).font(.headline)
                Text(LocalizedStringKey(detail))
                    .font(.subheadline)
                    .foregroundStyle(ScrollTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
        }
    }
}
