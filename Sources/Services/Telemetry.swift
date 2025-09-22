import Foundation
import PostHog

enum Telemetry {
    static func configure(enabled: Bool, apiKey: String) {
        if enabled {
            let config = PostHogConfig(apiKey: apiKey)
            config.host = "https://app.posthog.com"
            PostHogSDK.shared.setup(config)
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }

    static func track(_ name: String, props: [String: Any] = [:]) {
        guard UserDefaults.standard.bool(forKey: "telemetry_enabled") else { return }
        PostHogSDK.shared.capture(name, properties: props)
    }

    // Bias-driven events for measuring UX improvements
    static func trackBiasEvent(_ biasType: String, action: String, value: Any? = nil) {
        var props: [String: Any] = [
            "bias_type": biasType,
            "action": action,
        ]
        if let value {
            props["value"] = value
        }
        track("bias_interaction", props: props)
    }
}

// Usage examples:
// Telemetry.trackBiasEvent("anchoring", "pricing_viewed", "yearly_selected")
// Telemetry.trackBiasEvent("loss_aversion", "security_warning_shown", securityCount)
// Telemetry.trackBiasEvent("social_proof", "user_count_viewed", 3218)
