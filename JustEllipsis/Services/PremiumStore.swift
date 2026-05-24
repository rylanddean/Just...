import Foundation
import StoreKit

enum PremiumFeature: CaseIterable {
    case unlimitedBrain
    case brainSearch
    case brainExport
    case readerThemes
    case homeWidget
}

@Observable
@MainActor
final class PremiumStore {

    static let shared = PremiumStore()

    private let productID = "com.rylandean.justellipsis.premium"

    var isPremium: Bool = false
    var isLoading: Bool = false
    var purchaseError: Error?

    private init() {}

    // MARK: - Check Entitlement

    func refreshStatus() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == productID {
                isPremium = true
                return
            }
        }
        isPremium = false
    }

    // MARK: - Purchase

    func purchase() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            guard let product = try await Product.products(for: [productID]).first else { return }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    isPremium = true
                    await tx.finish()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error
        }
    }

    // MARK: - Restore

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshStatus()
        } catch {
            purchaseError = error
        }
    }
}
