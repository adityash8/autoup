import Foundation

enum Rollback {
    static func latestBackup(bundleID: String) -> URL? {
        let base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/AutoUp/Backups/\(bundleID)")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else {
            return nil
        }

        return entries.sorted { (a, b) in
            let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return dateA > dateB
        }.first?.appendingPathComponent("\(bundleID).app")
    }

    static func restoreBackup(bundleID: String, to appName: String) throws -> Bool {
        guard let backupURL = latestBackup(bundleID: bundleID) else {
            return false
        }

        let currentAppPath = "/Applications/\(appName).app"
        let currentAppURL = URL(fileURLWithPath: currentAppPath)

        // Remove current version
        if FileManager.default.fileExists(atPath: currentAppPath) {
            try FileManager.default.removeItem(at: currentAppURL)
        }

        // Copy backup to Applications
        try FileManager.default.copyItem(at: backupURL, to: currentAppURL)

        // Remove quarantine if present
        _ = SecurityChecks.removeQuarantine(currentAppPath)

        return true
    }

    static func listAvailableBackups(bundleID: String) -> [(version: String, date: Date)] {
        let base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/AutoUp/Backups/\(bundleID)")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else {
            return []
        }

        return entries.compactMap { entry in
            guard let date = try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                return nil
            }
            let version = entry.lastPathComponent
            return (version: version, date: date)
        }.sorted { $0.date > $1.date }
    }

    static func cleanOldBackups(bundleID: String, keepLatest: Int = 3) {
        let backups = listAvailableBackups(bundleID: bundleID)
        let toDelete = backups.dropFirst(keepLatest)

        for backup in toDelete {
            let backupPath = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/AutoUp/Backups/\(bundleID)/\(backup.version)")
            try? FileManager.default.removeItem(at: backupPath)
        }
    }
}