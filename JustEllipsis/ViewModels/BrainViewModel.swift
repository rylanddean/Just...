import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class BrainViewModel {

    var searchText: String = ""
    var selectedTopic: String? = nil
    var rememberedEntry: BrainEntry? = nil

    // MARK: - Cached analytics (recomputed only when entry count changes)

    private(set) var cachedInsightParagraph: String = ""
    private(set) var cachedWeeklyWords: [String] = []
    private(set) var cachedStats: (kept: Double, skipped: Double, avgSeconds: Double, avgReadSeconds: Double) = (0, 0, 0, 0)
    private var cacheEntryCount: Int = -1

    func refreshCacheIfNeeded(entries: [BrainEntry]) {
        guard entries.count != cacheEntryCount else { return }
        cacheEntryCount = entries.count
        cachedWeeklyWords = weeklyDNA(entries: entries)
        cachedInsightParagraph = insightParagraph(entries: entries)
        cachedStats = reflectionStats(entries: entries)
    }

    // MARK: - Rank

    func rank(for entries: [BrainEntry]) -> BrainRank {
        BrainEngine.rank(for: entries.count)
    }

    func progressToNextRank(for entries: [BrainEntry]) -> Double {
        BrainEngine.progressToNextRank(for: entries.count)
    }

    func entriesUntilNextRank(for entries: [BrainEntry]) -> Int {
        BrainEngine.entriesUntilNextRank(for: entries.count)
    }

    // MARK: - Filtering

    func filtered(_ entries: [BrainEntry]) -> [BrainEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty || selectedTopic != nil else { return entries }

        var result = entries

        if !q.isEmpty {
            result = result.filter { entry in
                entry.title.lowercased().contains(q)
                || entry.domain.lowercased().contains(q)
                || (entry.reflection?.lowercased().contains(q) == true)
            }
        }

        if let topic = selectedTopic {
            let t = topic.lowercased()
            result = result.filter { entry in
                entry.title.lowercased().contains(t)
                || (entry.reflection?.lowercased().contains(t) == true)
                || (entry.dna?.lowercased().contains(t) == true)
            }
        }

        return result
    }

    func toggleTopic(_ topic: String) {
        selectedTopic = selectedTopic == topic ? nil : topic
    }

    // MARK: - Remember This

    /// Picks one older entry (> 14 days), preferring entries with reflections.
    /// Only sets once per view lifetime.
    func setRememberedEntry(from entries: [BrainEntry]) {
        guard rememberedEntry == nil, entries.count > 10 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let older = entries.filter { $0.readAt < cutoff }
        let withReflection = older.filter { !($0.reflection ?? "").isEmpty }
        rememberedEntry = (withReflection.isEmpty ? older : withReflection).randomElement()
    }

    // MARK: - Insights

    func insightParagraph(entries: [BrainEntry]) -> String {
        let activity = monthlyActivity(entries: entries)
        let activeDays = activity.filter { $0 }.count
        let domains = topDomains(entries: entries)
        let stats = reflectionStats(entries: entries)
        let weekWords = weeklyDNA(entries: entries)

        guard activeDays > 0 else {
            return "No reading in the last 28 days."
        }

        var sentences: [String] = []

        // Reading cadence + source
        var opening = activeDays == 28
            ? "You've read every day this month"
            : "You've read on \(activeDays) of the last 28 days"
        let topTwo = domains.prefix(2).map(\.domain)
        switch topTwo.count {
        case 2:  opening += ", mostly from \(topTwo[0]) and \(topTwo[1])."
        case 1:  opening += ", mostly from \(topTwo[0])."
        default: opening += "."
        }
        sentences.append(opening)

        // Weekly topics
        if !weekWords.isEmpty {
            sentences.append("This week you've been drawn to \(naturalJoin(Array(weekWords.prefix(3)))).")
        }

        // Reflection depth
        let pct = Int(stats.kept * 100)
        if pct == 100 {
            let avg = formatAvgSeconds(stats.avgSeconds)
            sentences.append("You reflected on everything you read\(avg.isEmpty ? "." : " — about \(avg) per piece.")")
        } else if pct > 0 {
            let avg = formatAvgSeconds(stats.avgSeconds)
            sentences.append("You reflected on \(pct)% of what you read\(avg.isEmpty ? "." : " — about \(avg) per piece.")")
        }

        return sentences.joined(separator: " ")
    }

    private func naturalJoin(_ words: [String]) -> String {
        switch words.count {
        case 0: return ""
        case 1: return words[0]
        case 2: return "\(words[0]) and \(words[1])"
        default: return words.dropLast().joined(separator: ", ") + ", and " + words[words.count - 1]
        }
    }

    private func formatAvgSeconds(_ seconds: Double) -> String {
        guard seconds > 0 else { return "" }
        if seconds < 60 { return "\(Int(seconds))s" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return s > 0 ? "\(m)m \(s)s" : "\(m)m"
    }

    func weeklyDNA(entries: [BrainEntry]) -> [String] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekEntries = entries.filter { $0.readAt >= cutoff }
        guard weekEntries.count >= 3 else { return [] }
        var freq: [String: Int] = [:]
        for word in dnaWords(from: weekEntries) { freq[word, default: 0] += 1 }
        return freq.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(5).map(\.key)
    }

    func reflectionStats(entries: [BrainEntry]) -> (kept: Double, skipped: Double, avgSeconds: Double, avgReadSeconds: Double) {
        guard !entries.isEmpty else { return (0, 0, 0, 0) }
        let reflected = entries.filter { !($0.reflection ?? "").isEmpty }
        let withReadTime = entries.filter { $0.readingSeconds > 0 }
        let kept = Double(reflected.count) / Double(entries.count)
        let avg = reflected.isEmpty ? 0.0
            : Double(reflected.map(\.reflectionSeconds).reduce(0, +)) / Double(reflected.count)
        let avgRead = withReadTime.isEmpty ? 0.0
            : Double(withReadTime.map(\.readingSeconds).reduce(0, +)) / Double(withReadTime.count)
        return (kept, 1 - kept, avg, avgRead)
    }

    func topDomains(entries: [BrainEntry]) -> [(domain: String, count: Int)] {
        var freq: [String: Int] = [:]
        for entry in entries { freq[entry.domain, default: 0] += 1 }
        return freq.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3).map { (domain: $0.key, count: $0.value) }
    }

    /// Returns 28 booleans: index 0 = 27 days ago, index 27 = today.
    func monthlyActivity(entries: [BrainEntry]) -> [Bool] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<28).map { offset in
            guard let day = calendar.date(byAdding: .day, value: -(27 - offset), to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
            return entries.contains { $0.readAt >= day && $0.readAt < next }
        }
    }

    // Legacy — kept for compatibility
    func weeklyActivity(entries: [BrainEntry]) -> [Bool] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: -(6 - offset), to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
            return entries.contains { $0.readAt >= day && $0.readAt < next }
        }
    }

    func allTimeDNA(entries: [BrainEntry]) -> [(word: String, count: Int)] {
        var freq: [String: Int] = [:]
        for word in dnaWords(from: entries) { freq[word, default: 0] += 1 }
        return freq.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(12).map { (word: $0.key, count: $0.value) }
    }

    private func dnaWords(from entries: [BrainEntry]) -> [String] {
        entries.compactMap(\.dna)
            .flatMap { $0.components(separatedBy: " · ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
