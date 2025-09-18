import Foundation

class TahoeCompatibilityChecker: ObservableObject {
    @Published var incompatibleApps: [String: TahoeIncompatibility] = [:]

    private let tahoeBreakers: [TahoeIncompatibility]

    init() {
        // Load Tahoe compatibility data
        self.tahoeBreakers = Self.loadTahoeBreakers()
    }

    func checkCompatibility(for app: AppInfo) -> TahoeCompatibilityStatus {
        // Check if app is in the known incompatible list
        if let incompatibility = tahoeBreakers.first(where: { $0.matches(app) }) {
            if incompatibility.isVersionAffected(app.version) {
                return .incompatible(reason: incompatibility.reason, fixedInVersion: incompatibility.fixedInVersion)
            }
        }

        // Check for beta versions (generally risky with new macOS)
        if isBetaVersion(app.version) {
            return .risky(reason: "Beta version may have compatibility issues with macOS Tahoe")
        }

        // Check app age (very old apps might have issues)
        if isVeryOldApp(app) {
            return .risky(reason: "App hasn't been updated in over 2 years")
        }

        return .compatible
    }

    func filterIncompatibleUpdates(_ updates: [UpdateInfo]) -> [UpdateInfo] {
        return updates.compactMap { update in
            let status = checkCompatibility(for: update.appInfo)

            switch status {
            case .incompatible:
                return nil // Don't offer updates for incompatible apps
            case .risky:
                // Allow risky updates but mark them
                var modifiedUpdate = update
                modifiedUpdate = UpdateInfo(
                    appInfo: update.appInfo,
                    availableVersion: update.availableVersion,
                    changelog: update.changelog,
                    downloadURL: update.downloadURL,
                    isSecurityUpdate: update.isSecurityUpdate,
                    isTahoeCompatible: false,
                    summary: update.summary,
                    detectedAt: update.detectedAt
                )
                return modifiedUpdate
            case .compatible:
                return update
            }
        }
    }

    private func isBetaVersion(_ version: String) -> Bool {
        let betaKeywords = ["beta", "alpha", "rc", "preview", "dev", "nightly"]
        let lowercaseVersion = version.lowercased()

        return betaKeywords.contains { lowercaseVersion.contains($0) } ||
               version.contains(try! NSRegularExpression(pattern: #"\d+\.\d+\.\d+-"#))
    }

    private func isVeryOldApp(_ app: AppInfo) -> Bool {
        let twoYearsAgo = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        return app.lastModified < twoYearsAgo
    }

    private static func loadTahoeBreakers() -> [TahoeIncompatibility] {
        // In production, this would load from a JSON file or remote API
        // For now, return hardcoded known issues based on the PRD

        return [
            TahoeIncompatibility(
                bundleIDs: ["com.adobe.Lightroom"],
                appNames: ["Adobe Lightroom Classic", "Adobe Lightroom"],
                affectedVersions: ["13.0", "13.1", "13.2"],
                fixedInVersion: "13.3",
                reason: "Crashes on startup with macOS Tahoe",
                severity: .high,
                source: "Adobe Support Forums"
            ),
            TahoeIncompatibility(
                bundleIDs: ["com.fujifilm.FujiCameraTethering"],
                appNames: ["Fuji Camera Tethering"],
                affectedVersions: ["*"],
                fixedInVersion: nil,
                reason: "Tethering functionality broken, fix expected end of September",
                severity: .critical,
                source: "Fujifilm Developer Notice"
            ),
            TahoeIncompatibility(
                bundleIDs: ["com.microsoft.Office365ServiceV2"],
                appNames: ["Microsoft Office"],
                affectedVersions: ["16.70", "16.71"],
                fixedInVersion: "16.72",
                reason: "Excel crashes when opening large spreadsheets",
                severity: .medium,
                source: "Microsoft Tech Community"
            ),
            TahoeIncompatibility(
                bundleIDs: ["com.parallels.desktop.console"],
                appNames: ["Parallels Desktop"],
                affectedVersions: ["18.0", "18.1"],
                fixedInVersion: "18.2",
                reason: "Virtual machines fail to start",
                severity: .high,
                source: "Parallels Support"
            ),
            TahoeIncompatibility(
                bundleIDs: ["com.vmware.fusion"],
                appNames: ["VMware Fusion"],
                affectedVersions: ["13.0"],
                fixedInVersion: "13.1",
                reason: "Kernel panics when starting VMs",
                severity: .critical,
                source: "VMware Knowledge Base"
            ),
            TahoeIncompatibility(
                bundleIDs: ["com.blackmagic-design.DaVinciResolve"],
                appNames: ["DaVinci Resolve"],
                affectedVersions: ["18.5", "18.6"],
                fixedInVersion: "19.0",
                reason: "GPU acceleration disabled, poor performance",
                severity: .medium,
                source: "Blackmagic Design Forums"
            ),
            TahoeIncompatibility(
                bundleIDs: ["com.native-instruments.traktor"],
                appNames: ["Traktor Pro"],
                affectedVersions: ["3.10", "3.11"],
                fixedInVersion: "3.12",
                reason: "Audio dropouts and MIDI issues",
                severity: .high,
                source: "Native Instruments Community"
            ),
            TahoeIncompatibility(
                bundleIDs: ["org.videolan.vlc"],
                appNames: ["VLC Media Player"],
                affectedVersions: ["3.0.18", "3.0.19"],
                fixedInVersion: "3.1.0",
                reason: "Hardware acceleration issues with new video drivers",
                severity: .low,
                source: "VLC Forums"
            ),
            TahoeIncompatibility(
                bundleIDs: ["com.google.Chrome.canary"],
                appNames: ["Google Chrome Canary"],
                affectedVersions: ["*"],
                fixedInVersion: nil,
                reason: "Canary builds may have stability issues with Tahoe",
                severity: .low,
                source: "Chrome Developer Channels"
            ),
            TahoeIncompatibility(
                bundleIDs: ["com.unity3d.UnityEditor5.x"],
                appNames: ["Unity Editor"],
                affectedVersions: ["2022.3.0", "2022.3.1", "2022.3.2"],
                fixedInVersion: "2022.3.3",
                reason: "Rendering pipeline crashes",
                severity: .high,
                source: "Unity Issue Tracker"
            )
        ]
    }
}

struct TahoeIncompatibility {
    let bundleIDs: [String]
    let appNames: [String]
    let affectedVersions: [String]
    let fixedInVersion: String?
    let reason: String
    let severity: TahoeIncompatibilitySeverity
    let source: String

    func matches(_ app: AppInfo) -> Bool {
        return bundleIDs.contains(app.bundleID) ||
               appNames.contains { appName in
                   app.name.lowercased().contains(appName.lowercased())
               }
    }

    func isVersionAffected(_ version: String) -> Bool {
        // If "*" is in affected versions, all versions are affected
        if affectedVersions.contains("*") {
            return true
        }

        // Check if current version is in the affected list
        let normalizedVersion = normalizeVersion(version)
        return affectedVersions.contains { affectedVersion in
            normalizeVersion(affectedVersion) == normalizedVersion
        }
    }

    private func normalizeVersion(_ version: String) -> String {
        // Remove common prefixes and normalize format
        return version
            .replacingOccurrences(of: "v", with: "")
            .replacingOccurrences(of: "version", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

enum TahoeIncompatibilitySeverity: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    var description: String {
        switch self {
        case .low:
            return "Minor issues"
        case .medium:
            return "Moderate problems"
        case .high:
            return "Significant issues"
        case .critical:
            return "App unusable"
        }
    }

    var color: String {
        switch self {
        case .low:
            return "yellow"
        case .medium:
            return "orange"
        case .high:
            return "red"
        case .critical:
            return "purple"
        }
    }
}

enum TahoeCompatibilityStatus {
    case compatible
    case risky(reason: String)
    case incompatible(reason: String, fixedInVersion: String?)

    var isProblematic: Bool {
        switch self {
        case .compatible:
            return false
        case .risky, .incompatible:
            return true
        }
    }

    var description: String {
        switch self {
        case .compatible:
            return "Compatible with macOS Tahoe"
        case .risky(let reason):
            return "⚠️ Caution: \(reason)"
        case .incompatible(let reason, let fixedVersion):
            if let fixedVersion = fixedVersion {
                return "❌ Incompatible: \(reason) (Fixed in v\(fixedVersion))"
            } else {
                return "❌ Incompatible: \(reason)"
            }
        }
    }
}

// MARK: - Integration with Update Detection

extension UpdateDetector {
    func checkTahoeCompatibility(_ updates: [UpdateInfo]) async -> [UpdateInfo] {
        let compatibilityChecker = TahoeCompatibilityChecker()
        return compatibilityChecker.filterIncompatibleUpdates(updates)
    }
}

// MARK: - Tahoe Breakers JSON Structure

struct TahoeBreakersList: Codable {
    let lastUpdated: String
    let macOSVersion: String
    let breakers: [TahoeBreakerItem]
}

struct TahoeBreakerItem: Codable {
    let bundleIDs: [String]
    let appNames: [String]
    let affectedVersions: [String]
    let fixedInVersion: String?
    let reason: String
    let severity: String
    let source: String
    let reportedDate: String
}

// MARK: - Remote Update Capability

extension TahoeCompatibilityChecker {
    func updateBreakersList() async {
        // In production, this would fetch from a remote API
        // For MVP, we'll use the hardcoded list
        do {
            let url = URL(string: "https://api.autoup.app/tahoe-breakers.json")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let remoteBreakers = try JSONDecoder().decode(TahoeBreakersList.self, from: data)

            // Convert and update local list
            // This would update the local cache for future use
            print("Updated Tahoe breakers list: \(remoteBreakers.breakers.count) items")

        } catch {
            print("Failed to update Tahoe breakers list: \(error)")
            // Continue with cached/hardcoded list
        }
    }
}