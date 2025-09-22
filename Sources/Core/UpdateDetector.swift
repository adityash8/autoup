import Foundation

@MainActor
class UpdateDetector: ObservableObject {
    @Published var availableUpdates: [UpdateInfo] = []
    @Published var isChecking = false

    private let urlSession = URLSession.shared
    private let sparkleDetector = SparkleUpdateDetector()
    private let homebrewDetector = HomebrewUpdateDetector()
    private let githubDetector = GitHubUpdateDetector()

    func checkForUpdates(apps: [AppInfo]) async -> [UpdateInfo] {
        isChecking = true
        defer { isChecking = false }

        var updates: [UpdateInfo] = []

        await withTaskGroup(of: [UpdateInfo].self) { group in
            // Check Sparkle feeds
            for app in apps where app.sparkleURL != nil {
                group.addTask {
                    await self.sparkleDetector.checkForUpdate(app: app) ?? []
                }
            }

            // Check Homebrew
            group.addTask {
                await self.homebrewDetector.checkForUpdates(apps: apps.filter(\.isHomebrew))
            }

            // Check GitHub
            for app in apps where app.githubRepo != nil {
                group.addTask {
                    await self.githubDetector.checkForUpdate(app: app) ?? []
                }
            }

            for await result in group {
                updates.append(contentsOf: result)
            }
        }

        // Remove duplicates and sort by priority
        let uniqueUpdates = Dictionary(grouping: updates, by: { $0.appInfo.bundleID })
            .compactMapValues { $0.first }
            .values
            .sorted { lhs, rhs in
                if lhs.isSecurityUpdate != rhs.isSecurityUpdate {
                    return lhs.isSecurityUpdate
                }
                return lhs.appInfo.name < rhs.appInfo.name
            }

        availableUpdates = Array(uniqueUpdates)
        return availableUpdates
    }
}

class SparkleUpdateDetector {
    private let urlSession = URLSession.shared

    func checkForUpdate(app: AppInfo) async -> [UpdateInfo]? {
        guard let sparkleURLString = app.sparkleURL,
              let sparkleURL = URL(string: sparkleURLString)
        else {
            return nil
        }

        do {
            let (data, _) = try await urlSession.data(from: sparkleURL)
            let parser = SparkleXMLParser()
            let updateInfo = parser.parseSparkleXML(data: data, for: app)
            return updateInfo.map { [$0] }
        } catch {
            print("Error checking Sparkle update for \(app.name): \(error)")
            return nil
        }
    }
}

class HomebrewUpdateDetector {
    private let safeProcess = SafeProcess()

    func checkForUpdates(apps: [AppInfo]) async -> [UpdateInfo] {
        guard !apps.isEmpty else { return [] }

        do {
            // Check if brew is available
            guard await safeProcess.isExecutableAvailable("brew") else {
                print("Homebrew not available")
                return []
            }

            let result = try await safeProcess.execute(
                executable: "brew",
                arguments: ["outdated", "--cask", "--json"],
                timeout: 60
            )

            guard result.isSuccess else {
                print("Homebrew command failed: \(result.stderr)")
                return []
            }

            let data = result.stdout.data(using: .utf8) ?? Data()
            let outdatedCasks = try JSONDecoder().decode(HomebrewOutdatedResponse.self, from: data)

            var updates: [UpdateInfo] = []

            for cask in outdatedCasks.casks {
                if let app = apps.first(where: { matchesHomebrewCask($0, cask: cask) }) {
                    let update = UpdateInfo(
                        appInfo: app,
                        availableVersion: cask.current_version,
                        changelog: nil,
                        downloadURL: "", // Homebrew handles downloads
                        isSecurityUpdate: false,
                        isTahoeCompatible: true,
                        summary: "Homebrew cask update available",
                        detectedAt: Date()
                    )
                    updates.append(update)
                }
            }

            return updates
        } catch {
            print("Error checking Homebrew updates: \(error)")
            return []
        }
    }

    private func matchesHomebrewCask(_ app: AppInfo, cask: HomebrewCask) -> Bool {
        // Simple matching heuristic
        let appNameLower = app.name.lowercased()
        let caskNameLower = cask.name.lowercased()

        return appNameLower.contains(caskNameLower) ||
            caskNameLower.contains(appNameLower) ||
            app.bundleID.lowercased().contains(caskNameLower)
    }
}

class GitHubUpdateDetector {
    private let urlSession = URLSession.shared

    func checkForUpdate(app: AppInfo) async -> [UpdateInfo]? {
        guard let repo = app.githubRepo else { return nil }

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return nil
        }

        do {
            let (data, _) = try await urlSession.data(from: url)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            if Versioning.isNewer(release.tag_name, than: app.version) {
                let isSecurityUpdate = containsSecurityKeywords(release.body ?? "")

                // Find download URL for macOS
                let downloadURL = findMacOSDownloadURL(from: release.assets) ?? release.html_url

                let update = UpdateInfo(
                    appInfo: app,
                    availableVersion: release.tag_name,
                    changelog: release.body,
                    downloadURL: downloadURL,
                    isSecurityUpdate: isSecurityUpdate,
                    isTahoeCompatible: true, // TODO: Check against compatibility list
                    summary: nil, // Will be generated by AI
                    detectedAt: Date()
                )

                return [update]
            }

            return nil
        } catch {
            print("Error checking GitHub update for \(app.name): \(error)")
            return nil
        }
    }


    private func containsSecurityKeywords(_ text: String) -> Bool {
        let securityKeywords = ["security", "vulnerability", "cve", "exploit", "patch", "fix"]
        let lowercaseText = text.lowercased()

        return securityKeywords.contains { lowercaseText.contains($0) }
    }

    private func findMacOSDownloadURL(from assets: [GitHubAsset]) -> String? {
        // Look for macOS-specific assets
        let macAssets = assets.filter { asset in
            let name = asset.name.lowercased()
            return name.contains("mac") || name.contains("darwin") || name.contains(".dmg") || name
                .contains(".pkg")
        }

        return macAssets.first?.browser_download_url
    }
}

class SparkleXMLParser {
    func parseSparkleXML(data: Data, for app: AppInfo) -> UpdateInfo? {
        guard let xmlString = String(data: data, encoding: .utf8) else { return nil }

        // Simple XML parsing - in production, use XMLParser or a proper XML library
        let lines = xmlString.components(separatedBy: .newlines)

        var version: String?
        var url: String?
        var description: String?

        for line in lines {
            if line.contains("sparkle:version=") {
                version = extractAttribute(from: line, attribute: "sparkle:version")
            } else if line.contains("url="), url == nil {
                url = extractAttribute(from: line, attribute: "url")
            } else if line.contains("<description>") {
                description = extractContent(from: line, tag: "description")
            }
        }

        guard let latestVersion = version,
              let downloadURL = url,
              Versioning.isNewer(latestVersion, than: app.version)
        else {
            return nil
        }

        let isSecurityUpdate = containsSecurityKeywords(description ?? "")

        return UpdateInfo(
            appInfo: app,
            availableVersion: latestVersion,
            changelog: description,
            downloadURL: downloadURL,
            isSecurityUpdate: isSecurityUpdate,
            isTahoeCompatible: true,
            summary: nil,
            detectedAt: Date()
        )
    }

    private func extractAttribute(from line: String, attribute: String) -> String? {
        guard let range = line.range(of: "\(attribute)=\"") else { return nil }
        let start = range.upperBound
        guard let endRange = line[start...].range(of: "\"") else { return nil }
        return String(line[start ..< endRange.lowerBound])
    }

    private func extractContent(from line: String, tag: String) -> String? {
        guard let startRange = line.range(of: "<\(tag)>"),
              let endRange = line.range(of: "</\(tag)>") else { return nil }
        return String(line[startRange.upperBound ..< endRange.lowerBound])
    }


    private func containsSecurityKeywords(_ text: String) -> Bool {
        let securityKeywords = ["security", "vulnerability", "cve", "exploit", "patch", "fix"]
        let lowercaseText = text.lowercased()
        return securityKeywords.contains { lowercaseText.contains($0) }
    }
}

// MARK: - Data Models for External APIs

struct HomebrewOutdatedResponse: Codable {
    let casks: [HomebrewCask]
}

struct HomebrewCask: Codable {
    let name: String
    let installed_versions: [String]
    let current_version: String
}

struct GitHubRelease: Codable {
    let tag_name: String
    let name: String
    let body: String?
    let html_url: String
    let assets: [GitHubAsset]
    let published_at: String
}

struct GitHubAsset: Codable {
    let name: String
    let browser_download_url: String
    let size: Int
}
