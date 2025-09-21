import Foundation

enum Brew {
    static func caskIsOutdated(_ cask: String) -> Bool {
        let command = "brew outdated --cask --greedy --quiet | grep -x \(shellQuote(cask))"
        return run(command).exitCode == 0
    }

    static func guessCask(from appName: String) -> String {
        return appName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "")
    }

    static func getCaskInfo(_ cask: String) -> CaskInfo? {
        let result = run("brew info --cask \(shellQuote(cask)) --json")
        guard result.exitCode == 0,
              let data = result.output.data(using: .utf8) else {
            return nil
        }

        do {
            let casks = try JSONDecoder().decode([CaskInfo].self, from: data)
            return casks.first
        } catch {
            return nil
        }
    }

    static func updateCask(_ cask: String) -> Bool {
        let result = run("brew upgrade --cask \(shellQuote(cask))")
        return result.exitCode == 0
    }

    static func isBrewInstalled() -> Bool {
        return run("command -v brew").exitCode == 0
    }

    struct CaskInfo: Decodable {
        let token: String
        let full_name: String
        let tap: String
        let version: String
        let installed: String?
        let outdated: Bool
        let homepage: String?
        let url: String
        let name: [String]
        let desc: String?
    }

    private static func run(_ command: String) -> (exitCode: Int32, output: String) {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-lc", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return (task.terminationStatus, output)
        } catch {
            return (-1, "")
        }
    }

    private static func shellQuote(_ string: String) -> String {
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}