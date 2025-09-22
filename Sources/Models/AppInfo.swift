import Foundation

struct AppInfo: Identifiable, Codable, Hashable {
    let id = UUID()
    let bundleID: String
    let name: String
    let version: String
    let path: String
    let iconPath: String?
    let sparkleURL: String?
    let githubRepo: String?
    let isHomebrew: Bool
    let lastModified: Date

    var healthScore: HealthScore {
        // Will be computed based on update availability and security status
        .current
    }

    enum CodingKeys: String, CodingKey {
        case bundleID, name, version, path, iconPath, sparkleURL, githubRepo, isHomebrew, lastModified
    }
}

enum HealthScore: String, CaseIterable, Codable {
    case current
    case updateAvailable = "update_available"
    case securityUpdate = "security_update"
    case tahoeIncompatible = "tahoe_incompatible"

    var color: String {
        switch self {
        case .current:
            "green"
        case .updateAvailable:
            "yellow"
        case .securityUpdate:
            "red"
        case .tahoeIncompatible:
            "purple"
        }
    }

    var description: String {
        switch self {
        case .current:
            "Up to date"
        case .updateAvailable:
            "Update available"
        case .securityUpdate:
            "Security update"
        case .tahoeIncompatible:
            "Tahoe incompatible"
        }
    }
}

struct UpdateInfo: Identifiable, Codable {
    let id = UUID()
    let appInfo: AppInfo
    let availableVersion: String
    let changelog: String?
    let downloadURL: String
    let isSecurityUpdate: Bool
    let isTahoeCompatible: Bool
    let summary: String?
    let detectedAt: Date

    enum CodingKeys: String, CodingKey {
        case appInfo, availableVersion, changelog, downloadURL, isSecurityUpdate, isTahoeCompatible, summary,
             detectedAt
    }
}

struct UpdateHistory: Identifiable, Codable {
    let id = UUID()
    let appInfo: AppInfo
    let fromVersion: String
    let toVersion: String
    let installedAt: Date
    let rollbackAvailable: Bool
    let rollbackPath: String?

    enum CodingKeys: String, CodingKey {
        case appInfo, fromVersion, toVersion, installedAt, rollbackAvailable, rollbackPath
    }
}
