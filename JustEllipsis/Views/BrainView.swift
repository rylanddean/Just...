import SwiftUI
import SwiftData
import UIKit

struct BrainView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme
    @Query(sort: \BrainEntry.readAt, order: .reverse) private var entries: [BrainEntry]
    @Query(sort: \QuoteEntry.savedAt, order: .reverse) private var quotes: [QuoteEntry]
    @State private var viewModel = BrainViewModel()
    @State private var selectedEntry: BrainEntry?
    @State private var selectedQuote: QuoteEntry?

    private var rank: BrainRank { viewModel.rank(for: entries) }
    private var progress: Double { viewModel.progressToNextRank(for: entries) }
    private var displayed: [BrainEntry] { viewModel.filtered(entries) }
    private var hasSearchQuery: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var hasTopicFilter: Bool { viewModel.selectedTopic != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()

                if entries.isEmpty {
                    emptyState
                } else {
                    List {
                        // RANK
                        Section {
                            VStack(spacing: 10) {
                                BrainOrb(rank: rank, entryCount: entries.count, progress: progress)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 2)

                                if viewModel.entriesUntilNextRank(for: entries) > 0 {
                                    Text("\(viewModel.entriesUntilNextRank(for: entries)) more to \(nextRankTitle)")
                                        .font(AppTheme.sansSerif(12))
                                        .foregroundStyle(appTheme.textFaint)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(AppTheme.cardPadding)
                            .background(appTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(rowInsets)
                        } header: {
                            sectionHeader("RANK")
                        }
                        .listSectionSeparator(.hidden)

                        // ACTIVITY
                        Section {
                            ActivityHeatmapView(entries: entries)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(rowInsets)
                        } header: {
                            sectionHeader("ACTIVITY")
                        }
                        .listSectionSeparator(.hidden)

                        // INSIGHTS (always visible)
                        Section {
                            BrainDietPanel(
                                viewModel: viewModel,
                                selectedTopic: viewModel.selectedTopic,
                                onTopicSelected: { viewModel.toggleTopic($0) }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(rowInsets)
                        } header: {
                            sectionHeader("INSIGHTS")
                        }
                        .listSectionSeparator(.hidden)

                        // QUOTES
                        if !quotes.isEmpty {
                            Section {
                                ForEach(quotes) { quote in
                                    BrainQuoteRow(quote: quote)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedQuote = quote }
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(rowInsets)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                deleteQuote(quote)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            .tint(AppTheme.danger)
                                        }
                                }
                            } header: {
                                sectionHeader("QUOTES")
                            }
                            .listSectionSeparator(.hidden)
                        }

                        // REVISIT (shown once older entries exist with reflections)
                        if let remembered = viewModel.rememberedEntry {
                            Section {
                                RememberCard(entry: remembered) {
                                    selectedEntry = remembered
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(rowInsets)
                            } header: {
                                sectionHeader("REVISIT")
                            }
                            .listSectionSeparator(.hidden)
                        }

                        // TIMELINE (or filtered topic view)
                        Section {
                            if displayed.isEmpty {
                                VStack(spacing: 6) {
                                    Text(hasTopicFilter ? "Nothing tagged \"\(viewModel.selectedTopic ?? "")\"." : "No entries match that search.")
                                        .font(AppTheme.sansSerif(14, weight: .medium))
                                        .foregroundStyle(appTheme.heading)
                                    Text("Try a different keyword.")
                                        .font(AppTheme.sansSerif(13))
                                        .foregroundStyle(appTheme.textFaint)
                                }
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                                .padding(AppTheme.cardPadding)
                                .background(appTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(rowInsets)
                            } else {
                                ForEach(displayed) { entry in
                                    BrainEntryRow(entry: entry)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedEntry = entry }
                                        .contextMenu {
                                            Button {
                                                UIPasteboard.general.string = entry.url
                                            } label: {
                                                Label("Copy Link", systemImage: "link")
                                            }
                                        }
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(rowInsets)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                deleteEntry(entry)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            .tint(AppTheme.danger)
                                        }
                                }
                            }
                        } header: {
                            timelineHeader
                        }
                        .listSectionSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .contentMargins(.bottom, 32, for: .scrollContent)
                }
            }
            .navigationTitle("Brain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(appTheme.background, for: .navigationBar)
            .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .searchable(text: $viewModel.searchText, prompt: "Search your Brain")
        }
        .onAppear {
            viewModel.setRememberedEntry(from: entries)
            viewModel.refreshCacheIfNeeded(entries: entries)
        }
        .onChange(of: entries.count) { _, _ in
            viewModel.refreshCacheIfNeeded(entries: entries)
        }
        .sheet(item: $selectedEntry) { entry in
            BrainEntryDetail(entry: entry)
        }
        .sheet(item: $selectedQuote) { quote in
            QuoteEntryDetail(quote: quote)
        }
    }

    // MARK: - Timeline header

    private var timelineHeader: some View {
        HStack(spacing: 6) {
            if let topic = viewModel.selectedTopic {
                Text(topic.uppercased())
                    .kerning(2)
                    .foregroundStyle(appTheme.accent)

                Button {
                    viewModel.selectedTopic = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(appTheme.accent)
                        .padding(4)
                        .background(appTheme.accent.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            } else {
                Text(hasSearchQuery ? "SEARCH RESULTS" : "TIMELINE")
                    .kerning(2)
                    .foregroundStyle(appTheme.textFaint)
            }
        }
        .font(AppTheme.sansSerif(11, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .listRowInsets(EdgeInsets())
        .background(appTheme.background)
    }

    private func deleteQuote(_ quote: QuoteEntry) {
        if selectedQuote?.id == quote.id { selectedQuote = nil }
        context.delete(quote)
        try? context.save()
    }

    // MARK: - Delete

    private func deleteEntry(_ entry: BrainEntry) {
        if selectedEntry?.id == entry.id { selectedEntry = nil }
        if viewModel.rememberedEntry?.id == entry.id { viewModel.rememberedEntry = nil }
        let url = entry.url
        let descriptor = FetchDescriptor<RSSArticle>(
            predicate: #Predicate { $0.url == url }
        )
        if let article = try? context.fetch(descriptor).first {
            article.isQueued = false
        }
        context.delete(entry)
        try? context.save()
    }

    private var nextRankTitle: String {
        let all = BrainRank.allCases
        guard let idx = all.firstIndex(of: rank), idx + 1 < all.count else { return "" }
        return all[idx + 1].rawValue
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 5, leading: AppTheme.pagePadding, bottom: 5, trailing: AppTheme.pagePadding)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Your Brain is empty.")
                .font(AppTheme.sansSerif(18, weight: .medium))
                .foregroundStyle(appTheme.heading)

            Text("Start reading and reflecting to grow it.")
                .font(AppTheme.sansSerif(14))
                .foregroundStyle(appTheme.textFaint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppTheme.pagePadding)
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(AppTheme.sansSerif(11, weight: .medium))
            .foregroundStyle(appTheme.textFaint)
            .kerning(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .listRowInsets(EdgeInsets())
            .background(appTheme.background)
    }
}

// MARK: - Entry Row (reflection-first)

struct BrainEntryRow: View {
    let entry: BrainEntry

    @Environment(\.appTheme) private var appTheme

    private var hasReflection: Bool {
        !(entry.reflection ?? "").isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FaviconView(domain: entry.domain)

            VStack(alignment: .leading, spacing: 6) {
                // Metadata: domain · date
                HStack(spacing: 6) {
                    Text(entry.domain)
                        .lineLimit(1)
                    Text("·")
                    Text(entry.readAt.formatted(.relative(presentation: .named)))
                }
                .font(AppTheme.sansSerif(11))
                .foregroundStyle(appTheme.textFaint)

                if hasReflection {
                    // Reflection is the hero
                    Text(entry.reflection!)
                        .font(AppTheme.serif(15))
                        .foregroundStyle(appTheme.text)
                        .lineLimit(3)
                        .lineSpacing(2)

                    // Title is context
                    TitleWithRewriteIndicator(
                        displayTitle: entry.displayTitle,
                        originalTitle: entry.rewrittenTitle != nil ? entry.title : nil,
                        font: AppTheme.sansSerif(12, weight: .medium)
                    )
                    .lineLimit(1)
                } else {
                    // No reflection — title is primary
                    TitleWithRewriteIndicator(
                        displayTitle: entry.displayTitle,
                        originalTitle: entry.rewrittenTitle != nil ? entry.title : nil,
                        font: AppTheme.sansSerif(14, weight: .medium)
                    )
                    .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(appTheme.textFaint)
                .padding(.top, 3)
        }
        .padding(AppTheme.cardPadding)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

// MARK: - Remember Card

private struct RememberCard: View {
    let entry: BrainEntry
    let onTap: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(entry.domain)
                        .font(AppTheme.sansSerif(11))
                        .foregroundStyle(appTheme.textFaint)
                    Spacer()
                    Text(entry.readAt.formatted(.relative(presentation: .named)))
                        .font(AppTheme.sansSerif(11))
                        .foregroundStyle(appTheme.textFaint)
                }

                if let reflection = entry.reflection, !reflection.isEmpty {
                    Text(reflection)
                        .font(AppTheme.serif(16))
                        .foregroundStyle(appTheme.text)
                        .lineSpacing(4)
                        .lineLimit(4)
                }

                Text(entry.title)
                    .font(AppTheme.sansSerif(12, weight: .medium))
                    .foregroundStyle(appTheme.textFaint)
                    .lineLimit(1)
            }
            .padding(AppTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    .stroke(appTheme.accent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Entry Detail Sheet

struct BrainEntryDetail: View {
    let entry: BrainEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme
    @State private var showReread = false
    @State private var isEditing = false
    @State private var editedReflection: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        TitleWithRewriteIndicator(
                            displayTitle: entry.displayTitle,
                            originalTitle: entry.rewrittenTitle != nil ? entry.title : nil,
                            font: AppTheme.sansSerif(20, weight: .semibold)
                        )

                        HStack(spacing: 8) {
                            Text(entry.domain)
                            Text("·")
                            Text(entry.readAt.formatted(date: .long, time: .omitted))
                            if entry.readingSeconds > 0 {
                                Text("·")
                                Text(formatReadTime(entry.readingSeconds))
                            }
                        }
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(appTheme.textFaint)

                        Divider().background(appTheme.separator)

                        if isEditing {
                            TextEditor(text: $editedReflection)
                                .font(AppTheme.serif(18))
                                .foregroundStyle(appTheme.text)
                                .scrollContentBackground(.hidden)
                                .background(.clear)
                                .tint(appTheme.accent)
                                .frame(minHeight: 160)
                        } else {
                            if let reflection = entry.reflection, !reflection.isEmpty {
                                Text(reflection)
                                    .font(AppTheme.serif(18))
                                    .foregroundStyle(appTheme.text)
                                    .lineSpacing(6)
                            } else {
                                Text("No reflection.")
                                    .font(AppTheme.serif(16))
                                    .foregroundStyle(appTheme.textFaint)
                                    .italic()
                            }
                        }
                    }
                    .padding(AppTheme.pagePadding)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        if isEditing { saveEdit() }
                        dismiss()
                    }
                    .foregroundStyle(appTheme.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        Button("Save") { saveEdit() }
                            .foregroundStyle(appTheme.accent)
                    } else {
                        Menu {
                            Button("Edit reflection") { beginEdit() }
                            Button("Re-read") { showReread = true }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(appTheme.accent)
                        }
                    }
                }
            }
            .toolbarBackground(appTheme.background, for: .navigationBar)
            .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationBackground(appTheme.background)
        .fullScreenCover(isPresented: $showReread) {
            RereadView(url: entry.url, domain: entry.domain)
        }
    }

    private func formatReadTime(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60) min"
    }

    private func beginEdit() {
        editedReflection = entry.reflection ?? ""
        isEditing = true
    }

    private func saveEdit() {
        let trimmed = editedReflection.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.reflection = trimmed.isEmpty ? nil : trimmed
        try? context.save()
        isEditing = false
    }
}

// MARK: - Quote Row

struct BrainQuoteRow: View {
    let quote: QuoteEntry
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quote.text)
                .font(AppTheme.serif(15))
                .foregroundStyle(appTheme.text)
                .italic()
                .lineLimit(4)
                .lineSpacing(2)

            HStack(spacing: 6) {
                Text(quote.domain)
                Text("·")
                Text(quote.savedAt.formatted(.relative(presentation: .named)))
            }
            .font(AppTheme.sansSerif(11))
            .foregroundStyle(appTheme.textFaint)

            Text(quote.title)
                .font(AppTheme.sansSerif(12, weight: .medium))
                .foregroundStyle(appTheme.textFaint)
                .lineLimit(1)
        }
        .padding(AppTheme.cardPadding)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

// MARK: - Quote Detail Sheet

struct QuoteEntryDetail: View {
    let quote: QuoteEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme
    @State private var showSafari = false

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(quote.text)
                            .font(AppTheme.serif(18))
                            .foregroundStyle(appTheme.text)
                            .italic()
                            .lineSpacing(6)

                        Divider().background(appTheme.separator)

                        Button {
                            showSafari = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(quote.title)
                                    .font(AppTheme.sansSerif(14, weight: .medium))
                                    .foregroundStyle(appTheme.heading)
                                    .multilineTextAlignment(.leading)
                                Text(quote.domain)
                                    .font(AppTheme.sansSerif(12))
                                    .foregroundStyle(appTheme.textFaint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(AppTheme.pagePadding)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(appTheme.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Delete", role: .destructive) {
                            context.delete(quote)
                            try? context.save()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(appTheme.accent)
                    }
                }
            }
            .toolbarBackground(appTheme.background, for: .navigationBar)
            .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationBackground(appTheme.background)
        .sheet(isPresented: $showSafari) {
            if let url = URL(string: quote.url) {
                SafariView(url: url).ignoresSafeArea()
            }
        }
    }
}
