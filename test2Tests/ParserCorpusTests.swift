#if canImport(Testing)
import Foundation
import Testing
import UIKit
@testable import ParkSignal_AI

/// Anchors `Bundle(for:)` to the test bundle, where `Corpus/` files are copied.
private final class CorpusBundleAnchor {}

/// Real-world parking signs with the rules they actually mean. See `Corpus/README.md`.
struct SignCorpus: Decodable {
    struct Rule: Decodable {
        let type: AIRestrictionType
        let days: [Int]
        let start: String?
        let end: String?
        let durationMinutes: Int?
        let exceptHolidays: Bool?
    }

    struct Entry: Decodable {
        let id: String
        let source: String
        let ocrText: String?
        let image: String?
        let expected: [Rule]
        let knownFailing: Bool
        let notes: String?
    }

    let entries: [Entry]

    static func load() throws -> SignCorpus {
        let bundle = Bundle(for: CorpusBundleAnchor.self)
        let url = bundle.url(forResource: "sign_corpus", withExtension: "json")
            ?? bundle.url(forResource: "sign_corpus", withExtension: "json", subdirectory: "Corpus")
        let found = try #require(url, "sign_corpus.json is not in the test bundle")
        return try JSONDecoder().decode(SignCorpus.self, from: Data(contentsOf: found))
    }
}

/// Runs the on-device parser over the whole corpus, prints per-sign results and overall
/// accuracy, and fails on any sign not marked `knownFailing` that no longer parses correctly.
@MainActor
@Suite("Parser accuracy corpus")
struct ParserCorpusTests {

    /// Comparable form of one rule: empty days = every day; no window = "00:00"-"00:00".
    private struct Normalized: Equatable, CustomStringConvertible {
        let type: String
        let days: [Int]
        let start: String
        let end: String
        let duration: Int?
        let holidays: Bool?

        init(type: AIRestrictionType, days: [Int], start: String?, end: String?, duration: Int?, holidays: Bool?) {
            self.type = type.rawValue
            let valid = Set(days.filter { (0...6).contains($0) })
            self.days = valid.isEmpty ? Array(0...6) : valid.sorted()
            let s = start ?? "00:00"
            var e = end ?? "00:00"
            if s == "00:00", e == "23:59" || e == "24:00" { e = "00:00" }
            self.start = s
            self.end = e
            self.duration = duration
            self.holidays = holidays
        }

        var sortKey: String { "\(type)|\(start)|\(end)|\(days)" }
        var description: String {
            var parts = ["\(type) \(days) \(start)-\(end)"]
            if let duration { parts.append("\(duration)min") }
            if holidays == true { parts.append("exc.holidays") }
            return parts.joined(separator: " ")
        }

        /// `expected.duration`/`holidays` are only checked when the corpus specifies them.
        func matches(expected: Normalized) -> Bool {
            type == expected.type && days == expected.days && start == expected.start && end == expected.end
                && (expected.duration == nil || duration == expected.duration)
                && (expected.holidays == nil || (holidays ?? false) == expected.holidays)
        }
    }

    private func matches(expected: [Normalized], actual: [Normalized]) -> Bool {
        guard expected.count == actual.count else { return false }
        let e = expected.sorted { $0.sortKey < $1.sortKey }
        let a = actual.sorted { $0.sortKey < $1.sortKey }
        return zip(a, e).allSatisfy { $0.matches(expected: $1) }
    }

    private func ocrText(for entry: SignCorpus.Entry) async throws -> String {
        if let image = entry.image {
            let name = (image as NSString).deletingPathExtension
            let ext = (image as NSString).pathExtension
            let bundle = Bundle(for: CorpusBundleAnchor.self)
            let path = try #require(bundle.path(forResource: name, ofType: ext), "missing corpus image \(image)")
            let uiImage = try #require(UIImage(contentsOfFile: path), "unreadable corpus image \(image)")
            return try await VisionOCRService().recognizeText(in: uiImage)
        }
        return try #require(entry.ocrText, "\(entry.id) has neither ocrText nor image")
    }

    @Test("Corpus accuracy report and regression guard")
    func corpusAccuracy() async throws {
        let corpus = try SignCorpus.load()
        #expect(!corpus.entries.isEmpty)
        let parser = ParkingTextParser()

        var passed = 0
        var regressions: [String] = []
        var nowPassing: [String] = []

        for entry in corpus.entries {
            let text = try await ocrText(for: entry)
            let actual = parser.analyze(ocrText: text).restrictions.map {
                Normalized(type: $0.type, days: $0.daysOfWeek, start: $0.startTime, end: $0.endTime,
                           duration: $0.durationMinutes, holidays: $0.exceptHolidays)
            }
            let expected = entry.expected.map {
                Normalized(type: $0.type, days: $0.days, start: $0.start, end: $0.end,
                           duration: $0.durationMinutes, holidays: $0.exceptHolidays)
            }
            let ok = matches(expected: expected, actual: actual)
            if ok { passed += 1 }
            if !ok && !entry.knownFailing { regressions.append(entry.id) }
            if ok && entry.knownFailing { nowPassing.append(entry.id) }

            let flag = ok ? "PASS" : (entry.knownFailing ? "KNOWN" : "FAIL")
            print("CORPUS|\(flag)|\(entry.id)|expected: \(expected.map(\.description).joined(separator: "; "))|actual: \(actual.map(\.description).joined(separator: "; "))")
        }

        let total = corpus.entries.count
        let pct = total == 0 ? 0 : Double(passed) / Double(total) * 100
        print(String(format: "CORPUS|SUMMARY|%d/%d signs parsed correctly (%.1f%%)", passed, total, pct))
        if !nowPassing.isEmpty {
            print("CORPUS|NOW-PASSING|mark these knownFailing=false: \(nowPassing.joined(separator: ", "))")
        }

        #expect(regressions.isEmpty, "Parser regressed on: \(regressions.joined(separator: ", "))")
    }
}
#endif
