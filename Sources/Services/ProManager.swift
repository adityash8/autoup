import Foundation
import StoreKit

class ProManager: ObservableObject {
    @Published var isProUser = false
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []

    private let productIDs = [
        "com.autoup.pro.monthly",
        "com.autoup.pro.yearly",
        "com.autoup.pro.family"
    ]

    private var updateListenerTask: Task<Void, Error>?

    init() {
        updateListenerTask = listenForTransactions()
        Task {
            await requestProducts()
            await updateCustomerProductStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    @MainActor
    func requestProducts() async {
        do {
            products = try await Product.products(for: productIDs)
        } catch {
            print("Failed to request products: \(error)")
        }
    }

    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateCustomerProductStatus()
            await transaction.finish()
            return transaction

        case .userCancelled, .pending:
            return nil

        default:
            return nil
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await updateCustomerProductStatus()
    }

    @MainActor
    private func updateCustomerProductStatus() async {
        var purchasedProducts: Set<String> = []

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                purchasedProducts.insert(transaction.productID)
            } catch {
                print("Transaction verification failed: \(error)")
            }
        }

        purchasedProductIDs = purchasedProducts
        isProUser = !purchasedProducts.isEmpty
    }

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.updateCustomerProductStatus()
                    await transaction.finish()
                } catch {
                    print("Transaction failed verification: \(error)")
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

enum StoreError: Error {
    case failedVerification
}

// MARK: - Pro Features

extension ProManager {
    var hasMultiMacSync: Bool {
        return isProUser
    }

    var hasVersionPinning: Bool {
        return isProUser
    }

    var hasRollbackFeature: Bool {
        return isProUser
    }

    var hasFamilySharing: Bool {
        return purchasedProductIDs.contains("com.autoup.pro.family")
    }

    var hasPrioritySupport: Bool {
        return isProUser
    }
}

// MARK: - Version Pinning Service

class VersionPinningService: ObservableObject {
    @Published var pinnedVersions: [String: String] = [:]
    @Published var ignoredApps: Set<String> = []

    private let proManager: ProManager
    private let databaseManager: DatabaseManager

    init(proManager: ProManager, databaseManager: DatabaseManager) {
        self.proManager = proManager
        self.databaseManager = databaseManager
        loadPinnedVersions()
    }

    func pinVersion(bundleID: String, version: String) {
        guard proManager.hasVersionPinning else { return }

        pinnedVersions[bundleID] = version
        savePinnedVersions()
    }

    func unpinVersion(bundleID: String) {
        pinnedVersions.removeValue(forKey: bundleID)
        savePinnedVersions()
    }

    func ignoreApp(bundleID: String) {
        ignoredApps.insert(bundleID)
        saveIgnoredApps()
    }

    func unignoreApp(bundleID: String) {
        ignoredApps.remove(bundleID)
        saveIgnoredApps()
    }

    func shouldIgnoreUpdate(for app: AppInfo, toVersion: String) -> Bool {
        // Check if app is completely ignored
        if ignoredApps.contains(app.bundleID) {
            return true
        }

        // Check if version is pinned
        if let pinnedVersion = pinnedVersions[app.bundleID] {
            return app.version == pinnedVersion
        }

        return false
    }

    private func loadPinnedVersions() {
        if let data = databaseManager.loadSetting(key: "pinnedVersions"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data.data(using: .utf8)!) {
            pinnedVersions = decoded
        }

        if let data = databaseManager.loadSetting(key: "ignoredApps"),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data.data(using: .utf8)!) {
            ignoredApps = decoded
        }
    }

    private func savePinnedVersions() {
        if let encoded = try? JSONEncoder().encode(pinnedVersions),
           let jsonString = String(data: encoded, encoding: .utf8) {
            databaseManager.saveSetting(key: "pinnedVersions", value: jsonString)
        }
    }

    private func saveIgnoredApps() {
        if let encoded = try? JSONEncoder().encode(ignoredApps),
           let jsonString = String(data: encoded, encoding: .utf8) {
            databaseManager.saveSetting(key: "ignoredApps", value: jsonString)
        }
    }
}

// MARK: - Multi-Mac Sync Service

class MultiMacSyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?

    private let proManager: ProManager
    private let databaseManager: DatabaseManager

    init(proManager: ProManager, databaseManager: DatabaseManager) {
        self.proManager = proManager
        self.databaseManager = databaseManager
    }

    func syncSettings() async {
        guard proManager.hasMultiMacSync else { return }

        await MainActor.run {
            isSyncing = true
        }

        do {
            // Upload local settings to iCloud
            await uploadSettingsToiCloud()

            // Download and merge settings from other devices
            await downloadSettingsFromiCloud()

            await MainActor.run {
                lastSyncDate = Date()
                isSyncing = false
            }

        } catch {
            print("Sync failed: \(error)")
            await MainActor.run {
                isSyncing = false
            }
        }
    }

    private func uploadSettingsToiCloud() async {
        // Implementation would use CloudKit or iCloud Drive
        // For now, this is a placeholder
        print("Uploading settings to iCloud...")
    }

    private func downloadSettingsFromiCloud() async {
        // Implementation would use CloudKit or iCloud Drive
        // For now, this is a placeholder
        print("Downloading settings from iCloud...")
    }
}

// MARK: - Health Score Calculator

class HealthScoreCalculator {
    private let tahoeChecker = TahoeCompatibilityChecker()

    func calculateHealthScore(for app: AppInfo, availableUpdate: UpdateInfo?) -> HealthScore {
        // Check Tahoe compatibility first
        let tahoeStatus = tahoeChecker.checkCompatibility(for: app)
        if case .incompatible = tahoeStatus {
            return .tahoeIncompatible
        }

        // Check for available updates
        guard let update = availableUpdate else {
            return .current
        }

        // Prioritize security updates
        if update.isSecurityUpdate {
            return .securityUpdate
        }

        // Regular update available
        return .updateAvailable
    }

    func calculateOverallHealthScore(apps: [AppInfo], updates: [UpdateInfo]) -> OverallHealthScore {
        let updatesByBundleID = Dictionary(grouping: updates, by: { $0.appInfo.bundleID })

        var scores: [HealthScore] = []

        for app in apps {
            let availableUpdate = updatesByBundleID[app.bundleID]?.first
            let score = calculateHealthScore(for: app, availableUpdate: availableUpdate)
            scores.append(score)
        }

        let totalApps = apps.count
        let currentApps = scores.filter { $0 == .current }.count
        let updatesAvailable = scores.filter { $0 == .updateAvailable }.count
        let securityUpdates = scores.filter { $0 == .securityUpdate }.count
        let tahoeIncompatible = scores.filter { $0 == .tahoeIncompatible }.count

        let healthyPercentage = totalApps > 0 ? (currentApps * 100) / totalApps : 100

        return OverallHealthScore(
            totalApps: totalApps,
            currentApps: currentApps,
            updatesAvailable: updatesAvailable,
            securityUpdates: securityUpdates,
            tahoeIncompatible: tahoeIncompatible,
            healthyPercentage: healthyPercentage
        )
    }
}

struct OverallHealthScore {
    let totalApps: Int
    let currentApps: Int
    let updatesAvailable: Int
    let securityUpdates: Int
    let tahoeIncompatible: Int
    let healthyPercentage: Int

    var description: String {
        if securityUpdates > 0 {
            return "\(securityUpdates) security update\(securityUpdates == 1 ? "" : "s") needed"
        } else if updatesAvailable > 0 {
            return "\(updatesAvailable) update\(updatesAvailable == 1 ? "" : "s") available"
        } else if tahoeIncompatible > 0 {
            return "\(tahoeIncompatible) app\(tahoeIncompatible == 1 ? "" : "s") incompatible with Tahoe"
        } else {
            return "All apps up to date"
        }
    }

    var color: String {
        if securityUpdates > 0 {
            return "red"
        } else if updatesAvailable > 0 {
            return "yellow"
        } else if tahoeIncompatible > 0 {
            return "purple"
        } else {
            return "green"
        }
    }
}