import SwiftUI

struct LinkCard: View {
    let link: QueuedLink
    let onTap: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                FaviconView(domain: link.domain ?? domainFromURL(link.url))

                VStack(alignment: .leading, spacing: 4) {
                    Text(link.title ?? link.url)
                        .font(AppTheme.sansSerif(15, weight: .medium))
                        .foregroundStyle(appTheme.heading)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(link.domain ?? domainFromURL(link.url))
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
                if link.source.isRSSPick {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(appTheme.background)
                        .padding(4)
                        .background(appTheme.accent)
                        .clipShape(Circle())
                        .offset(x: 5, y: -5)
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

    private func domainFromURL(_ raw: String) -> String {
        guard let url = URL(string: raw) else { return raw }
        return ContentFetcher.extractDomain(from: url)
    }
}
