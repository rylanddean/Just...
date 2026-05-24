import SwiftUI
import SwiftData

struct BrainView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BrainEntry.readAt, order: .reverse) private var entries: [BrainEntry]
    @State private var viewModel = BrainViewModel()
    @State private var selectedEntry: BrainEntry?

    private var rank: BrainRank { viewModel.rank(for: entries) }
    private var progress: Double { viewModel.progressToNextRank(for: entries) }
    private var displayed: [BrainEntry] { viewModel.filtered(entries) }

    var body: some View {
        NavigationStack {
            List {
                // ── Orb header ────────────────────────────────────────────
                Section {
                    BrainOrb(rank: rank, entryCount: entries.count, progress: progress)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .listRowBackground(AppTheme.background)
                        .listRowSeparator(.hidden)

                    if entries.count > 0, viewModel.entriesUntilNextRank(for: entries) > 0 {
                        Text("\(viewModel.entriesUntilNextRank(for: entries)) more to \(nextRankTitle)")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(AppTheme.textFaint)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(AppTheme.background)
                            .listRowSeparator(.hidden)
                            .padding(.bottom, 8)
                    }
                }

                // ── Entry list ────────────────────────────────────────────
                Section {
                    if displayed.isEmpty {
                        Text(viewModel.searchText.isEmpty
                             ? "Your Brain is empty.\nStart reading to grow it."
                             : "No entries match that search.")
                            .font(AppTheme.sansSerif(14))
                            .foregroundStyle(AppTheme.textFaint)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                            .listRowBackground(AppTheme.background)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(displayed) { entry in
                            BrainEntryRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedEntry = entry }
                                .listRowBackground(AppTheme.background)
                                .listRowSeparatorTint(AppTheme.separator)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteEntry(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .scrollIndicators(.hidden)
            .navigationTitle("Brain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $viewModel.searchText, prompt: "Search your Brain")
        }
        .sheet(item: $selectedEntry) { entry in
            BrainEntryDetail(entry: entry)
        }
    }

    // MARK: - Delete

    private func deleteEntry(_ entry: BrainEntry) {
        if selectedEntry?.id == entry.id { selectedEntry = nil }
        context.delete(entry)
        try? context.save()
    }

    private var nextRankTitle: String {
        let all = BrainRank.allCases
        guard let idx = all.firstIndex(of: rank), idx + 1 < all.count else { return "" }
        return all[idx + 1].rawValue
    }
}

// MARK: - Entry Row

struct BrainEntryRow: View {
    let entry: BrainEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title)
                    .font(AppTheme.sansSerif(14, weight: .medium))
                    .foregroundStyle(AppTheme.heading)
                    .lineLimit(2)

                Spacer()

                Text(entry.readAt.formatted(.relative(presentation: .named)))
                    .font(AppTheme.sansSerif(11))
                    .foregroundStyle(AppTheme.textFaint)
            }

            Text(entry.domain)
                .font(AppTheme.sansSerif(11))
                .foregroundStyle(AppTheme.textFaint)

            if let reflection = entry.reflection, !reflection.isEmpty {
                Text(reflection)
                    .font(AppTheme.serif(13))
                    .foregroundStyle(AppTheme.text.opacity(0.75))
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 14)
    }
}

// MARK: - Entry Detail Sheet

struct BrainEntryDetail: View {
    let entry: BrainEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(entry.title)
                            .font(AppTheme.sansSerif(20, weight: .semibold))
                            .foregroundStyle(AppTheme.heading)

                        HStack(spacing: 8) {
                            Text(entry.domain)
                            Text("·")
                            Text(entry.readAt.formatted(date: .long, time: .omitted))
                        }
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(AppTheme.textFaint)

                        if let reflection = entry.reflection, !reflection.isEmpty {
                            Divider().background(AppTheme.separator)

                            Text(reflection)
                                .font(AppTheme.serif(18))
                                .foregroundStyle(AppTheme.text)
                                .lineSpacing(6)
                        } else {
                            Text("No reflection.")
                                .font(AppTheme.serif(16))
                                .foregroundStyle(AppTheme.textFaint)
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
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationBackground(AppTheme.background)
    }
}
