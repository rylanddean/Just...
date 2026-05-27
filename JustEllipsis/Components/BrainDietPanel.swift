import SwiftUI

struct BrainDietPanel: View {
    let entries: [BrainEntry]
    let viewModel: BrainViewModel
    let selectedTopic: String?
    let onTopicSelected: (String) -> Void

    @Environment(\.appTheme) private var appTheme

    private var weeklyWords: [String] { viewModel.weeklyDNA(entries: entries) }
    private var stats: (kept: Double, skipped: Double, avgSeconds: Double) {
        viewModel.reflectionStats(entries: entries)
    }
    private var domains: [(domain: String, count: Int)] { viewModel.topDomains(entries: entries) }
    private var activity: [Bool] { viewModel.monthlyActivity(entries: entries) }
    private var activeDays: Int { activity.filter { $0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryRow

            if !weeklyWords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    label("THIS WEEK")
                    FlowLayout(spacing: 6) {
                        ForEach(weeklyWords, id: \.self) { word in
                            let isSelected = selectedTopic == word
                            Button {
                                onTopicSelected(word)
                            } label: {
                                Text(word)
                                    .font(AppTheme.sansSerif(12, weight: .medium))
                                    .foregroundStyle(isSelected ? (appTheme.isLight ? .white : appTheme.background) : appTheme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        isSelected ? appTheme.accent : appTheme.accent.opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: isSelected)
                        }
                    }
                }
            }

            if !domains.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    label("TOP SOURCES")
                    VStack(spacing: 6) {
                        ForEach(Array(domains.prefix(3).enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(AppTheme.sansSerif(11))
                                    .foregroundStyle(appTheme.textFaint)
                                    .frame(width: 12, alignment: .leading)

                                Text(item.domain)
                                    .font(AppTheme.sansSerif(13, weight: .medium))
                                    .foregroundStyle(appTheme.heading)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(item.count)")
                                    .font(AppTheme.sansSerif(11, weight: .medium))
                                    .foregroundStyle(appTheme.textFaint)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(appTheme.background, in: Capsule())
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    label("4 WEEKS")
                    Spacer()
                    Text("\(activeDays) active")
                        .font(AppTheme.sansSerif(10))
                        .foregroundStyle(appTheme.textFaint)
                }
                activityGrid
            }
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    // MARK: - Activity grid (4 rows × 7 cols = 28 days)

    private var activityGrid: some View {
        VStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { col in
                        let index = row * 7 + col
                        RoundedRectangle(cornerRadius: 3)
                            .fill(activity[index] ? appTheme.accent : appTheme.separator)
                            .frame(maxWidth: .infinity)
                            .frame(height: 14)
                    }
                }
            }
        }
    }

    // MARK: - Summary pills

    private var summaryRow: some View {
        HStack(spacing: 8) {
            summaryPill(title: "Kept", value: "\(Int(stats.kept * 100))%")
            summaryPill(title: "Avg think", value: formattedAvg)
            summaryPill(title: "Active", value: "\(activeDays)/28")
        }
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(AppTheme.sansSerif(13, weight: .semibold))
                .foregroundStyle(appTheme.heading)
                .monospacedDigit()
            Text(title)
                .font(AppTheme.sansSerif(10))
                .foregroundStyle(appTheme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(appTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var formattedAvg: String {
        guard stats.avgSeconds > 0 else { return "—" }
        if stats.avgSeconds < 60 { return "\(Int(stats.avgSeconds))s" }
        let minutes = Int(stats.avgSeconds) / 60
        let seconds = Int(stats.avgSeconds) % 60
        return "\(minutes)m \(seconds)s"
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.sansSerif(10, weight: .medium))
            .foregroundStyle(appTheme.textFaint)
            .tracking(1.6)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        var line: [(Subviews.Element, CGPoint)] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                line.forEach { $0.0.place(at: $0.1, proposal: .unspecified) }
                line = []
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            line.append((subview, CGPoint(x: x, y: y)))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        line.forEach { $0.0.place(at: $0.1, proposal: .unspecified) }
    }
}
