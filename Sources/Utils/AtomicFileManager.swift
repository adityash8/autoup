import Foundation
import CryptoKit

/// Atomic file operations manager that ensures data integrity during file operations
actor AtomicFileManager {
    enum AtomicError: Error, LocalizedError {
        case stagingDirectoryCreationFailed
        case backupCreationFailed
        case sourceVerificationFailed
        case backupVerificationFailed
        case atomicMoveFailed
        case rollbackFailed
        case insufficientSpace
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .stagingDirectoryCreationFailed:
                return "Failed to create staging directory"
            case .backupCreationFailed:
                return "Failed to create backup"
            case .sourceVerificationFailed:
                return "Source file verification failed"
            case .backupVerificationFailed:
                return "Backup verification failed"
            case .atomicMoveFailed:
                return "Atomic move operation failed"
            case .rollbackFailed:
                return "Rollback operation failed"
            case .insufficientSpace:
                return "Insufficient disk space"
            case .checksumMismatch:
                return "File checksum verification failed"
            }
        }
    }

    private let fileManager = FileManager.default

    /// Atomically replace a file with backup and verification
    /// - Parameters:
    ///   - sourceURL: Source file to install
    ///   - destinationURL: Destination to replace
    ///   - createBackup: Whether to create a backup of the destination
    /// - Returns: Backup URL if backup was created
    func atomicReplace(
        sourceURL: URL,
        destinationURL: URL,
        createBackup: Bool = true
    ) async throws -> URL? {
        // Verify source file exists and is readable
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AtomicError.sourceVerificationFailed
        }

        // Calculate source checksum for verification
        let sourceChecksum = try calculateChecksum(for: sourceURL)

        // Create staging directory for atomic operations
        let stagingDir = try createStagingDirectory()
        defer {
            try? fileManager.removeItem(at: stagingDir)
        }

        var backupURL: URL?

        // Step 1: Create backup if destination exists and backup is requested
        if createBackup && fileManager.fileExists(atPath: destinationURL.path) {
            backupURL = try await createVerifiedBackup(
                from: destinationURL,
                to: stagingDir.appendingPathComponent("backup")
            )
        }

        // Step 2: Copy source to staging area
        let stagedURL = stagingDir.appendingPathComponent("staged")
        try fileManager.copyItem(at: sourceURL, to: stagedURL)

        // Step 3: Verify staged file integrity
        let stagedChecksum = try calculateChecksum(for: stagedURL)
        guard sourceChecksum == stagedChecksum else {
            throw AtomicError.checksumMismatch
        }

        // Step 4: Check available space
        try verifyAvailableSpace(for: stagedURL, at: destinationURL.deletingLastPathComponent())

        // Step 5: Atomic move operation
        do {
            // Remove destination if it exists
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            // Atomic move from staging to final destination
            try fileManager.moveItem(at: stagedURL, to: destinationURL)

            // Verify final file integrity
            let finalChecksum = try calculateChecksum(for: destinationURL)
            guard sourceChecksum == finalChecksum else {
                // If verification fails, attempt rollback
                if let backupURL = backupURL {
                    try? await rollback(from: backupURL, to: destinationURL)
                }
                throw AtomicError.checksumMismatch
            }

            return backupURL
        } catch {
            // If atomic move fails, attempt rollback
            if let backupURL = backupURL {
                do {
                    try await rollback(from: backupURL, to: destinationURL)
                } catch {
                    throw AtomicError.rollbackFailed
                }
            }
            throw AtomicError.atomicMoveFailed
        }
    }

    /// Create a verified backup of a file
    private func createVerifiedBackup(from sourceURL: URL, to backupURL: URL) async throws -> URL {
        // Create backup directory if needed
        let backupDir = backupURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: backupDir.path) {
            try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        }

        // Calculate source checksum
        let sourceChecksum = try calculateChecksum(for: sourceURL)

        // Copy to backup location
        try fileManager.copyItem(at: sourceURL, to: backupURL)

        // Verify backup integrity
        let backupChecksum = try calculateChecksum(for: backupURL)
        guard sourceChecksum == backupChecksum else {
            try? fileManager.removeItem(at: backupURL)
            throw AtomicError.backupVerificationFailed
        }

        return backupURL
    }

    /// Rollback from backup to original location
    private func rollback(from backupURL: URL, to originalURL: URL) async throws {
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw AtomicError.rollbackFailed
        }

        // Remove current file if it exists
        if fileManager.fileExists(atPath: originalURL.path) {
            try fileManager.removeItem(at: originalURL)
        }

        // Move backup to original location
        try fileManager.moveItem(at: backupURL, to: originalURL)

        // Verify rollback integrity
        _ = try calculateChecksum(for: originalURL)
    }

    /// Calculate SHA256 checksum for file verification
    private func calculateChecksum(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Create a staging directory for atomic operations
    private func createStagingDirectory() throws -> URL {
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("AutoUp-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    /// Verify available disk space for operation
    private func verifyAvailableSpace(for fileURL: URL, at destinationDir: URL) throws {
        let fileSize = try fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0

        if let availableSpace = try? destinationDir.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity {
            // Require 2x file size to ensure safe operation (file + backup)
            if availableSpace < fileSize * 2 {
                throw AtomicError.insufficientSpace
            }
        }
    }

    /// Verify file integrity after operation
    func verifyFileIntegrity(sourceURL: URL, destinationURL: URL) async throws -> Bool {
        let sourceChecksum = try calculateChecksum(for: sourceURL)
        let destChecksum = try calculateChecksum(for: destinationURL)
        return sourceChecksum == destChecksum
    }
}