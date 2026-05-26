import SwiftUI
import SwiftData

// MARK: - Brain Diet Panel

struct BrainDietPanel: View {
    let entries: [BrainEntry]
    let viewModel: BrainViewModel

    @AppStorage("brainDietExpanded") private var isExpanded: Bool = false
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Text("WHAT YOU'VE BEEN READING")
                        .font(AppTheme.sansSerif(10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(appTheme.accent)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(appTheme.accent)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 10) {
                    let weeklyWords = viewModel.weeklyDNA(entries: entries)
                    if !weeklyWords.isEmpty {
                        WeeklyDNACard(words: weeklyWords)
                    }

                    let stats = viewModel.reflectionStats(entries: entries)
                    ReflectionStatsCard(kept: stats.kept, skipped: stats.skipped, avgSeconds: stats.avgSeconds)

                    let domains = viewModel.topDomains(entries: entries)
                    if !domains.isEmpty {
                        TopDomainsCard(domains: domains)
                    }

                    WeeklyActivityCard(activity: viewModel.weeklyActivity(entries: entries))

                    if entries.count >= 50 {
                        let allWords = viewModel.allTimeDNA(entries: entries)
                        if !allWords.isEmpty {
                            AllTimeDNACard(words: allWords)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Card Container

private struct DietCard<Content: View>: View {
    @Environment(\.appTheme) private var appTheme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .strokeBorder(appTheme.accent.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Section Label

private struct DietLabel: View {
    let text: String
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Text(text)
            .font(AppTheme.sansSerif(10, weight: .medium))
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(appTheme.accent)
    }
}

// MARK: - Weekly DNA Card

private struct WeeklyDNACard: View {
    let words: [String]
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        DietCard {
            DietLabel(text: "Reading This Week")
            FlowLayout(spacing: 8) {
                ForEach(words, id: \.self) { word in
                    Text(word)
                        .font(AppTheme.sansSerif(13))
                        .foregroundStyle(appTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(appTheme.accent.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

// MARK: - Reflection Stats Card

private struct ReflectionStatsCard: View {
    let kept: Double
    let skipped: Double
    let avgSeconds: Double
    @Environment(\.appTheme) private var appTheme

    private var formattedAvg: String {
        guard avgSeconds > 0 else { return "—" }
        if avgSeconds < 60 { return "\(Int(avgSeconds))s" }
        let m = Int(avgSeconds) / 60
        let s = Int(avgSeconds) % 60
        return "\(m)m \(s)s"
    }

    var body: some View {
        DietCard {
            DietLabel(text: "Reflections")
            HStack(alignment: .top) {
                statCell(label: "Kept", value: "\(Int(kept * 100))%")
                Spacer()
                statCell(label: "Skipped", value: "\(Int(skipped * 100))%")
                Spacer()
                statCell(label: "Avg. time", value: formattedAvg)
            }
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(value)
                .font(AppTheme.serif(22))
                .foregroundStyle(appTheme.heading)
            Text(label)
                .font(AppTheme.sansSerif(10))
                .foregroundStyle(appTheme.textFaint)
        }
    }
}

// MARK: - Top Domains Card

private struct TopDomainsCard: View {
    let domains: [(domain: String, count: Int)]
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        DietCard {
            DietLabel(text: "Your Sources")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(domains.enumerated()), id: \.offset) { i, item in
                    HStack(spacing: 12) {
                        Text("\(i + 1)")
                            .font(AppTheme.sansSerif(11))
                            .foregroundStyle(appTheme.textFaint)
                            .frame(width: 12, alignment: .leading)
                        Text(item.domain)
                            .font(AppTheme.sansSerif(13, weight: .medium))
                            .foregroundStyle(appTheme.text)
                        Spacer()
                        Text("\(item.count) \(item.count == 1 ? "entry" : "entries")")
                            .font(AppTheme.sansSerif(11))
                            .foregroundStyle(appTheme.textFaint)
                    }
                }
            }
        }
    }
}

// MARK: - Weekly Activity Card

private struct WeeklyActivityCard: View {
    let activity: [Bool]
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        DietCard {
            DietLabel(text: "Last 7 Days")
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(activity[i] ? appTheme.accent : appTheme.accent.opacity(0.1))
                            .frame(height: 28)
                        Text(dayLetter(for: i))
                            .font(AppTheme.sansSerif(9))
                            .foregroundStyle(appTheme.textFaint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func dayLetter(for offset: Int) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let date = calendar.date(byAdding: .day, value: -(6 - offset), to: today) else { return "" }
        let weekday = calendar.component(.weekday, from: date)
        return ["S", "M", "T", "W", "T", "F", "S"][weekday - 1]
    }
}

// MARK: - All-Time DNA Card

private struct AllTimeDNACard: View {
    let words: [(word: String, count: Int)]
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        DietCard {
            DietLabel(text: "Your Brain Over Time")
            FlowLayout(spacing: 10) {
                ForEach(words, id: \.word) { item in
                    Text(item.word)
                        .font(AppTheme.serif(fontSize(for: item.count)))
                        .foregroundStyle(appTheme.text.opacity(opacity(for: item.count)))
                }
            }
        }
    }

    private var maxCount: Int { words.first?.count ?? 1 }
    private var minCount: Int { words.last?.count ?? 1 }

    private func fontSize(for count: Int) -> CGFloat {
        guard maxCount > minCount else { return 20 }
        let ratio = Double(count - minCount) / Double(maxCount - minCount)
        return 13 + CGFloat(ratio) * 19   // 13pt → 32pt
    }

    private func opacity(for count: Int) -> Double {
        guard maxCount > minCount else { return 1.0 }
        let ratio = Double(count - minCount) / Double(maxCount - minCount)
        return 0.5 + ratio * 0.5
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 {
                y += lineH + spacing
                x = 0
                lineH = 0
            }
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        return CGSize(width: width, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        var line: [(Subviews.Element, CGPoint)] = []
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX {
                line.forEach { $0.0.place(at: $0.1, proposal: .unspecified) }
                line = []
                y += lineH + spacing
                x = bounds.minX
                lineH = 0
            }
            line.append((sv, CGPoint(x: x, y: y)))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        line.forEach { $0.0.place(at: $0.1, proposal: .unspecified) }
    }
}
