import Foundation
import AppKit

@MainActor
class AppScanner: ObservableObject {
    @Published var installedApps: [AppInfo] = []
    @Published var isScanning = false

    private let fileManager = FileManager.default
    private let applicationsPaths = [
        "/Applications",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
    ]

    func scanInstalledApps() async -> [AppInfo] {
        isScanning = true
        defer { isScanning = false }

        var apps: [AppInfo] = []

        for path in applicationsPaths {
            let pathApps = await scanDirectory(path: path)
            apps.append(contentsOf: pathApps)
        }

        // Remove duplicates based on bundle ID
        let uniqueApps = Dictionary(grouping: apps, by: { $0.bundleID })
            .compactMapValues { $0.first }
            .values
            .sorted { $0.name.lowercased() < $1.name.lowercased() }

        installedApps = Array(uniqueApps)
        return installedApps
    }

    private func scanDirectory(path: String) async -> [AppInfo] {
        guard fileManager.fileExists(atPath: path) else { return [] }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            var apps: [AppInfo] = []

            for item in contents {
                if item.hasSuffix(".app") {
                    let appPath = "\(path)/\(item)"
                    if let appInfo = await parseAppBundle(path: appPath) {
                        apps.append(appInfo)
                    }
                }
            }

            return apps
        } catch {
            print("Error scanning directory \(path): \(error)")
            return []
        }
    }

    private func parseAppBundle(path: String) async -> AppInfo? {
        let infoPlistPath = "\(path)/Contents/Info.plist"

        guard fileManager.fileExists(atPath: infoPlistPath) else { return nil }

        do {
            let plistData = try Data(contentsOf: URL(fileURLWithPath: infoPlistPath))
            guard let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
                return nil
            }

            // Extract basic info
            guard let bundleID = plist["CFBundleIdentifier"] as? String,
                  let name = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String else {
                return nil
            }

            let version = plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String ?? "Unknown"

            // Get file modification date
            let attributes = try fileManager.attributesOfItem(atPath: path)
            let lastModified = attributes[.modificationDate] as? Date ?? Date()

            // Extract Sparkle feed URL
            let sparkleURL = plist["SUFeedURL"] as? String

            // Check for icon
            let iconPath = findAppIcon(appPath: path, plist: plist)

            // Check if it's a Homebrew app
            let isHomebrew = path.contains("/opt/homebrew/") || checkIfHomebrewApp(bundleID: bundleID)

            // Try to determine GitHub repo
            let githubRepo = inferGitHubRepo(bundleID: bundleID, name: name)

            return AppInfo(
                bundleID: bundleID,
                name: name,
                version: version,
                path: path,
                iconPath: iconPath,
                sparkleURL: sparkleURL,
                githubRepo: githubRepo,
                isHomebrew: isHomebrew,
                lastModified: lastModified
            )

        } catch {
            print("Error parsing app bundle at \(path): \(error)")
            return nil
        }
    }

    private func findAppIcon(appPath: String, plist: [String: Any]) -> String? {
        // Try to find app icon from Info.plist
        if let iconFile = plist["CFBundleIconFile"] as? String {
            let iconPath = "\(appPath)/Contents/Resources/\(iconFile)"
            if fileManager.fileExists(atPath: iconPath) {
                return iconPath
            }
            // Try with .icns extension
            let iconPathWithExt = "\(iconPath).icns"
            if fileManager.fileExists(atPath: iconPathWithExt) {
                return iconPathWithExt
            }
        }

        // Try common icon names
        let commonIconNames = ["icon.icns", "app.icns", "AppIcon.icns"]
        for iconName in commonIconNames {
            let iconPath = "\(appPath)/Contents/Resources/\(iconName)"
            if fileManager.fileExists(atPath: iconPath) {
                return iconPath
            }
        }

        return nil
    }

    private func checkIfHomebrewApp(bundleID: String) -> Bool {
        // Simple heuristic - check if app is in Homebrew casks
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        process.arguments = ["list", "--cask"]

        do {
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Basic matching - could be improved
            return output.lowercased().contains(bundleID.lowercased()) ||
                   output.lowercased().contains(bundleID.components(separatedBy: ".").last?.lowercased() ?? "")
        } catch {
            return false
        }
    }

    private func inferGitHubRepo(bundleID: String, name: String) -> String? {
        // Hardcoded mapping for popular apps
        let repoMapping: [String: String] = [
            "com.microsoft.VSCode": "microsoft/vscode",
            "com.github.atom": "atom/atom",
            "com.sublimetext.4": "sublimehq/sublime_text",
            "org.mozilla.firefox": "mozilla/firefox",
            "com.google.Chrome": "google/chrome",
            "com.raycast.macos": "raycast/raycast",
            "com.runningwithcrayons.Alfred": "alfred-app/alfred",
            "com.figma.Desktop": "figma/figma-api",
            "com.tinyapp.TableFlip": "chockenberry/tableflip"
        ]

        if let repo = repoMapping[bundleID] {
            return repo
        }

        // Try to infer from bundle ID
        let components = bundleID.components(separatedBy: ".")
        if components.count >= 3 {
            let domain = components[1]
            let appName = components[2]

            // Check if domain looks like a GitHub username
            if domain != "com" && domain != "org" && domain != "net" {
                return "\(domain)/\(appName.lowercased())"
            }
        }

        return nil
    }
}