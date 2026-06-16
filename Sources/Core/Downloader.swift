import Foundation
import CryptoKit

actor Downloader: NSObject {
    private var activeDownloads: [URL: DownloadTask] = [:]
    private let session: URLSession

    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        super.init()
    }

    func download(_ url: URL, to destination: URL, expectedSize: Int64? = nil, expectedChecksum: String? = nil, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {

        // Check if download already in progress
        if let existingTask = activeDownloads[url] {
            return try await existingTask.result.value
        }

        // Create new download task
        let task = DownloadTask(url: url, destination: destination, expectedSize: expectedSize, expectedChecksum: expectedChecksum)
        activeDownloads[url] = task

        defer {
            activeDownloads.removeValue(forKey: url)
        }

        do {
            let finalURL = try await performDownload(task: task, progress: progress)
            task.result.resume(returning: finalURL)
            return finalURL
        } catch {
            task.result.resume(throwing: error)
            throw error
        }
    }

    private func performDownload(task: DownloadTask, progress: @escaping @Sendable (DownloadProgress) -> Void) async throws -> URL {
        // Ensure destination directory exists
        let destinationDir = task.destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        // Start download
        let (tempURL, response) = try await session.download(from: task.url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw DownloadError.httpError(httpResponse.statusCode)
        }

        // Verify content length if provided
        if let expectedSize = task.expectedSize {
            let actualSize = httpResponse.expectedContentLength
            if actualSize != expectedSize && actualSize != -1 {
                throw DownloadError.sizeMismatch(expected: expectedSize, actual: actualSize)
            }
        }

        // Verify checksum if provided
        if let expectedChecksum = task.expectedChecksum {
            let actualChecksum = try calculateSHA256(for: tempURL)
            if actualChecksum != expectedChecksum {
                throw DownloadError.checksumMismatch(expected: expectedChecksum, actual: actualChecksum)
            }
        }

        // Move to final destination
        if FileManager.default.fileExists(atPath: task.destination.path) {
            try FileManager.default.removeItem(at: task.destination)
        }

        try FileManager.default.moveItem(at: tempURL, to: task.destination)

        // Final progress update
        let fileSize = try FileManager.default.attributesOfItem(atPath: task.destination.path)[.size] as? Int64 ?? 0
        let finalProgress = DownloadProgress(
            bytesDownloaded: fileSize,
            totalBytes: fileSize,
            percentage: 1.0,
            status: .completed
        )
        progress(finalProgress)

        return task.destination
    }

    private func calculateSHA256(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    func cancelDownload(_ url: URL) {
        activeDownloads.removeValue(forKey: url)
    }

    func cancelAllDownloads() {
        activeDownloads.removeAll()
    }
}

// MARK: - Supporting Types

class DownloadTask {
    let url: URL
    let destination: URL
    let expectedSize: Int64?
    let expectedChecksum: String?
    let result: CheckedContinuation<URL, Error>

    init(url: URL, destination: URL, expectedSize: Int64?, expectedChecksum: String?) {
        self.url = url
        self.destination = destination
        self.expectedSize = expectedSize
        self.expectedChecksum = expectedChecksum
        self.result = CheckedContinuation<URL, Error>()
    }
}

struct DownloadProgress: Sendable {
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let percentage: Double
    let status: DownloadStatus

    var formattedBytesDownloaded: String {
        ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
    }

    var formattedTotalBytes: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var formattedProgress: String {
        "\(formattedBytesDownloaded) / \(formattedTotalBytes)"
    }
}

enum DownloadStatus: Sendable {
    case waiting
    case downloading
    case completed
    case failed(Error)
    case cancelled
}

enum DownloadError: LocalizedError, Sendable {
    case invalidResponse
    case httpError(Int)
    case sizeMismatch(expected: Int64, actual: Int64)
    case checksumMismatch(expected: String, actual: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .sizeMismatch(let expected, let actual):
            return "File size mismatch - expected \(expected), got \(actual)"
        case .checksumMismatch(let expected, let actual):
            return "Checksum verification failed - expected \(expected), got \(actual)"
        case .cancelled:
            return "Download was cancelled"
        }
    }
}

// MARK: - URLSessionDownloadDelegate for Progress Tracking

extension Downloader: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {

        let progress = DownloadProgress(
            bytesDownloaded: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : totalBytesWritten,
            percentage: totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0,
            status: .downloading
        )

        // Find the associated task and call its progress handler
        // Note: This requires refactoring to store progress handlers per task
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handle completion
    }
}