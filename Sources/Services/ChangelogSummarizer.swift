import Foundation
import MLX

class ChangelogSummarizer: ObservableObject {
    @Published var isProcessing = false

    private let openAIAPIKey: String?
    private let useLocalModel: Bool

    init() {
        self.openAIAPIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        self.useLocalModel = true // Prefer local model for privacy
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
        // Enhanced heuristic-based local summarization
        return await heuristicSummarize(changelog)
    }

    private func heuristicSummarize(_ text: String) async -> String {
        let cleanText = text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\*+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "#+", with: "", options: .regularExpression)

        let lines = cleanText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let joined = lines.prefix(6).joined(separator: " ")

        // Security keywords (highest priority)
        let securityKeywords = [
            "cve", "security", "vulnerability", "exploit", "patch",
            "malware", "breach", "unauthorized", "privilege escalation"
        ]

        // Bug keywords
        let bugKeywords = [
            "bug", "fix", "crash", "freeze", "hang", "error",
            "issue", "problem", "resolve", "correct"
        ]

        // Performance keywords
        let performanceKeywords = [
            "performance", "speed", "faster", "optimization", "memory",
            "cpu", "battery", "efficiency", "responsive"
        ]

        let lowerText = joined.lowercased()

        // Priority: Security > Bugs > Performance > Generic
        if securityKeywords.contains(where: { lowerText.contains($0) }) {
            return "Security fix and stability improvements."
        }

        if bugKeywords.contains(where: { lowerText.contains($0) }) {
            return "Bug fixes and performance improvements."
        }

        if performanceKeywords.contains(where: { lowerText.contains($0) }) {
            return "Performance improvements and optimizations."
        }

        // Extract first meaningful sentence
        let sentences = joined.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        for sentence in sentences.prefix(3) {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 10 && trimmed.count < 120 {
                return trimmed + "."
            }
        }

        // Fallback: truncate to reasonable length
        let truncated = String(joined.prefix(140))
        return truncated.hasSuffix(" ") ? String(truncated.dropLast()) : truncated
    }

    private func summarizeWithOpenAI(_ changelog: String, appName: String, apiKey: String) async -> String? {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Summarize this app update changelog for \(appName) in under 20 words. Focus on security fixes, bugs, and performance improvements. Be concise and user-friendly.

        Changelog:
        \(changelog)
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": 50,
            "temperature": 0.3
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("OpenAI API error: \(response)")
                return nil
            }

            let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            return openAIResponse.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)

        } catch {
            print("Error calling OpenAI API: \(error)")
            return nil
        }
    }

    private func extractKeywordSummary(_ changelog: String, appName: String) -> String {
        let lowercaseChangelog = changelog.lowercased()

        var features: [String] = []

        // Security keywords
        if containsAny(lowercaseChangelog, keywords: ["security", "vulnerability", "cve", "exploit", "patch"]) {
            features.append("security fixes")
        }

        // Bug fixes
        if containsAny(lowercaseChangelog, keywords: ["bug", "fix", "crash", "issue", "problem"]) {
            features.append("bug fixes")
        }

        // Performance
        if containsAny(lowercaseChangelog, keywords: ["performance", "faster", "speed", "optimization", "memory"]) {
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
        return keywords.contains { text.contains($0) }
    }

    func extractSecurityInfo(_ text: String) -> SecurityInfo {
        let lowerText = text.lowercased()

        // Extract CVE numbers
        let cvePattern = #"cve-\d{4}-\d{4,7}"#
        let cveRegex = try? NSRegularExpression(pattern: cvePattern, options: .caseInsensitive)

        var cves: [String] = []
        if let regex = cveRegex {
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            cves = matches.compactMap { match in
                guard let range = Range(match.range, in: text) else { return nil }
                return String(text[range]).uppercased()
            }
        }

        // Determine severity
        let severityKeywords: [String: SecuritySeverity] = [
            "critical": .critical,
            "high": .high,
            "medium": .medium,
            "moderate": .medium,
            "low": .low,
            "important": .high,
            "severe": .critical
        ]

        var severity: SecuritySeverity = .unknown
        for (keyword, level) in severityKeywords {
            if lowerText.contains(keyword) {
                if level.rawValue > severity.rawValue {
                    severity = level
                }
            }
        }

        let hasSecurityContent = [
            "security", "vulnerability", "exploit", "cve", "patch",
            "malware", "unauthorized", "privilege"
        ].contains { lowerText.contains($0) }

        return SecurityInfo(
            hasSecurity: hasSecurityContent,
            severity: severity,
            cves: cves
        )
    }

    struct SecurityInfo {
        let hasSecurity: Bool
        let severity: SecuritySeverity
        let cves: [String]
    }

    enum SecuritySeverity: Int, CaseIterable {
        case unknown = 0
        case low = 1
        case medium = 2
        case high = 3
        case critical = 4

        var displayName: String {
            switch self {
            case .unknown: return "Unknown"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .critical: return "Critical"
            }
        }

        var color: String {
            switch self {
            case .unknown: return "gray"
            case .low: return "green"
            case .medium: return "yellow"
            case .high: return "orange"
            case .critical: return "red"
            }
        }
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