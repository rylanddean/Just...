import SwiftUI

struct LinkCard: View {
    let link: QueuedLink
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(link.title ?? link.url)
                        .font(AppTheme.sansSerif(15, weight: .medium))
                        .foregroundStyle(AppTheme.heading)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(link.domain ?? domainFromURL(link.url))
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(AppTheme.textFaint)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textFaint)
            }
            .padding(AppTheme.cardPadding)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private func domainFromURL(_ raw: String) -> String {
        guard let url = URL(string: raw) else { return raw }
        return ContentFetcher.extractDomain(from: url)
    }
}
