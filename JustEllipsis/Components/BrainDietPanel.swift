import SwiftUI

struct BrainDietPanel: View {
    let viewModel: BrainViewModel
    let selectedTopic: String?
    let onTopicSelected: (String) -> Void

    @Environment(\.appTheme) private var appTheme

    private var stats: (kept: Double, skipped: Double, avgSeconds: Double, avgReadSeconds: Double) {
        viewModel.cachedStats
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.cachedInsightParagraph)
                .font(AppTheme.serif(15))
                .foregroundStyle(appTheme.text)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if stats.kept > 0 || stats.avgReadSeconds > 0 {
                ReflectionStatsRow(stats: stats)
            }

            if !viewModel.cachedWeeklyWords.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(viewModel.cachedWeeklyWords, id: \.self) { word in
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
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

// MARK: - Reflection Stats Row

private struct ReflectionStatsRow: View {
    let stats: (kept: Double, skipped: Double, avgSeconds: Double, avgReadSeconds: Double)

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 0) {
            statCell(label: "Kept", value: "\(Int(stats.kept * 100))%")
            statCell(label: "Skipped", value: "\(Int(stats.skipped * 100))%")
            if stats.avgSeconds > 0 {
                statCell(label: "Avg. reflect", value: formatSeconds(stats.avgSeconds))
            }
            if stats.avgReadSeconds > 0 {
                statCell(label: "Avg. read", value: formatSeconds(stats.avgReadSeconds))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(AppTheme.sansSerif(15, weight: .medium))
                .foregroundStyle(appTheme.heading)
                .monospacedDigit()
            Text(label)
                .font(AppTheme.sansSerif(10))
                .foregroundStyle(appTheme.textFaint)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatSeconds(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 60 { return "\(Int(seconds))s" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return s > 0 ? "\(m)m \(s)s" : "\(m)m"
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
