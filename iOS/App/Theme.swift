import SwiftUI

enum L10n {
    static var appName: String { text("续页") }
    static func text(_ key: String) -> String { NSLocalizedString(key, comment: "") }

    static func captureReason(_ reason: String) -> String {
        let formats = [
            ("已达到设置的 ", " 屏上限。", "已达到设置的 %lld 屏上限。"),
            ("停止滑动 ", " 秒，已完成捕捉。", "停止滑动 %lld 秒，已完成捕捉。")
        ]
        for (prefix, suffix, key) in formats where reason.hasPrefix(prefix) && reason.hasSuffix(suffix) {
            if let count = Int64(reason.dropFirst(prefix.count).dropLast(suffix.count)) {
                return String(format: text(key), count)
            }
        }
        return text(reason)
    }
}

enum ScrollTheme {
    static let ink = Color(red: 0.13, green: 0.21, blue: 0.24)
    static let teal = Color(red: 0.02, green: 0.47, blue: 0.43)
    static let mint = Color(red: 0.84, green: 0.94, blue: 0.88)
    static let paper = Color(red: 0.97, green: 0.97, blue: 0.94)
    static let secondary = Color(red: 0.36, green: 0.43, blue: 0.43)
}

struct PaperCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(ScrollTheme.ink.opacity(0.06)))
    }
}

struct PillLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(LocalizedStringKey(title), systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(ScrollTheme.teal)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(ScrollTheme.mint.opacity(0.65), in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(.white)
            .background(ScrollTheme.teal.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 18))
    }
}

extension View {
    func paperBackground() -> some View {
        background(ScrollTheme.paper.ignoresSafeArea())
            .tint(ScrollTheme.teal)
            .foregroundStyle(ScrollTheme.ink)
    }
}
