import Foundation

enum InstallerError: LocalizedError {
    case noAppFound
    case dmgAttachFailed(Int32)
    case pkgInstallFailed(Int32)
    case codesignFailed
    case backupFailed

    var errorDescription: String? {
        switch self {
        case .noAppFound:
            return "Couldn't find the app in the download"
        case .dmgAttachFailed(let code):
            return "DMG mount failed with code \(code)"
        case .pkgInstallFailed(let code):
            return "PKG install failed with code \(code)"
        case .codesignFailed:
            return "App signature verification failed"
        case .backupFailed:
            return "Couldn't backup current version"
        }
    }
}

enum Installer {
    static func installZIP(from zipURL: URL, toApplications name: String, bundleID: String, currentVersion: String) throws {
        // Create backup first
        let currentAppPath = "/Applications/\(name).app"
        if FileManager.default.fileExists(atPath: currentAppPath) {
            _ = try? SecurityChecks.backup(appPath: currentAppPath, bundleID: bundleID, version: currentVersion)
        }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        _ = try run("/usr/bin/unzip", ["-qq", zipURL.path, "-d", tmp.path])
        let app = try findApp(in: tmp)

        // Verify codesign before installing
        guard SecurityChecks.verifyCodeSign(app.path) else {
            throw InstallerError.codesignFailed
        }

        try moveToApplications(app)
    }

    static func installDMG(from dmgURL: URL, bundleID: String, currentVersion: String) throws {
        // Create backup first
        let apps = try? FileManager.default.contentsOfDirectory(atPath: "/Applications")
        let currentAppPath = apps?.first { $0.hasSuffix(".app") && Bundle(path: "/Applications/\($0)")?.bundleIdentifier == bundleID }

        if let appPath = currentAppPath {
            let fullPath = "/Applications/\(appPath)"
            _ = try? SecurityChecks.backup(appPath: fullPath, bundleID: bundleID, version: currentVersion)
        }

        let (code, out) = try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-quiet", dmgURL.path])
        guard code == 0 else {
            throw InstallerError.dmgAttachFailed(code)
        }

        guard let mount = out.split(separator: "\t").last.map(String.init) else {
            throw InstallerError.dmgAttachFailed(-1)
        }

        defer { _ = try? run("/usr/bin/hdiutil", ["detach", "-quiet", mount]) }

        let app = try findApp(in: URL(fileURLWithPath: mount))

        // Verify codesign before installing
        guard SecurityChecks.verifyCodeSign(app.path) else {
            throw InstallerError.codesignFailed
        }

        try moveToApplications(app)
    }

    static func installPKG(from pkgURL: URL) throws {
        let (code, _) = try run("/usr/sbin/installer", ["-pkg", pkgURL.path, "-target", "/"])
        guard code == 0 else {
            throw InstallerError.pkgInstallFailed(code)
        }
    }

    // MARK: - Private Helpers

    private static func findApp(in dir: URL) throws -> URL {
        let items = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        if let app = items.first(where: { $0.pathExtension == "app" }) {
            return app
        }

        // Recursive search in case of subfolders
        for url in items where url.hasDirectoryPath {
            if let app = try? findApp(in: url) {
                return app
            }
        }

        throw InstallerError.noAppFound
    }

    private static func moveToApplications(_ src: URL) throws {
        let dst = URL(fileURLWithPath: "/Applications").appendingPathComponent(src.lastPathComponent)

        if FileManager.default.fileExists(atPath: dst.path) {
            try FileManager.default.removeItem(at: dst)
        }

        try FileManager.default.copyItem(at: src, to: dst)

        // Remove quarantine if present
        _ = SecurityChecks.removeQuarantine(dst.path)
    }

    @discardableResult
    private static func run(_ bin: String, _ args: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return (process.terminationStatus, output)
    }
}