import Foundation

struct GitHub {
    struct Release: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let published_at: String?
        let assets: [Asset]
    }

    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let content_type: String
        let size: Int
    }

    static func latest(owner: String, repo: String, token: String? = nil) async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AutoUp/1.0", forHTTPHeaderField: "User-Agent")

        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 403 {
            throw GitHubError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw GitHubError.apiError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(Release.self, from: data)
    }

    static func releases(owner: String, repo: String, count: Int = 10, token: String? = nil) async throws -> [Release] {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=\(count)")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AutoUp/1.0", forHTTPHeaderField: "User-Agent")

        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([Release].self, from: data)
    }

    enum GitHubError: LocalizedError {
        case rateLimited
        case apiError(Int)
        case invalidRepo

        var errorDescription: String? {
            switch self {
            case .rateLimited:
                return "GitHub API rate limit exceeded"
            case .apiError(let code):
                return "GitHub API error: \(code)"
            case .invalidRepo:
                return "Invalid GitHub repository"
            }
        }
    }
}