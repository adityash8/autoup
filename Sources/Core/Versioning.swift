import Foundation

enum Versioning {
    // Numeric-aware compare: "1.10" > "1.9", strips leading "v"
    static func isNewer(_ latest: String, than current: String) -> Bool {
        let a = latest.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let b = current.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        return a.compare(b, options: [.numeric, .caseInsensitive]) == .orderedDescending
    }
}