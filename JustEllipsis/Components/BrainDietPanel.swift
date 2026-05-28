import SwiftUI

struct BrainDietPanel: View {
    let entries: [BrainEntry]
    let viewModel: BrainViewModel
    let selectedTopic: String?
    let onTopicSelected: (String) -> Void

    @Environment(\.appTheme) private var appTheme

    private var weeklyWords: [String] { viewModel.weeklyDNA(entries: entries) }
    private var paragraph: String { viewModel.insightParagraph(entries: entries) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(paragraph)
                .font(AppTheme.serif(15))
                .foregroundStyle(appTheme.text)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !weeklyWords.isEmpty {
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
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
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
