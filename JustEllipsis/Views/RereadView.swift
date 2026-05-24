import SwiftUI

struct RereadView: View {
    let url: String
    let domain: String
    @Environment(\.dismiss) private var dismiss

    @AppStorage(ReaderTheme.defaultsKey) private var themeRaw: String = "ember"
    @State private var viewModel = ReaderViewModel()

    private var theme: ReaderTheme {
        ReaderTheme(rawValue: themeRaw) ?? .ember
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            if viewModel.isLoading {
                loadingView
            } else if let content = viewModel.content {
                articleView(content)
            } else if let error = viewModel.error {
                errorBannerView(error)
            }
        }
        .task {
            await viewModel.loadURL(url)
        }
        .preferredColorScheme(theme.colorScheme)
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(theme.accent)
            Text("Fetching article…")
                .font(AppTheme.sansSerif(13))
                .foregroundStyle(theme.text.opacity(0.5))
        }
    }

    private func articleView(_ content: StrippedContent) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.text.opacity(0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 1) {
                    Text(content.domain)
                        .font(AppTheme.sansSerif(12, weight: .medium))
                        .foregroundStyle(theme.text.opacity(0.5))

                    Text("\(content.estimatedReadingMinutes) min read")
                        .font(AppTheme.sansSerif(10))
                        .foregroundStyle(theme.text.opacity(0.3))
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = url
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 12)
            .background(theme.bg)

            Rectangle()
                .fill(theme.text.opacity(0.08))
                .frame(height: 1)

            ReaderWebView(
                html: content.body,
                theme: theme,
                onScrollProgress: { _ in },
                onNearBottom: { _ in },
                onOverScrollDelta: { _ in },
                onReflectTrigger: { }
            )
        }
    }

    private func errorBannerView(_ error: Error) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.text.opacity(0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(domain)
                    .font(AppTheme.sansSerif(12, weight: .medium))
                    .foregroundStyle(theme.text.opacity(0.4))

                Spacer()

                Button {
                    UIPasteboard.general.string = url
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.text.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 12)
            .background(theme.bg)

            Rectangle()
                .fill(theme.text.opacity(0.08))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.text.opacity(0.35))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't load this link.")
                        .font(AppTheme.sansSerif(14, weight: .medium))
                        .foregroundStyle(theme.heading)

                    Text(friendlyErrorMessage(for: error))
                        .font(AppTheme.sansSerif(13))
                        .foregroundStyle(theme.text.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(AppTheme.pagePadding)
            .background(theme.text.opacity(0.05))

            Button("Try again") {
                Task { await viewModel.loadURL(url) }
            }
            .font(AppTheme.sansSerif(14, weight: .medium))
            .foregroundStyle(theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 20)

            Spacer()
        }
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No connection. Try again when you're online."
            case .timedOut, .cannotConnectToHost, .cannotFindHost:
                return "The server didn't respond. Try again later."
            default:
                return "Something went wrong. Try again later."
            }
        }
        if let fetchError = error as? ContentFetcher.FetchError {
            switch fetchError {
            case .invalidURL:
                return "This doesn't appear to be a valid link."
            case .emptyContent:
                return "This link didn't return readable content. It may be paywalled or require JavaScript."
            case .httpError(let code) where code == 404:
                return "This link no longer exists."
            case .httpError(let code) where code >= 400 && code < 500:
                return "This link isn't publicly accessible. It may require a login."
            case .httpError:
                return "The server returned an error. Try again later."
            }
        }
        return "Something went wrong. Try again later."
    }
}
