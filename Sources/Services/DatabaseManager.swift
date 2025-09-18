import Foundation
import SQLite

class DatabaseManager: ObservableObject {
    private var db: Connection?
    private let dbPath: URL

    // Tables
    private let appsTable = Table("apps")
    private let updatesTable = Table("updates")
    private let historyTable = Table("update_history")
    private let settingsTable = Table("settings")

    // Apps table columns
    private let appId = Expression<Int64>("id")
    private let bundleID = Expression<String>("bundle_id")
    private let appName = Expression<String>("name")
    private let version = Expression<String>("version")
    private let path = Expression<String>("path")
    private let iconPath = Expression<String?>("icon_path")
    private let sparkleURL = Expression<String?>("sparkle_url")
    private let githubRepo = Expression<String?>("github_repo")
    private let isHomebrew = Expression<Bool>("is_homebrew")
    private let lastModified = Expression<Date>("last_modified")
    private let lastScanned = Expression<Date>("last_scanned")

    // Updates table columns
    private let updateId = Expression<Int64>("id")
    private let updateBundleID = Expression<String>("bundle_id")
    private let availableVersion = Expression<String>("available_version")
    private let changelog = Expression<String?>("changelog")
    private let downloadURL = Expression<String>("download_url")
    private let isSecurityUpdate = Expression<Bool>("is_security_update")
    private let isTahoeCompatible = Expression<Bool>("is_tahoe_compatible")
    private let summary = Expression<String?>("summary")
    private let detectedAt = Expression<Date>("detected_at")

    // History table columns
    private let historyId = Expression<Int64>("id")
    private let historyBundleID = Expression<String>("bundle_id")
    private let fromVersion = Expression<String>("from_version")
    private let toVersion = Expression<String>("to_version")
    private let installedAt = Expression<Date>("installed_at")
    private let rollbackAvailable = Expression<Bool>("rollback_available")
    private let rollbackPath = Expression<String?>("rollback_path")

    // Settings table columns
    private let settingKey = Expression<String>("key")
    private let settingValue = Expression<String>("value")

    init() {
        // Create database in Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let autoUpDir = appSupport.appendingPathComponent("AutoUp")

        do {
            try FileManager.default.createDirectory(at: autoUpDir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create AutoUp directory: \(error)")
        }

        dbPath = autoUpDir.appendingPathComponent("autoup.db")
        print("Database path: \(dbPath.path)")

        setupDatabase()
    }

    private func setupDatabase() {
        do {
            db = try Connection(dbPath.path)
            createTables()
        } catch {
            print("Database connection error: \(error)")
        }
    }

    private func createTables() {
        do {
            // Apps table
            try db?.run(appsTable.create(ifNotExists: true) { t in
                t.column(appId, primaryKey: .autoincrement)
                t.column(bundleID, unique: true)
                t.column(appName)
                t.column(version)
                t.column(path)
                t.column(iconPath)
                t.column(sparkleURL)
                t.column(githubRepo)
                t.column(isHomebrew)
                t.column(lastModified)
                t.column(lastScanned)
            })

            // Updates table
            try db?.run(updatesTable.create(ifNotExists: true) { t in
                t.column(updateId, primaryKey: .autoincrement)
                t.column(updateBundleID)
                t.column(availableVersion)
                t.column(changelog)
                t.column(downloadURL)
                t.column(isSecurityUpdate)
                t.column(isTahoeCompatible)
                t.column(summary)
                t.column(detectedAt)
                t.unique(updateBundleID, availableVersion)
            })

            // History table
            try db?.run(historyTable.create(ifNotExists: true) { t in
                t.column(historyId, primaryKey: .autoincrement)
                t.column(historyBundleID)
                t.column(fromVersion)
                t.column(toVersion)
                t.column(installedAt)
                t.column(rollbackAvailable)
                t.column(rollbackPath)
            })

            // Settings table
            try db?.run(settingsTable.create(ifNotExists: true) { t in
                t.column(settingKey, primaryKey: true)
                t.column(settingValue)
            })

        } catch {
            print("Failed to create tables: \(error)")
        }
    }

    // MARK: - App Management

    func saveApps(_ apps: [AppInfo]) {
        guard let db = db else { return }

        do {
            try db.transaction {
                for app in apps {
                    try db.run(appsTable.insert(or: .replace,
                        bundleID <- app.bundleID,
                        appName <- app.name,
                        version <- app.version,
                        path <- app.path,
                        iconPath <- app.iconPath,
                        sparkleURL <- app.sparkleURL,
                        githubRepo <- app.githubRepo,
                        isHomebrew <- app.isHomebrew,
                        lastModified <- app.lastModified,
                        lastScanned <- Date()
                    ))
                }
            }
        } catch {
            print("Failed to save apps: \(error)")
        }
    }

    func loadApps() -> [AppInfo] {
        guard let db = db else { return [] }

        do {
            let apps = try db.prepare(appsTable).map { row in
                AppInfo(
                    bundleID: row[bundleID],
                    name: row[appName],
                    version: row[version],
                    path: row[path],
                    iconPath: row[iconPath],
                    sparkleURL: row[sparkleURL],
                    githubRepo: row[githubRepo],
                    isHomebrew: row[isHomebrew],
                    lastModified: row[lastModified]
                )
            }
            return apps
        } catch {
            print("Failed to load apps: \(error)")
            return []
        }
    }

    // MARK: - Update Management

    func saveUpdates(_ updates: [UpdateInfo]) {
        guard let db = db else { return }

        do {
            // Clear existing updates
            try db.run(updatesTable.delete())

            // Insert new updates
            try db.transaction {
                for update in updates {
                    try db.run(updatesTable.insert(
                        updateBundleID <- update.appInfo.bundleID,
                        availableVersion <- update.availableVersion,
                        changelog <- update.changelog,
                        downloadURL <- update.downloadURL,
                        isSecurityUpdate <- update.isSecurityUpdate,
                        isTahoeCompatible <- update.isTahoeCompatible,
                        summary <- update.summary,
                        detectedAt <- update.detectedAt
                    ))
                }
            }
        } catch {
            print("Failed to save updates: \(error)")
        }
    }

    func loadUpdates() -> [UpdateInfo] {
        guard let db = db else { return [] }

        do {
            let apps = loadApps()
            let appsByBundleID = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleID, $0) })

            let updates = try db.prepare(updatesTable).compactMap { row -> UpdateInfo? in
                guard let app = appsByBundleID[row[updateBundleID]] else { return nil }

                return UpdateInfo(
                    appInfo: app,
                    availableVersion: row[availableVersion],
                    changelog: row[changelog],
                    downloadURL: row[downloadURL],
                    isSecurityUpdate: row[isSecurityUpdate],
                    isTahoeCompatible: row[isTahoeCompatible],
                    summary: row[summary],
                    detectedAt: row[detectedAt]
                )
            }
            return updates
        } catch {
            print("Failed to load updates: \(error)")
            return []
        }
    }

    // MARK: - Update History

    func saveUpdateHistory(_ historyItem: UpdateHistory) {
        guard let db = db else { return }

        do {
            try db.run(historyTable.insert(
                historyBundleID <- historyItem.appInfo.bundleID,
                fromVersion <- historyItem.fromVersion,
                toVersion <- historyItem.toVersion,
                installedAt <- historyItem.installedAt,
                rollbackAvailable <- historyItem.rollbackAvailable,
                rollbackPath <- historyItem.rollbackPath
            ))
        } catch {
            print("Failed to save update history: \(error)")
        }
    }

    func loadUpdateHistory(limit: Int = 50) -> [UpdateHistory] {
        guard let db = db else { return [] }

        do {
            let apps = loadApps()
            let appsByBundleID = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleID, $0) })

            let history = try db.prepare(
                historyTable
                    .order(installedAt.desc)
                    .limit(limit)
            ).compactMap { row -> UpdateHistory? in
                guard let app = appsByBundleID[row[historyBundleID]] else { return nil }

                return UpdateHistory(
                    appInfo: app,
                    fromVersion: row[fromVersion],
                    toVersion: row[toVersion],
                    installedAt: row[installedAt],
                    rollbackAvailable: row[rollbackAvailable],
                    rollbackPath: row[rollbackPath]
                )
            }
            return history
        } catch {
            print("Failed to load update history: \(error)")
            return []
        }
    }

    // MARK: - Settings

    func saveSetting(key: String, value: String) {
        guard let db = db else { return }

        do {
            try db.run(settingsTable.insert(or: .replace,
                settingKey <- key,
                settingValue <- value
            ))
        } catch {
            print("Failed to save setting \(key): \(error)")
        }
    }

    func loadSetting(key: String) -> String? {
        guard let db = db else { return nil }

        do {
            let query = settingsTable.filter(settingKey == key)
            if let row = try db.pluck(query) {
                return row[settingValue]
            }
        } catch {
            print("Failed to load setting \(key): \(error)")
        }
        return nil
    }

    // MARK: - Utility Methods

    func clearAllData() {
        guard let db = db else { return }

        do {
            try db.run(appsTable.delete())
            try db.run(updatesTable.delete())
            try db.run(historyTable.delete())
            try db.run(settingsTable.delete())
        } catch {
            print("Failed to clear data: \(error)")
        }
    }

    func getDatabaseSize() -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: dbPath.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    func exportToCSV() -> URL? {
        guard let db = db else { return nil }

        let documentsURL = FileManager.default.urls(for: .documentsDirectory, in: .userDomainMask).first!
        let csvURL = documentsURL.appendingPathComponent("autoup_export_\(Date().timeIntervalSince1970).csv")

        do {
            var csvContent = "App Name,Bundle ID,Version,Last Modified,Updates Available\n"

            let apps = loadApps()
            let updates = loadUpdates()
            let updatesByBundleID = Dictionary(grouping: updates, by: { $0.appInfo.bundleID })

            for app in apps {
                let hasUpdates = updatesByBundleID[app.bundleID]?.isEmpty == false
                csvContent += "\"\(app.name)\",\"\(app.bundleID)\",\"\(app.version)\",\"\(app.lastModified)\",\"\(hasUpdates)\"\n"
            }

            try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
            return csvURL

        } catch {
            print("Failed to export CSV: \(error)")
            return nil
        }
    }
}