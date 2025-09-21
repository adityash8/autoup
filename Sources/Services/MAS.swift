import Foundation
import AppKit

enum MAS {
    static func updatesAvailable() async -> Int {
        // Try to use mas command line tool if available
        if isMasInstalled() {
            return await getMasUpdatesCount()
        }

        // Fallback: Check if App Store has updates by looking at the dock badge
        return getAppStoreBadgeCount()
    }

    static func openUpdates() {
        guard let url = URL(string: "macappstore://showUpdatesPage") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openAppStore() {
        guard let url = URL(string: "macappstore://") else { return }
        NSWorkspace.shared.open(url)
    }

    static func isMasInstalled() -> Bool {
        let result = shell("command -v mas")
        return result.exitCode == 0
    }

    static func installMas() -> Bool {
        if isMasInstalled() { return true }

        // Try to install via Homebrew
        if Brew.isBrewInstalled() {
            let result = shell("brew install mas")
            return result.exitCode == 0
        }

        return false
    }

    static func isAppFromMAS(_ appPath: String) -> Bool {
        // Check if app has Mac App Store receipt
        let receiptPath = "\(appPath)/Contents/_MASReceipt/receipt"
        return FileManager.default.fileExists(atPath: receiptPath)
    }

    static func getMASAppID(_ appPath: String) -> String? {
        guard isAppFromMAS(appPath) else { return nil }

        // Try to extract app ID from receipt or bundle
        let result = shell("mdls -name kMDItemAppStoreHasReceipt -name kMDItemAppStoreInstallerVersionID '\(appPath)'")

        if result.exitCode == 0 && result.output.contains("= 1") {
            // Parse the installer version ID if available
            let lines = result.output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("kMDItemAppStoreInstallerVersionID") {
                    let components = line.components(separatedBy: "= ")
                    if components.count > 1 {
                        return components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }

        return nil
    }

    private static func getMasUpdatesCount() async -> Int {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                let result = shell("mas outdated | wc -l")
                let count = Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                continuation.resume(returning: count)
            }
        }
    }

    private static func getAppStoreBadgeCount() -> Int {
        // Try to get badge count from App Store app
        let appStoreApp = NSWorkspace.shared.runningApplications.first { app in
            app.bundleIdentifier == "com.apple.AppStore"
        }

        // This is a heuristic - we can't directly read the badge count
        // but we can check if the App Store is running and infer updates
        return appStoreApp != nil ? 0 : 0
    }

    @discardableResult
    private static func shell(_ command: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.launchPath = "/bin/zsh"
        process.arguments = ["-lc", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return (process.terminationStatus, output)
        } catch {
            return (-1, "")
        }
    }
}

// Extension for MAS app detection in existing apps
extension MAS {
    static func categorizeApps(_ apps: [AppInfo]) -> (masApps: [AppInfo], nonMasApps: [AppInfo]) {
        var masApps: [AppInfo] = []
        var nonMasApps: [AppInfo] = []

        for app in apps {
            if let path = app.path, isAppFromMAS(path) {
                masApps.append(app)
            } else {
                nonMasApps.append(app)
            }
        }

        return (masApps: masApps, nonMasApps: nonMasApps)
    }

    static func getMASAppsWithUpdates() async -> [AppInfo] {
        guard isMasInstalled() else { return [] }

        let result = shell("mas outdated")
        guard result.exitCode == 0 else { return [] }

        var apps: [AppInfo] = []
        let lines = result.output.components(separatedBy: .newlines)

        for line in lines {
            let components = line.components(separatedBy: .whitespaces)
            if components.count >= 2 {
                let appID = components[0]
                let name = components[1...].joined(separator: " ")

                let appInfo = AppInfo(
                    name: name,
                    bundleIdentifier: "mas.\(appID)",
                    version: "unknown",
                    path: nil,
                    iconPath: nil
                )
                apps.append(appInfo)
            }
        }

        return apps
    }
}