import AppKit
import Foundation

class InstallManager: ObservableObject {
    @Published var currentInstallations: [String: InstallProgress] = [:]

    private let fileManager = FileManager.default
    private let downloadManager = DownloadManager()
    private let rollbackManager = RollbackManager()
    private let safeProcess = SafeProcess()
    private let atomicFileManager = AtomicFileManager()

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
        // Validate that brew is available
        guard await safeProcess.isExecutableAvailable("brew") else {
            throw InstallError.homebrewNotAvailable
        }

        // Sanitize cask name to prevent injection
        let caskName = sanitizeCaskName(update.appInfo.name)

        do {
            let result = try await safeProcess.execute(
                executable: "brew",
                arguments: ["upgrade", "--cask", caskName],
                timeout: 300 // 5 minutes for Homebrew operations
            )

            if result.isSuccess {
                // Homebrew handles the installation directly
                return URL(fileURLWithPath: "/tmp/homebrew_success")
            } else {
                throw InstallError.homebrewFailed
            }
        } catch {
            throw InstallError.homebrewFailed
        }
    }

    private func sanitizeCaskName(_ name: String) -> String {
        // Remove dangerous characters and convert to safe format
        let allowedChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return name.lowercased()
            .components(separatedBy: allowedChars.inverted)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
            Task {
                try? await unmountDMG(mountPoint)
            }
        }

        // Find the .app bundle in the mounted DMG
        let contents = try fileManager.contentsOfDirectory(atPath: mountPoint.path)
        guard let appFile = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw InstallError.appNotFoundInDMG
        }

        let sourceApp = mountPoint.appendingPathComponent(appFile)
        let destinationApp = URL(fileURLWithPath: update.appInfo.path)

        // Use atomic replacement to ensure safe installation
        let backupURL = try await atomicFileManager.atomicReplace(
            sourceURL: sourceApp,
            destinationURL: destinationApp,
            createBackup: true
        )

        // Store backup information for potential rollback
        if let backupURL = backupURL {
            try await rollbackManager.registerBackup(
                appInfo: update.appInfo,
                backupURL: backupURL
            )
        }
    }

    private func installFromPKG(_ pkgFile: URL, update: UpdateInfo) async throws {
        // Validate PKG file exists and is readable
        guard fileManager.fileExists(atPath: pkgFile.path) else {
            throw InstallError.pkgFileNotFound
        }

        do {
            let result = try await safeProcess.execute(
                executable: "installer",
                arguments: ["-pkg", pkgFile.path, "-target", "/"],
                timeout: 600 // 10 minutes for package installation
            )

            if !result.isSuccess {
                throw InstallError.pkgInstallationFailed
            }
        } catch {
            throw InstallError.pkgInstallationFailed
        }
    }

    private func installFromZIP(_ zipFile: URL, update: UpdateInfo) async throws {
        // Extract ZIP to temporary directory
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // Unzip using safe process execution
        do {
            let result = try await safeProcess.execute(
                executable: "unzip",
                arguments: ["-q", zipFile.path, "-d", tempDir.path],
                timeout: 120 // 2 minutes for extraction
            )

            if !result.isSuccess {
                throw InstallError.zipExtractionFailed
            }
        } catch {
            throw InstallError.zipExtractionFailed
        }

        // Find .app bundle in extracted contents
        let contents = try fileManager.contentsOfDirectory(atPath: tempDir.path)
        guard let appFile = findAppBundle(in: contents, at: tempDir) else {
            throw InstallError.appNotFoundInZIP
        }

        let sourceApp = tempDir.appendingPathComponent(appFile)
        let destinationApp = URL(fileURLWithPath: update.appInfo.path)

        // Use atomic replacement to ensure safe installation
        let backupURL = try await atomicFileManager.atomicReplace(
            sourceURL: sourceApp,
            destinationURL: destinationApp,
            createBackup: true
        )

        // Store backup information for potential rollback
        if let backupURL = backupURL {
            try await rollbackManager.registerBackup(
                appInfo: update.appInfo,
                backupURL: backupURL
            )
        }
    }

    private func findAppBundle(in contents: [String], at directory: URL) -> String? {
        for item in contents {
            if item.hasSuffix(".app") {
                return item
            }

            // Check subdirectories
            let itemPath = directory.appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: itemPath.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                if let subContents = try? fileManager.contentsOfDirectory(atPath: itemPath.path),
                   let appBundle = findAppBundle(in: subContents, at: itemPath)
                {
                    return "\(item)/\(appBundle)"
                }
            }
        }
        return nil
    }

    private func mountDMG(_ dmgFile: URL) async throws -> URL {
        // Validate DMG file exists
        guard fileManager.fileExists(atPath: dmgFile.path) else {
            throw InstallError.dmgFileNotFound
        }

        do {
            let result = try await safeProcess.execute(
                executable: "hdiutil",
                arguments: ["attach", "-nobrowse", "-quiet", dmgFile.path],
                timeout: 120 // 2 minutes for mounting
            )

            if result.isSuccess {
                // Parse mount point from hdiutil output
                let lines = result.stdout.components(separatedBy: .newlines)
                for line in lines {
                    let components = line.components(separatedBy: .whitespaces)
                    if let mountPoint = components.last, mountPoint.hasPrefix("/Volumes/") {
                        return URL(fileURLWithPath: mountPoint)
                    }
                }
            }

            throw InstallError.dmgMountFailed
        } catch {
            throw InstallError.dmgMountFailed
        }
    }

    private func unmountDMG(_ mountPoint: URL) async throws {
        do {
            _ = try await safeProcess.execute(
                executable: "hdiutil",
                arguments: ["detach", mountPoint.path, "-quiet"],
                timeout: 30
            )
        } catch {
            // Log but don't fail on unmount errors
            print("Warning: Failed to unmount DMG at \(mountPoint.path): \(error)")
        }
    }
}

class DownloadManager {
    private let urlSession = URLSession.shared

    func download(from url: URL) async throws -> URL {
        let (tempURL, _) = try await urlSession.download(from: url)

        // Move to a more permanent location
        guard let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw DownloadError.downloadsDirectoryNotFound
        }
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
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access Application Support directory")
        }
        cacheDirectory = appSupport.appendingPathComponent("AutoUp/Cache")

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func createRollbackPoint(for app: AppInfo) async throws {
        let appURL = URL(fileURLWithPath: app.path)
        let rollbackName = "\(app.bundleID)_\(app.version).zip"
        let rollbackURL = cacheDirectory.appendingPathComponent(rollbackName)

        // Create ZIP of current app using safe process execution
        let safeProcess = SafeProcess()

        do {
            let result = try await safeProcess.execute(
                executable: "zip",
                arguments: ["-r", "-q", rollbackURL.path, appURL.lastPathComponent],
                timeout: 300, // 5 minutes for backup creation
                workingDirectory: appURL.deletingLastPathComponent()
            )

            if !result.isSuccess {
                throw InstallError.rollbackCreationFailed
            }
        } catch {
            throw InstallError.rollbackCreationFailed
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

        // Extract rollback version using safe process execution
        let safeProcess = SafeProcess()

        do {
            let result = try await safeProcess.execute(
                executable: "unzip",
                arguments: ["-q", rollbackURL.path, "-d", appURL.deletingLastPathComponent().path],
                timeout: 120 // 2 minutes for extraction
            )

            if !result.isSuccess {
                throw InstallError.rollbackFailed
            }
        } catch {
            throw InstallError.rollbackFailed
        }
    }

    func registerBackup(appInfo: AppInfo, backupURL: URL) async throws {
        // Store backup metadata for future rollback operations
        let metadataURL = cacheDirectory.appendingPathComponent("\(appInfo.bundleID)_backup_metadata.json")

        let metadata = BackupMetadata(
            appInfo: appInfo,
            backupURL: backupURL,
            createdAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL)
    }

    func getAvailableBackups(for bundleID: String) -> [BackupMetadata] {
        // Return available backups for the given app
        guard let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        var backups: [BackupMetadata] = []

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "json" && fileURL.lastPathComponent.contains(bundleID) {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let metadata = try decoder.decode(BackupMetadata.self, from: data)
                    backups.append(metadata)
                } catch {
                    print("Failed to decode backup metadata: \(error)")
                }
            }
        }

        return backups.sorted { $0.createdAt > $1.createdAt }
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
    case homebrewNotAvailable
    case unsupportedFileType(String)
    case appNotFoundInDMG
    case appNotFoundInZIP
    case pkgInstallationFailed
    case pkgFileNotFound
    case zipExtractionFailed
    case dmgMountFailed
    case dmgFileNotFound
    case rollbackCreationFailed
    case rollbackNotAvailable
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidDownloadURL:
            "Invalid download URL"
        case .homebrewFailed:
            "Homebrew update failed"
        case .homebrewNotAvailable:
            "Homebrew is not available on this system"
        case .unsupportedFileType(let type):
            "Unsupported file type: \(type)"
        case .appNotFoundInDMG:
            "App not found in DMG file"
        case .appNotFoundInZIP:
            "App not found in ZIP file"
        case .pkgInstallationFailed:
            "Package installation failed"
        case .pkgFileNotFound:
            "Package file not found"
        case .zipExtractionFailed:
            "ZIP extraction failed"
        case .dmgMountFailed:
            "DMG mounting failed"
        case .dmgFileNotFound:
            "DMG file not found"
        case .rollbackCreationFailed:
            "Failed to create rollback point"
        case .rollbackNotAvailable:
            "Rollback version not available"
        case .rollbackFailed:
            "Rollback failed"
        }
    }
}

enum DownloadError: Error, LocalizedError {
    case downloadsDirectoryNotFound

    var errorDescription: String? {
        switch self {
        case .downloadsDirectoryNotFound:
            "Downloads directory not found"
        }
    }
}

struct BackupMetadata: Codable {
    let appInfo: AppInfo
    let backupURL: URL
    let createdAt: Date
}
