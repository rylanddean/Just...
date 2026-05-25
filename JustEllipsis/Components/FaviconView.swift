import SwiftUI

struct FaviconView: View {
    let domain: String
    var size: CGFloat = 28

    private var faviconURL: URL? {
        URL(string: "https://icons.duckduckgo.com/ip3/\(domain).ico")
    }

    var body: some View {
        AsyncImage(url: faviconURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.21))
            default:
                RoundedRectangle(cornerRadius: size * 0.21)
                    .fill(AppTheme.textFaint.opacity(0.12))
                    .frame(width: size, height: size)
                    .overlay {
                        Text(domain.prefix(1).uppercased())
                            .font(AppTheme.sansSerif(13, weight: .medium))
                            .foregroundStyle(AppTheme.textFaint)
                    }
            }
        }
        .frame(width: size, height: size)
    }
}
