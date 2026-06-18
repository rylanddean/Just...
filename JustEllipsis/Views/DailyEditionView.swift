import SwiftUI
import SwiftData

struct DailyEditionView: View {
    let edition: DailyEdition

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    @State private var currentArticleSource: IdentifiableSource? = nil

    var body: some View {
        ZStack {
            appTheme.background.ignoresSafeArea()

            if edition.isComplete {
                completionView
            } else {
                landingView
            }
        }
        .preferredColorScheme(appTheme.colorScheme)
        .fullScreenCover(item: $currentArticleSource, onDismiss: advance) { identifiable in
            ReaderView(source: identifiable.source, editionMode: true)
        }
    }

    // MARK: - Landing

    private var landingView: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(editionDateLabel)
                            .font(AppTheme.mono(12))
                            .foregroundStyle(appTheme.textFaint)
                            .kerning(1)

                        Text("Today's Edition")
                            .font(AppTheme.sansSerif(28, weight: .medium))
                            .foregroundStyle(appTheme.heading)

                        if edition.hasStarted {
                            Text("\(edition.articlesRead) of \(edition.totalCount) read")
                                .font(AppTheme.sansSerif(14))
                                .foregroundStyle(appTheme.textFaint)
                        } else {
                            Text("\(edition.totalCount) article\(edition.totalCount == 1 ? "" : "s")")
                                .font(AppTheme.sansSerif(14))
                                .foregroundStyle(appTheme.textFaint)
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.bottom, 24)

                    Rectangle()
                        .fill(appTheme.separator)
                        .frame(height: 1)

                    // Article list
                    ForEach(0..<edition.totalCount, id: \.self) { index in
                        if let article = edition.article(at: index) {
                            articleRow(article: article, index: index)
                        }
                        Rectangle()
                            .fill(appTheme.separator)
                            .frame(height: 1)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            // Button pinned to bottom
            Button(action: openCurrentArticle) {
                HStack {
                    Spacer()
                    Text(edition.hasStarted ? "Continue Reading" : "Begin Reading")
                        .font(AppTheme.sansSerif(15, weight: .semibold))
                        .foregroundStyle(appTheme.isLight ? .white : appTheme.background)
                    Spacer()
                }
                .frame(height: 48)
                .background(appTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 48)
        }
    }

    private func articleRow(article: (url: String, title: String, domain: String, feedID: UUID?, summary: String?), index: Int) -> some View {
        let isRead = index < edition.currentIndex
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(article.domain)
                    .font(AppTheme.mono(11))
                    .foregroundStyle(appTheme.textFaint)

                Text(article.title)
                    .font(AppTheme.sansSerif(15, weight: .medium))
                    .foregroundStyle(isRead ? appTheme.text.opacity(0.35) : appTheme.heading)
                    .fixedSize(horizontal: false, vertical: true)

                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(AppTheme.sansSerif(13))
                        .foregroundStyle(isRead ? appTheme.text.opacity(0.25) : appTheme.text.opacity(0.5))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if isRead {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(appTheme.accent.opacity(0.5))
                    .padding(.top, 18)
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 16)
    }

    // MARK: - Completion

    private var completionView: some View {
        VStack(spacing: 0) {
            topBar

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Edition complete.")
                    .font(AppTheme.sansSerif(28, weight: .medium))
                    .foregroundStyle(appTheme.heading)

                Text("\(edition.totalCount) article\(edition.totalCount == 1 ? "" : "s") added to your Brain.")
                    .font(AppTheme.sansSerif(15))
                    .foregroundStyle(appTheme.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)

            Spacer()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appTheme.text.opacity(0.5))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 16)
    }

    private var editionDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: edition.date).uppercased()
    }

    // MARK: - Navigation

    private func openCurrentArticle() {
        guard let article = edition.currentArticle else { return }
        currentArticleSource = IdentifiableSource(source: .dailyEdition(
            url: article.url,
            title: article.title,
            domain: article.domain,
            feedID: article.feedID
        ))
    }

    private func advance() {
        guard !edition.isComplete else { return }
        edition.currentIndex += 1
        if edition.currentIndex >= edition.totalCount {
            edition.isComplete = true
        }
        try? context.save()

        guard !edition.isComplete else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            openCurrentArticle()
        }
    }
}

// MARK: - Identifiable wrapper

private struct IdentifiableSource: Identifiable {
    let id = UUID()
    let source: ReadingSource
}
