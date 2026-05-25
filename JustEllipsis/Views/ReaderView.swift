import SwiftUI
import SwiftData

struct ReaderView: View {
    let link: QueuedLink
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage(ReaderTheme.defaultsKey) private var themeRaw: String = "ember"
    @State private var viewModel = ReaderViewModel()
    @State private var pendingEntry: BrainEntry?
    @State private var isNearBottom = false
    @State private var overScrollDelta: CGFloat = 0

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
            await viewModel.load(link: link, context: context)
        }
        .fullScreenCover(item: $pendingEntry) { entry in
            ReflectView(entry: entry, link: link, theme: theme, prompt: viewModel.generatedPrompt, onComplete: {
                viewModel.markAsRead(link: link, context: context)
                updateReadingDay()
                dismiss()
            })
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

    private func errorBannerView(_ error: Error) -> some View {
        VStack(spacing: 0) {
            // Chrome — identical structure to articleView so dismiss is always reachable
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.text.opacity(0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(link.domain ?? domainFromURL(link.url))
                    .font(AppTheme.sansSerif(12, weight: .medium))
                    .foregroundStyle(theme.text.opacity(0.4))

                Spacer()

                Button {
                    UIPasteboard.general.string = link.url
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

            // Error banner
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
                Task { await viewModel.load(link: link, context: context) }
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

    private func domainFromURL(_ raw: String) -> String {
        guard let url = URL(string: raw) else { return raw }
        return ContentFetcher.extractDomain(from: url)
    }

    private func articleView(_ content: StrippedContent) -> some View {
        VStack(spacing: 0) {
            // Top chrome: domain + read time, muted fallback Done
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

                HStack(spacing: 16) {
                    Button {
                        UIPasteboard.general.string = link.url
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.text.opacity(0.4))
                    }
                    .buttonStyle(.plain)

                    // Gesture is the primary path — button is muted for accessibility
                    Button("Done") {
                        openReflect(content: content)
                    }
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(theme.text.opacity(0.5))
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 12)
            .background(theme.bg)

            // Progress indicator
            GeometryReader { geo in
                Rectangle()
                    .fill(theme.accent.opacity(0.4))
                    .frame(width: geo.size.width * viewModel.readProgress, height: 1)
                    .animation(.linear(duration: 0.1), value: viewModel.readProgress)
            }
            .frame(height: 1)

            // Article + pull indicator overlay
            ZStack(alignment: .bottom) {
                ReaderWebView(
                    html: content.body,
                    theme: theme,
                    onScrollProgress: { progress in
                        viewModel.readProgress = progress
                    },
                    onNearBottom: { near in
                        withAnimation(.easeIn(duration: 0.2)) {
                            isNearBottom = near
                        }
                    },
                    onOverScrollDelta: { delta in
                        if delta == 0 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                overScrollDelta = 0
                            }
                        } else {
                            overScrollDelta = delta
                        }
                    },
                    onReflectTrigger: {
                        openReflect(content: content)
                    }
                )

                if isNearBottom {
                    pullIndicator
                        .transition(.opacity)
                }
            }
        }
    }

    private var pullIndicator: some View {
        VStack(spacing: 8) {
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.accent)
                .offset(y: -min(overScrollDelta / 80 * 10, 10))

            Text("reflect")
                .font(AppTheme.sansSerif(10))
                .foregroundStyle(theme.text.opacity(0.5))
                .tracking(2)

            Rectangle()
                .fill(theme.accent.opacity(0.45))
                .frame(height: 1)
        }
        .padding(.top, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [.clear, theme.bg.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func openReflect(content: StrippedContent) {
        let entry = BrainEntry(url: link.url, title: content.title, domain: content.domain)
        entry.wordCount = content.estimatedWordCount
        entry.dna = viewModel.generatedDNA
        pendingEntry = entry
    }

    private func updateReadingDay() {
        let logical = StreakEngine.logicalDay()
        let y = logical.year, m = logical.month, d = logical.day
        let fetchDescriptor = FetchDescriptor<ReadingDay>(
            predicate: #Predicate { $0.year == y && $0.month == m && $0.day == d }
        )
        if let existing = try? context.fetch(fetchDescriptor).first {
            existing.linksRead += 1
        } else {
            let day = ReadingDay(year: logical.year, month: logical.month, day: logical.day)
            day.linksRead = 1
            context.insert(day)
        }
        try? context.save()
    }
}
