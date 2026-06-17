import SwiftUI

struct TitleWithRewriteIndicator: View {
    let displayTitle: String
    let originalTitle: String?
    var font: Font = AppTheme.sansSerif(15, weight: .medium)

    @Environment(\.appTheme) private var appTheme
    @State private var showingOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(showingOriginal ? (originalTitle ?? displayTitle) : displayTitle)
                    .font(font)
                    .foregroundStyle(appTheme.heading)
                    .multilineTextAlignment(.leading)

                if originalTitle != nil {
                    Button { showingOriginal.toggle() } label: {
                        Text("✦")
                            .font(AppTheme.sansSerif(10))
                            .foregroundStyle(showingOriginal ? appTheme.textFaint : Color(hex: "#C49A3C"))
                    }
                    .buttonStyle(.plain)
                }
            }

            if showingOriginal, let original = originalTitle {
                Text(original)
                    .font(AppTheme.sansSerif(12))
                    .foregroundStyle(appTheme.textFaint)
                    .lineLimit(2)
            }
        }
    }
}
