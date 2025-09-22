import Foundation

/// Safe process execution utility that prevents shell injection vulnerabilities
actor SafeProcess {
    enum ProcessError: Error, LocalizedError {
        case invalidExecutablePath
        case executionFailed(Int32)
        case timeout
        case invalidArguments
        case processNotFound

        var errorDescription: String? {
            switch self {
            case .invalidExecutablePath:
                return "Invalid executable path"
            case .executionFailed(let code):
                return "Process failed with exit code: \(code)"
            case .timeout:
                return "Process execution timed out"
            case .invalidArguments:
                return "Invalid process arguments"
            case .processNotFound:
                return "Required process not found"
            }
        }
    }

    /// Validated executable paths to prevent arbitrary command execution
    private static let allowedExecutables: [String: String] = [
        "brew": "/opt/homebrew/bin/brew",
        "installer": "/usr/sbin/installer",
        "unzip": "/usr/bin/unzip",
        "zip": "/usr/bin/zip",
        "hdiutil": "/usr/bin/hdiutil",
        "codesign": "/usr/bin/codesign",
        "spctl": "/usr/sbin/spctl",
        "mas": "/opt/homebrew/bin/mas"
    ]

    /// Execute a process safely with input validation and timeout
    /// - Parameters:
    ///   - executable: The name of the executable (must be in allowedExecutables)
    ///   - arguments: The arguments to pass (will be validated)
    ///   - timeout: Maximum execution time in seconds (default: 60)
    ///   - workingDirectory: Working directory URL (optional)
    /// - Returns: ProcessResult containing stdout, stderr, and exit code
    func execute(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 60,
        workingDirectory: URL? = nil
    ) async throws -> ProcessResult {
        // Validate executable
        guard let executablePath = Self.allowedExecutables[executable] else {
            throw ProcessError.invalidExecutablePath
        }

        // Validate executable exists
        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw ProcessError.processNotFound
        }

        // Validate arguments
        let sanitizedArguments = try sanitizeArguments(arguments)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = sanitizedArguments

        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()

                    // Set up timeout
                    let timeoutWorkItem = DispatchWorkItem {
                        if process.isRunning {
                            process.terminate()
                            continuation.resume(throwing: ProcessError.timeout)
                        }
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

                    process.waitUntilExit()
                    timeoutWorkItem.cancel()

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let result = ProcessResult(
                        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8) ?? "",
                        exitCode: process.terminationStatus
                    )

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: ProcessError.executionFailed(process.terminationStatus))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Sanitize arguments to prevent injection attacks
    private func sanitizeArguments(_ arguments: [String]) throws -> [String] {
        return arguments.map { argument in
            // Remove dangerous characters and control sequences
            let dangerous = CharacterSet(charactersIn: ";|&$`(){}[]<>*?~")
            let cleaned = argument.components(separatedBy: dangerous).joined()

            // Validate that the argument doesn't contain shell metacharacters
            guard !argument.contains("$(") && !argument.contains("`") && !argument.contains("||") && !argument.contains("&&") else {
                return ""
            }

            return cleaned
        }.filter { !$0.isEmpty }
    }

    /// Check if an executable is available
    func isExecutableAvailable(_ executable: String) -> Bool {
        guard let path = Self.allowedExecutables[executable] else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}

struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var isSuccess: Bool {
        return exitCode == 0
    }
}