import SwiftUI

struct FeedDirectoryView: View {
    let subscribedURLs: Set<String>
    let onSubscribe: (FeedDirectoryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @State private var selectedCategory: String = "All"
    @State private var searchText = ""

    private let allItems: [FeedDirectoryItem] = FeedDirectoryItem.loadAll()

    private let categories: [String] = {
        var seen = Set<String>()
        var ordered: [String] = ["All"]
        for item in FeedDirectoryItem.loadAll() {
            if seen.insert(item.category).inserted {
                ordered.append(item.category)
            }
        }
        return ordered
    }()

    private var filtered: [FeedDirectoryItem] {
        allItems.filter { item in
            let categoryMatch = selectedCategory == "All" || item.category == selectedCategory
            let searchMatch = searchText.isEmpty
                || item.name.localizedCaseInsensitiveContains(searchText)
                || item.description.localizedCaseInsensitiveContains(searchText)
            return categoryMatch && searchMatch
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    categoryPicker
                        .padding(.vertical, 12)

                    if filtered.isEmpty {
                        Spacer()
                        Text("Nothing here.")
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(appTheme.textFaint)
                        Spacer()
                    } else {
                        List {
                            ForEach(filtered) { item in
                                DirectoryRow(
                                    item: item,
                                    isSubscribed: subscribedURLs.contains(item.url)
                                ) {
                                    onSubscribe(item)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(
                                    top: 4,
                                    leading: AppTheme.pagePadding,
                                    bottom: 4,
                                    trailing: AppTheme.pagePadding
                                ))
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.hidden)
                        .contentMargins(.bottom, 24, for: .scrollContent)
                    }
                }
            }
            .navigationTitle("Browse Feeds")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(appTheme.accent)
                }
            }
            .toolbarBackground(appTheme.background, for: .navigationBar)
            .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
    }

    // MARK: - Category picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category)
                            .font(AppTheme.sansSerif(13, weight: selectedCategory == category ? .semibold : .regular))
                            .foregroundStyle(selectedCategory == category ? appTheme.background : appTheme.textFaint)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                selectedCategory == category
                                    ? appTheme.accent
                                    : appTheme.surface
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
        }
    }
}

// MARK: - Directory row

private struct DirectoryRow: View {
    let item: FeedDirectoryItem
    let isSubscribed: Bool
    let onSubscribe: () -> Void

    @Environment(\.appTheme) private var appTheme
    @State private var justSubscribed = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if item.feedType == .podcast {
                        Image(systemName: "waveform")
                            .font(.system(size: 13))
                            .foregroundStyle(appTheme.textFaint)
                    }
                    Text(item.name)
                        .font(AppTheme.sansSerif(15, weight: .medium))
                        .foregroundStyle(appTheme.heading)
                        .lineLimit(1)
                }

                Text(item.description)
                    .font(AppTheme.sansSerif(12))
                    .foregroundStyle(appTheme.textFaint)
                    .lineLimit(2)
            }

            Spacer()

            if isSubscribed || justSubscribed {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(appTheme.accent)
                    .frame(width: 32, height: 32)
            } else {
                Button {
                    onSubscribe()
                    justSubscribed = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(appTheme.heading)
                        .frame(width: 32, height: 32)
                        .background(appTheme.surface)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(appTheme.separator, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.cardPadding)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}
