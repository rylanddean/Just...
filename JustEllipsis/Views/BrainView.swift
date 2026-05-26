import SwiftUI
import SwiftData
import UIKit

struct BrainView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme
    @Query(sort: \BrainEntry.readAt, order: .reverse) private var entries: [BrainEntry]
    @State private var viewModel = BrainViewModel()
    @State private var selectedEntry: BrainEntry?

    private var rank: BrainRank { viewModel.rank(for: entries) }
    private var progress: Double { viewModel.progressToNextRank(for: entries) }
    private var displayed: [BrainEntry] { viewModel.filtered(entries) }
    private var hasSearchQuery: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()

                if entries.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            VStack(spacing: 12) {
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

                        Section {
                            BrainDietPanel(entries: entries, viewModel: viewModel)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(rowInsets)
                        } header: {
                            sectionHeader("BRAIN DIET")
                        }
                        .listSectionSeparator(.hidden)

                        Section {
                            if displayed.isEmpty {
                                VStack(spacing: 6) {
                                    Text("No entries match that search.")
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
                            sectionHeader(hasSearchQuery ? "SEARCH RESULTS" : "TIMELINE")
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
        .sheet(item: $selectedEntry) { entry in
            BrainEntryDetail(entry: entry)
        }
    }

    // MARK: - Delete

    private func deleteEntry(_ entry: BrainEntry) {
        if selectedEntry?.id == entry.id { selectedEntry = nil }
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
        EdgeInsets(
            top: 5,
            leading: AppTheme.pagePadding,
            bottom: 5,
            trailing: AppTheme.pagePadding
        )
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

// MARK: - Entry Row

struct BrainEntryRow: View {
    let entry: BrainEntry

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FaviconView(domain: entry.domain)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(AppTheme.sansSerif(14, weight: .medium))
                    .foregroundStyle(appTheme.heading)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(entry.domain)
                        .lineLimit(1)
                    Text("·")
                    Text(entry.readAt.formatted(.relative(presentation: .named)))
                }
                .font(AppTheme.sansSerif(11))
                .foregroundStyle(appTheme.textFaint)

                if let dna = entry.dna, !dna.isEmpty {
                    Text(dna)
                        .font(AppTheme.sansSerif(11))
                        .foregroundStyle(appTheme.textFaint)
                        .lineLimit(1)
                }

                if let reflection = entry.reflection, !reflection.isEmpty {
                    Text(reflection)
                        .font(AppTheme.serif(13))
                        .foregroundStyle(appTheme.text.opacity(0.75))
                        .lineLimit(2)
                        .padding(.top, 2)
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

// MARK: - Entry Detail Sheet

struct BrainEntryDetail: View {
    let entry: BrainEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @State private var showReread = false

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(entry.title)
                            .font(AppTheme.sansSerif(20, weight: .semibold))
                            .foregroundStyle(appTheme.heading)

                        HStack(spacing: 8) {
                            Text(entry.domain)
                            Text("·")
                            Text(entry.readAt.formatted(date: .long, time: .omitted))
                        }
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(appTheme.textFaint)

                        if let reflection = entry.reflection, !reflection.isEmpty {
                            Divider().background(appTheme.separator)

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
                    Button("Re-read") { showReread = true }
                        .foregroundStyle(appTheme.accent)
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
}
