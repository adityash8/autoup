import Foundation

// Curated mapping of bundle IDs to GitHub repositories
let RepoHints: [String: (owner: String, repo: String)] = [
    // Developer Tools
    "com.microsoft.VSCode": ("microsoft", "vscode"),
    "com.github.GitHubDesktop": ("desktop", "desktop"),
    "com.figma.Desktop": ("figma", "figma-linux"),
    "com.postmanlabs.mac": ("postmanlabs", "postman-app-support"),

    // Productivity
    "com.raycast.macos": ("raycast", "raycast"),
    "com.electron.reeder.5": ("reederapp", "reeder5"),
    "com.culturedcode.ThingsMac": ("culturedcode", "things-mac"),
    "com.flexibits.fantastical2.mac": ("flexibits", "fantastical-mac"),

    // Media & Design
    "org.blender": ("blender", "blender"),
    "com.spotify.client": ("spotify", "spotify-desktop"),
    "com.getdavinci.DaVinciResolve": ("blackmagicdesign", "davinci-resolve"),

    // Communication
    "com.tinyspeck.slackmacgap": ("slack", "slack-desktop"),
    "com.microsoft.teams2": ("microsoft", "teams-desktop"),
    "ru.keepcoder.Telegram": ("telegramdesktop", "tdesktop"),

    // Utilities
    "com.1password.1password": ("1password", "1password-desktop"),
    "com.objective-see.lulu.app": ("objective-see", "lulu"),
    "com.posthog.desktop": ("posthog", "posthog-desktop"),
    "com.sindresorhus.CleanMyMac": ("sindresorhus", "cleanmymac"),

    // Browsers
    "com.google.Chrome": ("google", "chrome"),
    "com.microsoft.edgemac": ("microsoft", "edge"),
    "com.brave.Browser": ("brave", "brave-browser"),

    // Open Source
    "org.videolan.vlc": ("videolan", "vlc"),
    "org.mozilla.firefox": ("mozilla", "firefox"),
    "com.openemu.OpenEmu": ("openemu", "openemu"),
]

enum RepoDiscovery {
    static func guessRepository(for bundleID: String, appName: String) -> (owner: String, repo: String)? {
        // Check our curated list first
        if let repo = RepoHints[bundleID] {
            return repo
        }

        // Try common patterns
        let cleanName = appName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "")

        // Common organization patterns
        let commonOwners = [
            cleanName,
            "\(cleanName)-team",
            "\(cleanName)app",
            "electron-apps"
        ]

        // Return first guess (caller should validate)
        return (owner: commonOwners.first ?? cleanName, repo: cleanName)
    }

    static func validateRepository(owner: String, repo: String) async -> Bool {
        do {
            _ = try await GitHub.latest(owner: owner, repo: repo)
            return true
        } catch {
            return false
        }
    }
}