import Foundation
import AppKit

enum SparkleHints {
    static func feedURL(forAppAt path: String) -> URL? {
        guard let bundle = Bundle(path: path) else { return nil }

        // Check Info.plist for SUFeedURL
        if let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           let url = URL(string: feed) {
            return url
        }

        // Check UserDefaults for the app's domain
        if let bundleIdentifier = bundle.bundleIdentifier {
            if let feed = UserDefaults(suiteName: bundleIdentifier)?.string(forKey: "SUFeedURL"),
               let url = URL(string: feed) {
                return url
            }
        }

        // Check for common Sparkle keys
        let sparkleKeys = [
            "SUFeedURL",
            "SUPublicDSAKeyFile",
            "SUPublicEDKey",
            "SUScheduledCheckInterval"
        ]

        for key in sparkleKeys {
            if let value = bundle.object(forInfoDictionaryKey: key) {
                print("Found Sparkle key \(key) for \(bundle.bundleIdentifier ?? "unknown"): \(value)")
            }
        }

        return nil
    }

    static func isSparkleEnabled(forAppAt path: String) -> Bool {
        guard let bundle = Bundle(path: path) else { return false }

        // Check if any Sparkle framework is present
        let frameworksPath = bundle.privateFrameworksPath ?? ""
        let sparkleFramework = URL(fileURLWithPath: frameworksPath).appendingPathComponent("Sparkle.framework")

        if FileManager.default.fileExists(atPath: sparkleFramework.path) {
            return true
        }

        // Check for Sparkle keys in Info.plist
        let sparkleKeys = ["SUFeedURL", "SUPublicDSAKeyFile", "SUPublicEDKey"]
        return sparkleKeys.contains { bundle.object(forInfoDictionaryKey: $0) != nil }
    }

    static func getSparkleVersion(forAppAt path: String) -> String? {
        guard let bundle = Bundle(path: path) else { return nil }

        let frameworksPath = bundle.privateFrameworksPath ?? ""
        let sparkleBundle = Bundle(path: URL(fileURLWithPath: frameworksPath).appendingPathComponent("Sparkle.framework").path)

        return sparkleBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}