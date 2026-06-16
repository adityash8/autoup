import Foundation

// Actor-Observer bias: Frame errors as situational, not user failures
struct UpdateError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }

    static func friendly(_ error: Error) -> UpdateError {
        let description = String(describing: error).lowercased()

        // Use Actor-Observer bias: blame the situation, not the user
        if description.contains("codesign") || description.contains("signature") {
            return UpdateError(reason: "Looks like the app's signature couldn't be verified. Your previous version is safe. Try installing manually from the developer.")
        }

        if description.contains("permission") || description.contains("access") {
            return UpdateError(reason: "Auto-Up needs permission to replace the app. Grant Full Disk Access in Settings → Privacy & Security → Privacy.")
        }

        if description.contains("network") || description.contains("timeout") {
            return UpdateError(reason: "Network seems slow — we'll retry in 2 minutes. Your apps are still protected.")
        }

        if description.contains("disk") || description.contains("space") {
            return UpdateError(reason: "Looks like disk space is running low. Free up some space and try again.")
        }

        if description.contains("dmg") || description.contains("mount") {
            return UpdateError(reason: "The download file seems corrupted. We'll try downloading again automatically.")
        }

        // Default friendly message
        return UpdateError(reason: "Update temporarily unavailable. We've kept your previous version safe. You can retry or update manually.")
    }
}