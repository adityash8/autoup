import Foundation

enum SecurityChecks {
    static func backup(appPath: String, bundleID: String, version: String) throws -> URL {
        let base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/AutoUp/Backups/\(bundleID)/\(version)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let dest = base.appendingPathComponent((appPath as NSString).lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: appPath), to: dest)
        return dest
    }

    static func verifyCodeSign(_ appPath: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["--verify", "--deep", "--strict", appPath]
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    static func getQuarantineStatus(_ appPath: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-p", "com.apple.quarantine", appPath]
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    static func removeQuarantine(_ appPath: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-d", "com.apple.quarantine", appPath]
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}