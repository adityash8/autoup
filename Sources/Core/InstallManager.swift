import Foundation
import AppKit

class InstallManager: ObservableObject {
    @Published var currentInstallations: [String: InstallProgress] = [:]

    private let fileManager = FileManager.default
    private let downloadManager = DownloadManager()
    private let rollbackManager = RollbackManager()

    func installUpdate(_ update: UpdateInfo) async throws {
        let appID = update.appInfo.bundleID

        await MainActor.run {
            currentInstallations[appID] = InstallProgress(
                appName: update.appInfo.name,
                status: .downloading,
                progress: 0.0
            )
        }

        do {
            // Step 1: Create rollback point
            try await rollbackManager.createRollbackPoint(for: update.appInfo)

            // Step 2: Download update
            let downloadedFile = try await downloadUpdate(update)

            await MainActor.run {
                currentInstallations[appID]?.status = .installing
                currentInstallations[appID]?.progress = 0.5
            }

            // Step 3: Install update
            try await performInstallation(downloadedFile: downloadedFile, update: update)

            await MainActor.run {
                currentInstallations[appID]?.status = .completed
                currentInstallations[appID]?.progress = 1.0
            }

            // Step 4: Cleanup
            try? fileManager.removeItem(at: downloadedFile)

            // Remove from current installations after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.currentInstallations.removeValue(forKey: appID)
            }

        } catch {
            await MainActor.run {
                currentInstallations[appID]?.status = .failed
                currentInstallations[appID]?.error = error
            }
            throw error
        }
    }

    private func downloadUpdate(_ update: UpdateInfo) async throws -> URL {
        guard let downloadURL = URL(string: update.downloadURL) else {
            throw InstallError.invalidDownloadURL
        }

        if update.appInfo.isHomebrew {
            // Handle Homebrew updates
            return try await downloadHomebrewUpdate(update)
        } else {
            // Handle direct downloads
            return try await downloadManager.download(from: downloadURL)
        }
    }

    private func downloadHomebrewUpdate(_ update: UpdateInfo) async throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        process.arguments = ["upgrade", "--cask", update.appInfo.name.lowercased()]

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        // Homebrew handles the installation directly
                        continuation.resume(returning: URL(fileURLWithPath: "/tmp/homebrew_success"))
                    } else {
                        continuation.resume(throwing: InstallError.homebrewFailed)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performInstallation(downloadedFile: URL, update: UpdateInfo) async throws {
        if update.appInfo.isHomebrew {
            // Homebrew already handled the installation
            return
        }

        let fileExtension = downloadedFile.pathExtension.lowercased()

        switch fileExtension {
        case "dmg":
            try await installFromDMG(downloadedFile, update: update)
        case "pkg":
            try await installFromPKG(downloadedFile, update: update)
        case "zip":
            try await installFromZIP(downloadedFile, update: update)
        default:
            throw InstallError.unsupportedFileType(fileExtension)
        }
    }

    private func installFromDMG(_ dmgFile: URL, update: UpdateInfo) async throws {
        // Mount the DMG
        let mountPoint = try await mountDMG(dmgFile)
        defer {
            // Unmount DMG
            try? unmountDMG(mountPoint)
        }

        // Find the .app bundle in the mounted DMG
        let contents = try fileManager.contentsOfDirectory(atPath: mountPoint.path)
        guard let appFile = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw InstallError.appNotFoundInDMG
        }

        let sourceApp = mountPoint.appendingPathComponent(appFile)
        let destinationApp = URL(fileURLWithPath: update.appInfo.path)

        // Remove old app
        if fileManager.fileExists(atPath: destinationApp.path) {
            try fileManager.removeItem(at: destinationApp)
        }

        // Copy new app
        try fileManager.copyItem(at: sourceApp, to: destinationApp)
    }

    private func installFromPKG(_ pkgFile: URL, update: UpdateInfo) async throws {
        // Use Installer.app or installer command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
        process.arguments = ["-pkg", pkgFile.path, "-target", "/"]

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: InstallError.pkgInstallationFailed)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func installFromZIP(_ zipFile: URL, update: UpdateInfo) async throws {
        // Extract ZIP to temporary directory
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // Unzip using system unzip command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipFile.path, "-d", tempDir.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw InstallError.zipExtractionFailed
        }

        // Find .app bundle in extracted contents
        let contents = try fileManager.contentsOfDirectory(atPath: tempDir.path)
        guard let appFile = findAppBundle(in: contents, at: tempDir) else {
            throw InstallError.appNotFoundInZIP
        }

        let sourceApp = tempDir.appendingPathComponent(appFile)
        let destinationApp = URL(fileURLWithPath: update.appInfo.path)

        // Remove old app
        if fileManager.fileExists(atPath: destinationApp.path) {
            try fileManager.removeItem(at: destinationApp)
        }

        // Copy new app
        try fileManager.copyItem(at: sourceApp, to: destinationApp)
    }

    private func findAppBundle(in contents: [String], at directory: URL) -> String? {
        for item in contents {
            if item.hasSuffix(".app") {
                return item
            }

            // Check subdirectories
            let itemPath = directory.appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: itemPath.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                if let subContents = try? fileManager.contentsOfDirectory(atPath: itemPath.path),
                   let appBundle = findAppBundle(in: subContents, at: itemPath) {
                    return "\(item)/\(appBundle)"
                }
            }
        }
        return nil
    }

    private func mountDMG(_ dmgFile: URL) async throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", "-nobrowse", "-quiet", dmgFile.path]

        let pipe = Pipe()
        process.standardOutput = pipe

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? ""

                        // Parse mount point from hdiutil output
                        let lines = output.components(separatedBy: .newlines)
                        for line in lines {
                            let components = line.components(separatedBy: .whitespaces)
                            if let mountPoint = components.last, mountPoint.hasPrefix("/Volumes/") {
                                continuation.resume(returning: URL(fileURLWithPath: mountPoint))
                                return
                            }
                        }

                        continuation.resume(throwing: InstallError.dmgMountFailed)
                    } else {
                        continuation.resume(throwing: InstallError.dmgMountFailed)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func unmountDMG(_ mountPoint: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint.path, "-quiet"]

        try process.run()
        process.waitUntilExit()
    }
}

class DownloadManager {
    private let urlSession = URLSession.shared

    func download(from url: URL) async throws -> URL {
        let (tempURL, _) = try await urlSession.download(from: url)

        // Move to a more permanent location
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileName = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let destinationURL = downloadsDir.appendingPathComponent("AutoUp_\(fileName)")

        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        return destinationURL
    }
}

class RollbackManager {
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("AutoUp/Cache")

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func createRollbackPoint(for app: AppInfo) async throws {
        let appURL = URL(fileURLWithPath: app.path)
        let rollbackName = "\(app.bundleID)_\(app.version).zip"
        let rollbackURL = cacheDirectory.appendingPathComponent(rollbackName)

        // Create ZIP of current app
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-q", rollbackURL.path, appURL.lastPathComponent]
        process.currentDirectoryURL = appURL.deletingLastPathComponent()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: InstallError.rollbackCreationFailed)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func rollback(app: AppInfo, to version: String) async throws {
        let rollbackName = "\(app.bundleID)_\(version).zip"
        let rollbackURL = cacheDirectory.appendingPathComponent(rollbackName)

        guard fileManager.fileExists(atPath: rollbackURL.path) else {
            throw InstallError.rollbackNotAvailable
        }

        // Remove current app
        let appURL = URL(fileURLWithPath: app.path)
        if fileManager.fileExists(atPath: appURL.path) {
            try fileManager.removeItem(at: appURL)
        }

        // Extract rollback version
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", rollbackURL.path, "-d", appURL.deletingLastPathComponent().path]

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: InstallError.rollbackFailed)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct InstallProgress {
    let appName: String
    var status: InstallStatus
    var progress: Double
    var error: Error?
}

enum InstallStatus {
    case downloading
    case installing
    case completed
    case failed
}

enum InstallError: Error, LocalizedError {
    case invalidDownloadURL
    case homebrewFailed
    case unsupportedFileType(String)
    case appNotFoundInDMG
    case appNotFoundInZIP
    case pkgInstallationFailed
    case zipExtractionFailed
    case dmgMountFailed
    case rollbackCreationFailed
    case rollbackNotAvailable
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidDownloadURL:
            return "Invalid download URL"
        case .homebrewFailed:
            return "Homebrew update failed"
        case .unsupportedFileType(let type):
            return "Unsupported file type: \(type)"
        case .appNotFoundInDMG:
            return "App not found in DMG file"
        case .appNotFoundInZIP:
            return "App not found in ZIP file"
        case .pkgInstallationFailed:
            return "Package installation failed"
        case .zipExtractionFailed:
            return "ZIP extraction failed"
        case .dmgMountFailed:
            return "DMG mounting failed"
        case .rollbackCreationFailed:
            return "Failed to create rollback point"
        case .rollbackNotAvailable:
            return "Rollback version not available"
        case .rollbackFailed:
            return "Rollback failed"
        }
    }
}