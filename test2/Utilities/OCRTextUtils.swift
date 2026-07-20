import Foundation

/// Utilities for working with OCR text produced by on-device Vision or server AI.
///
/// Responsibilities:
/// - Normalize whitespace and trim noise
/// - Merge multi-photo OCR runs into a single readable block
/// - Deduplicate identical lines while preserving original order
enum OCRTextUtils {
    /// Normalize a single OCR line by collapsing internal whitespace to a single space.
    static func normalizeLine(_ line: String) -> String {
        line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Merge an array of OCR text blocks, split into lines, normalize, and deduplicate.
    /// - Parameter blocks: Array of OCR text blocks (one per photo in a session).
    /// - Returns: A single string with unique lines joined by newlines.
    static func mergeAndDeduplicate(blocks: [String]) -> String {
        let lines = blocks
            .joined(separator: "\n")
            .components(separatedBy: .newlines)
            .map { normalizeLine($0) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        var result: [String] = []
        for l in lines {
            // Use normalized value for de-dupe while preserving original text form
            let key = l.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                result.append(l)
            }
        }
        return result.joined(separator: "\n")
    }
}
