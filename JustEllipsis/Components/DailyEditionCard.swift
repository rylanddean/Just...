import SwiftUI

struct DailyEditionCard: View {
    let edition: DailyEdition
    let onTap: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "newspaper")
                    .font(.system(size: 18))
                    .foregroundStyle(appTheme.accent)
                    .frame(width: 32, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Edition")
                        .font(AppTheme.sansSerif(15, weight: .medium))
                        .foregroundStyle(appTheme.heading)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(appTheme.textFaint)
                }

                Spacer()

                if edition.isComplete {
                    Text("Done")
                        .font(AppTheme.mono(11))
                        .foregroundStyle(appTheme.accent.opacity(0.7))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appTheme.textFaint)
                }
            }
            .padding(AppTheme.cardPadding)
            .background(appTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if edition.isComplete {
            return "\(edition.totalCount) article\(edition.totalCount == 1 ? "" : "s") read"
        }
        if edition.hasStarted {
            return "\(edition.articlesRead) of \(edition.totalCount) read"
        }
        return "\(edition.totalCount) article\(edition.totalCount == 1 ? "" : "s")"
    }
}
