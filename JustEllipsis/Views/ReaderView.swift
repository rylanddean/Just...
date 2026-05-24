import SwiftUI
import SwiftData

struct ReaderView: View {
    let link: QueuedLink
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = ReaderViewModel()
    @State private var pendingEntry: BrainEntry?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if let content = viewModel.content {
                articleView(content)
            }
        }
        .task {
            await viewModel.load(link: link, context: context)
        }
        // Use item: so the entry is passed directly into the closure —
        // no bool/optional race condition that produces an empty black cover.
        .fullScreenCover(item: $pendingEntry) { entry in
            ReflectView(entry: entry, link: link, onComplete: {
                viewModel.markAsRead(link: link, context: context)
                updateReadingDay()
                pendingEntry = nil
                dismiss()
            })
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(AppTheme.readerAccent)
            Text("Fetching article…")
                .font(AppTheme.sansSerif(13))
                .foregroundStyle(AppTheme.textFaint)
        }
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 20) {
            Text("Couldn't load this article.")
                .font(AppTheme.sansSerif(16, weight: .medium))
                .foregroundStyle(AppTheme.heading)

            Text(error.localizedDescription)
                .font(AppTheme.sansSerif(13))
                .foregroundStyle(AppTheme.textFaint)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Retry") {
                    Task { await viewModel.load(link: link, context: context) }
                }
                .font(AppTheme.sansSerif(14, weight: .medium))
                .foregroundStyle(AppTheme.accent)

                Button("Close") { dismiss() }
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(AppTheme.textFaint)
            }
        }
        .padding(AppTheme.pagePadding)
    }

    private func articleView(_ content: StrippedContent) -> some View {
        VStack(spacing: 0) {
            // Top chrome: domain + read time
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.textFaint)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 1) {
                    Text(content.domain)
                        .font(AppTheme.sansSerif(12, weight: .medium))
                        .foregroundStyle(AppTheme.textFaint)

                    Text("\(content.estimatedReadingMinutes) min read")
                        .font(AppTheme.sansSerif(10))
                        .foregroundStyle(AppTheme.textFaint.opacity(0.6))
                }

                Spacer()

                Button("Done") {
                    openReflect(content: content)
                }
                .font(AppTheme.sansSerif(14, weight: .medium))
                .foregroundStyle(AppTheme.readerAccent)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 12)
            .background(AppTheme.background)

            // Progress indicator
            GeometryReader { geo in
                Rectangle()
                    .fill(AppTheme.readerAccent.opacity(0.4))
                    .frame(width: geo.size.width * viewModel.readProgress, height: 1)
                    .animation(.linear(duration: 0.1), value: viewModel.readProgress)
            }
            .frame(height: 1)

            // Article content
            ReaderWebView(html: content.body) { progress in
                viewModel.readProgress = progress
            }
        }
    }

    // MARK: - Actions

    private func openReflect(content: StrippedContent) {
        let entry = BrainEntry(url: link.url, title: content.title, domain: content.domain)
        entry.wordCount = content.estimatedWordCount
        pendingEntry = entry   // non-nil → cover is presented immediately
    }

    private func updateReadingDay() {
        let logical = StreakEngine.logicalDay()
        // #Predicate requires local constants — it doesn't support tuple member access
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
