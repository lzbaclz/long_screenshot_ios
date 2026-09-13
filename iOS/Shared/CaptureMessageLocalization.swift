import Foundation

/// Localize only at presentation boundaries; persisted reasons remain stable canonical keys.
public enum CaptureMessageLocalization {
    public static func text(_ canonicalReason: String, bundle: Bundle = .main) -> String {
        let formats = [
            ("已达到设置的 ", " 屏上限。", "已达到设置的 %lld 屏上限。"),
            ("停止滑动 ", " 秒，已完成捕捉。", "停止滑动 %lld 秒，已完成捕捉。")
        ]
        for (prefix, suffix, key) in formats
        where canonicalReason.hasPrefix(prefix) && canonicalReason.hasSuffix(suffix) {
            if let count = Int64(canonicalReason.dropFirst(prefix.count).dropLast(suffix.count)) {
                let format = bundle.localizedString(forKey: key, value: key, table: nil)
                return String(format: format, locale: Locale.current, count)
            }
        }
        return bundle.localizedString(forKey: canonicalReason, value: canonicalReason, table: nil)
    }
}
