import Foundation

enum LaunchAgent {
    static let label = "com.autoup.helper"
    static var plistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func install(hour: Int = 3, minute: Int = 15) throws {
        let executablePath = Bundle.main.bundlePath + "/Contents/MacOS/AutoUp"

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath, "--background-run"],
            "StartCalendarInterval": [
                "Hour": hour,
                "Minute": minute
            ],
            "RunAtLoad": false,
            "StandardOutPath": NSHomeDirectory() + "/Library/Logs/AutoUp.log",
            "StandardErrorPath": NSHomeDirectory() + "/Library/Logs/AutoUp.err",
            "ProcessType": "Background",
            "LowPriorityIO": true,
            "Nice": 1
        ]

        // Ensure LaunchAgents directory exists
        let launchAgentsDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        // Write plist
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)

        // Unload if already loaded, then load
        _ = shell("launchctl unload \(shellQuote(plistURL.path)) 2>/dev/null || true")
        let loadResult = shell("launchctl load \(shellQuote(plistURL.path))")

        if loadResult != 0 {
            throw LaunchAgentError.loadFailed
        }
    }

    static func uninstall() throws {
        let unloadResult = shell("launchctl unload \(shellQuote(plistURL.path)) 2>/dev/null || true")

        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }

        // Don't fail if unload fails - the file might not be loaded
    }

    static func isInstalled() -> Bool {
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func isLoaded() -> Bool {
        let result = shell("launchctl list | grep \(shellQuote(label))")
        return result == 0
    }

    static func updateSchedule(hour: Int, minute: Int) throws {
        if isInstalled() {
            try uninstall()
        }
        try install(hour: hour, minute: minute)
    }

    static func getStatus() -> LaunchAgentStatus {
        let installed = isInstalled()
        let loaded = isLoaded()

        if installed && loaded {
            return .active
        } else if installed {
            return .installed
        } else {
            return .notInstalled
        }
    }

    enum LaunchAgentStatus {
        case notInstalled
        case installed
        case active
    }

    enum LaunchAgentError: LocalizedError {
        case loadFailed
        case invalidSchedule

        var errorDescription: String? {
            switch self {
            case .loadFailed:
                return "Failed to load LaunchAgent"
            case .invalidSchedule:
                return "Invalid schedule parameters"
            }
        }
    }

    @discardableResult
    private static func shell(_ command: String) -> Int32 {
        let process = Process()
        process.launchPath = "/bin/zsh"
        process.arguments = ["-lc", command]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private static func shellQuote(_ string: String) -> String {
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}