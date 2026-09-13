import Foundation
import StoreKit
import Combine

/// Quotas apply to successfully exported captures, never previews or cancelled shares.
@MainActor
final class PurchaseStore: ObservableObject {
    @Published private(set) var product: Product?
    @Published private(set) var hasPro = false
    @Published private(set) var testingUnlimited = false
    @Published private(set) var isBusy = false
    @Published var message: String?
    @Published private var exports: [String: Date]

    private let defaults: UserDefaults
    private let productID: String?
    private var updatesTask: Task<Void, Never>?
    private let quotaKey = "successfulCaptureExports.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        productID = Bundle.main.object(forInfoDictionaryKey: "ProProductIdentifier") as? String
        exports = (defaults.dictionary(forKey: quotaKey) ?? [:]).compactMapValues { $0 as? Date }
        #if DEBUG
        testingUnlimited = true
        #endif
    }

    deinit { updatesTask?.cancel() }

    var unlimited: Bool { hasPro || testingUnlimited }

    var remainingExports: Int {
        let calendar = Calendar(identifier: .iso8601)
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        let used = exports.values.filter { interval.contains($0) }.count
        return max(0, 3 - used)
    }

    func canExport(sessionID: UUID) -> Bool {
        unlimited || exports[sessionID.uuidString] != nil || remainingExports > 0
    }

    func recordSuccessfulExport(sessionID: UUID) {
        guard exports[sessionID.uuidString] == nil else { return }
        exports[sessionID.uuidString] = Date()
        defaults.set(exports, forKey: quotaKey)
    }

    func start() async {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result, transaction.productID == self.productID {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
        #if !DEBUG
        if let result = try? await AppTransaction.shared,
           case .verified(let transaction) = result,
           transaction.environment == .sandbox {
            testingUnlimited = true
        }
        #endif
        await refreshEntitlements()
        await loadProduct()
    }

    func loadProduct() async {
        guard let productID, !productID.isEmpty else { return }
        do {
            product = try await Product.products(for: [productID]).first { $0.type == .nonConsumable }
        } catch {
            product = nil
        }
    }

    func purchase() async {
        guard let product, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                guard transaction.productID == productID, transaction.productType == .nonConsumable else {
                    message = String(localized: "这笔购买暂时无法确认，请稍后恢复购买。")
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                message = hasPro ? String(localized: "已解锁无限导出，谢谢支持续页。") : String(localized: "购买状态正在更新，请稍后恢复购买。")
            case .success(.unverified):
                message = String(localized: "暂时无法验证购买，请稍后重试。")
            case .pending:
                message = String(localized: "购买正在等待确认，确认后会自动解锁。")
            case .userCancelled:
                break
            @unknown default:
                message = String(localized: "购买尚未完成，请稍后重试。")
            }
        } catch {
            message = String(localized: "购买未完成，请检查网络后重试。")
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = hasPro ? String(localized: "已恢复无限导出。") : String(localized: "当前 Apple 账户下没有可恢复的购买。")
        } catch {
            message = String(localized: "暂时无法恢复购买，请稍后重试。")
        }
    }

    private func refreshEntitlements() async {
        var verified = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == productID,
               transaction.productType == .nonConsumable,
               transaction.revocationDate == nil,
               !transaction.isUpgraded {
                verified = true
            }
        }
        hasPro = verified
    }
}
