import Foundation
import MLX

class ChangelogSummarizer: ObservableObject {
    @Published var isProcessing = false

    private let openAIAPIKey: String?
    private let useLocalModel: Bool

    init() {
        openAIAPIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        useLocalModel = true // Prefer local model for privacy
    }

    func summarizeChangelog(_ changelog: String, for appName: String) async -> String? {
        guard !changelog.isEmpty else { return nil }

        isProcessing = true
        defer { isProcessing = false }

        // Try local MLX model first
        if useLocalModel {
            if let localSummary = await summarizeWithLocalModel(changelog, appName: appName) {
                return localSummary
            }
        }

        // Fallback to OpenAI if available
        if let apiKey = openAIAPIKey {
            return await summarizeWithOpenAI(changelog, appName: appName, apiKey: apiKey)
        }

        // Final fallback: keyword extraction
        return extractKeywordSummary(changelog, appName: appName)
    }

    private func summarizeWithLocalModel(_ changelog: String, appName: String) async -> String? {
        // Note: This is a simplified implementation
        // In practice, you'd need to load and run an MLX model
        // For now, return a placeholder to show the structure
        nil
    }

    private func summarizeWithOpenAI(_ changelog: String, appName: String, apiKey: String) async -> String? {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            print("Invalid OpenAI API URL")
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Summarize this app update changelog for \(
            appName
        ) in under 20 words. Focus on security fixes, bugs, and performance improvements. Be concise and user-friendly.

        Changelog:
        \(changelog)
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                [
                    "role": "user",
                    "content": prompt,
                ],
            ],
            "max_tokens": 50,
            "temperature": 0.3,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                print("OpenAI API error: \(response)")
                return nil
            }

            let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            return openAIResponse.choices.first?.message.content
                .trimmingCharacters(in: .whitespacesAndNewlines)

        } catch {
            print("Error calling OpenAI API: \(error)")
            return nil
        }
    }

    private func extractKeywordSummary(_ changelog: String, appName: String) -> String {
        let lowercaseChangelog = changelog.lowercased()

        var features: [String] = []

        // Security keywords
        if containsAny(
            lowercaseChangelog,
            keywords: ["security", "vulnerability", "cve", "exploit", "patch"]
        ) {
            features.append("security fixes")
        }

        // Bug fixes
        if containsAny(lowercaseChangelog, keywords: ["bug", "fix", "crash", "issue", "problem"]) {
            features.append("bug fixes")
        }

        // Performance
        if containsAny(
            lowercaseChangelog,
            keywords: ["performance", "faster", "speed", "optimization", "memory"]
        ) {
            features.append("performance improvements")
        }

        // New features
        if containsAny(lowercaseChangelog, keywords: ["new", "added", "feature", "support", "introduce"]) {
            features.append("new features")
        }

        // UI improvements
        if containsAny(lowercaseChangelog, keywords: ["ui", "interface", "design", "theme", "look"]) {
            features.append("UI improvements")
        }

        if features.isEmpty {
            return "General improvements and updates"
        } else if features.count == 1 {
            return "Includes \(features[0])"
        } else if features.count == 2 {
            return "Includes \(features[0]) and \(features[1])"
        } else {
            return "Includes \(features.dropLast().joined(separator: ", ")) and \(features.last!)"
        }
    }

    private func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

// MARK: - OpenAI Response Models

struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

struct OpenAIMessage: Codable {
    let content: String
}

// MARK: - Enhanced Update Info with AI Summaries

extension UpdateDetector {
    func enhanceWithAISummaries(_ updates: [UpdateInfo]) async -> [UpdateInfo] {
        let summarizer = ChangelogSummarizer()

        return await withTaskGroup(of: UpdateInfo.self) { group in
            for update in updates {
                group.addTask {
                    var enhancedUpdate = update

                    if let changelog = update.changelog, !changelog.isEmpty {
                        let summary = await summarizer.summarizeChangelog(changelog, for: update.appInfo.name)
                        enhancedUpdate = UpdateInfo(
                            appInfo: update.appInfo,
                            availableVersion: update.availableVersion,
                            changelog: update.changelog,
                            downloadURL: update.downloadURL,
                            isSecurityUpdate: update.isSecurityUpdate,
                            isTahoeCompatible: update.isTahoeCompatible,
                            summary: summary,
                            detectedAt: update.detectedAt
                        )
                    }

                    return enhancedUpdate
                }
            }

            var enhancedUpdates: [UpdateInfo] = []
            for await update in group {
                enhancedUpdates.append(update)
            }
            return enhancedUpdates
        }
    }
}
