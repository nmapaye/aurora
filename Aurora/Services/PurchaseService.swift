import Foundation
import Observation
import StoreKit

/// Aurora Plus, a one-time purchase (non-consumable) through the App Store.
/// The App Store's own entitlement list decides whether Plus is unlocked; the
/// cached flag only avoids a locked flash at launch and is corrected by
/// `refresh()` as soon as the entitlements load, including after a refund.
@MainActor
@Observable
final class PurchaseService {
    static let plusProductID = "com.nmapaye.aurora.plus"

    enum ProductState: Equatable {
        case loading
        /// The App Store couldn't be reached or the product isn't set up.
        case unavailable
        case loaded
    }

    enum Notice: Equatable {
        case pending
        case unverified
        case failed
        case restoreFailed
        case nothingToRestore
    }

    private(set) var isUnlocked: Bool
    private(set) var product: Product?
    private(set) var productState: ProductState = .loading
    private(set) var isWorking = false
    private(set) var notice: Notice?

    private let defaults: UserDefaults
    private let forced: Bool?
    private var updates: Task<Void, Never>?
    private static let cacheKey = "plus.unlocked"

    #if DEBUG
    /// UI tests and previews can start locked or unlocked without StoreKit.
    static let launchOverride: Bool? = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-AuroraPlusUnlocked") { return true }
        if args.contains("-AuroraPlusLocked") { return false }
        return nil
    }()
    #else
    static let launchOverride: Bool? = nil
    #endif

    init(defaults: UserDefaults = .standard, forced: Bool? = PurchaseService.launchOverride) {
        self.defaults = defaults
        self.forced = forced
        self.isUnlocked = forced ?? defaults.bool(forKey: Self.cacheKey)
    }

    /// Loads the product, checks entitlements and listens for purchases made
    /// elsewhere (Ask to Buy approvals, another device, refunds).
    func start() async {
        guard forced == nil else {
            productState = .unavailable
            return
        }
        if updates == nil {
            updates = Task { [weak self] in
                for await update in Transaction.updates {
                    if case .verified(let transaction) = update {
                        await transaction.finish()
                    }
                    await self?.refresh()
                }
            }
        }
        await refresh()
        await loadProduct()
    }

    func loadProduct() async {
        productState = .loading
        do {
            let products = try await Product.products(for: [Self.plusProductID])
            product = products.first
            productState = product == nil ? .unavailable : .loaded
        } catch {
            productState = .unavailable
        }
    }

    func refresh() async {
        guard forced == nil else { return }
        var unlocked = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.plusProductID,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }
        setUnlocked(unlocked)
    }

    func purchase() async {
        guard let product, !isWorking else { return }
        isWorking = true
        notice = nil
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    setUnlocked(transaction.revocationDate == nil)
                case .unverified:
                    notice = .unverified
                }
            case .pending:
                notice = .pending
            case .userCancelled:
                break
            @unknown default:
                notice = .failed
            }
        } catch {
            notice = .failed
        }
    }

    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        notice = nil
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refresh()
            if !isUnlocked { notice = .nothingToRestore }
        } catch {
            notice = .restoreFailed
        }
    }

    private func setUnlocked(_ value: Bool) {
        isUnlocked = value
        defaults.set(value, forKey: Self.cacheKey)
    }
}

extension PurchaseService.Notice {
    var text: String {
        switch self {
        case .pending: "The purchase is waiting for approval. Plus unlocks as soon as it’s approved."
        case .unverified: "The App Store couldn’t verify this purchase. Try Restore Purchase."
        case .failed: "The purchase didn’t go through. You weren’t charged. Try again."
        case .restoreFailed: "Couldn’t reach the App Store. Check your connection and try again."
        case .nothingToRestore: "No Aurora Plus purchase was found for this Apple Account."
        }
    }

    var isError: Bool { self != .pending }
}
