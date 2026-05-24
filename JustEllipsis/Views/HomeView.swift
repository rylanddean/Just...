import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \QueuedLink.sortOrder) private var queue: [QueuedLink]
    @Query private var readingDays: [ReadingDay]

    @State private var showAddLink: Bool = false
    @State private var showSettings: Bool = false
    @State private var activeLink: QueuedLink?

    private var streak: Int { StreakEngine.calculateStreak(from: readingDays).current }
    private var isAtRisk: Bool { StreakEngine.isStreakAtRisk(days: readingDays) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                if queue.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        StreakHeader(streak: streak, isAtRisk: isAtRisk)

                        List {
                            ForEach(queue) { link in
                                LinkCard(link: link) {
                                    activeLink = link
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(
                                    top: 5,
                                    leading: AppTheme.pagePadding,
                                    bottom: 5,
                                    trailing: AppTheme.pagePadding
                                ))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteLink(link)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(AppTheme.danger)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.hidden)
                        .contentMargins(.bottom, 32, for: .scrollContent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Just…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddLink = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showAddLink) {
            AddLinkView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(item: $activeLink) { link in
            ReaderView(link: link)
        }
    }

    // MARK: - Actions

    private func deleteLink(_ link: QueuedLink) {
        context.delete(link)
        try? context.save()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            StreakHeader(streak: streak, isAtRisk: isAtRisk)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(spacing: 12) {
                Text("Your queue is empty.")
                    .font(AppTheme.sansSerif(18, weight: .medium))
                    .foregroundStyle(AppTheme.heading)

                Text("Add a link to start reading.")
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(AppTheme.textFaint)
            }

            Spacer()

            Button {
                showAddLink = true
            } label: {
                HStack {
                    Spacer()
                    Text("Add a link")
                        .font(AppTheme.sansSerif(15, weight: .semibold))
                        .foregroundStyle(AppTheme.background)
                    Spacer()
                }
                .frame(height: 48)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.bottom, 32)
        }
    }
}
