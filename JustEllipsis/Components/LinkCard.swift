import SwiftUI
import SwiftData

struct LinkCard: View {
    let link: QueuedLink
    let onTap: () -> Void

    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var showNoTranscriptSheet = false

    var body: some View {
        Group {
            if link.isEpisode && link.transcriptState == .unavailable {
                noTranscriptCard
            } else if link.isEpisode && link.transcriptState == .generating {
                generatingCard
            } else {
                standardCard
            }
        }
        .confirmationDialog(
            link.title ?? "Episode",
            isPresented: $showNoTranscriptSheet,
            titleVisibility: .visible
        ) {
            Button("Open in Podcasts") {
                if let url = URL(string: link.url) { openURL(url) }
            }
            Button("Remove from queue", role: .destructive) {
                context.delete(link)
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No transcript.")
        }
    }

    // MARK: - Standard card (article or ready episode)

    private var standardCard: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                if !link.isEpisode {
                    FaviconView(domain: link.domain ?? domainFromURL(link.url))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(link.title ?? link.url)
                        .font(AppTheme.sansSerif(15, weight: .medium))
                        .foregroundStyle(appTheme.heading)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(link.isEpisode ? (link.showName ?? link.domain ?? domainFromURL(link.url))
                                        : (link.domain ?? domainFromURL(link.url)))
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(appTheme.textFaint)
                }

                Spacer()

                if link.prefetchState == .invalid {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(appTheme.textFaint)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appTheme.textFaint)
                }
            }
            .padding(AppTheme.cardPadding)
            .background(appTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .overlay(alignment: .topTrailing) {
                if link.isEpisode {
                    episodeBadge
                } else if link.source.isRSSPick {
                    rssDot
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = link.url
            } label: {
                Label("Copy link", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Generating card (shimmer + still-thinking tap)

    private var generatingCard: some View {
        Button {
            // No-op — "Still thinking." feedback is purely visual
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(link.title ?? link.url)
                        .font(AppTheme.sansSerif(15, weight: .medium))
                        .foregroundStyle(appTheme.heading.opacity(0.5))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .redacted(reason: .placeholder)
                        .shimmer(tint: appTheme.accentFaint)

                    Text("Still thinking.")
                        .font(AppTheme.mono(12))
                        .foregroundStyle(appTheme.textFaint)
                }

                Spacer()
            }
            .padding(AppTheme.cardPadding)
            .background(appTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .overlay(alignment: .topTrailing) { episodeBadge }
        }
        .buttonStyle(.plain)
    }

    // MARK: - No-transcript card (muted, action sheet on tap)

    private var noTranscriptCard: some View {
        Button {
            showNoTranscriptSheet = true
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(link.title ?? link.url)
                        .font(AppTheme.sansSerif(15, weight: .medium))
                        .foregroundStyle(appTheme.textFaint)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text("No transcript.")
                        .font(AppTheme.mono(12))
                        .foregroundStyle(appTheme.textFaint.opacity(0.6))
                }

                Spacer()
            }
            .padding(AppTheme.cardPadding)
            .background(appTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .overlay(alignment: .topTrailing) { episodeBadge }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared subviews

    private var episodeBadge: some View {
        Text("EPISODE")
            .font(AppTheme.mono(9, weight: .medium))
            .foregroundStyle(appTheme.textFaint)
            .kerning(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(appTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(appTheme.separator, lineWidth: 0.5))
            .offset(x: 5, y: -5)
    }

    private var rssDot: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(appTheme.background)
            .padding(4)
            .background(appTheme.accent)
            .clipShape(Circle())
            .offset(x: 5, y: -5)
    }

    private func domainFromURL(_ raw: String) -> String {
        guard let url = URL(string: raw) else { return raw }
        return ContentFetcher.extractDomain(from: url)
    }
}

// MARK: - Shimmer modifier

private struct ShimmerModifier: ViewModifier {
    let tint: Color
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: tint.opacity(0), location: phase - 0.3),
                        .init(color: tint.opacity(0.6), location: phase),
                        .init(color: tint.opacity(0), location: phase + 0.3)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

private extension View {
    func shimmer(tint: Color) -> some View {
        modifier(ShimmerModifier(tint: tint))
    }
}
