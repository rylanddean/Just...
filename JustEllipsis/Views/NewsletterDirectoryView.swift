import SwiftUI

struct NewsletterDirectoryView: View {
    /// Called when the user taps Subscribe on a row.
    /// The caller is responsible for opening AddNewsletterSheet with the item's URL pre-filled.
    let onSelect: (NewsletterDirectoryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    @State private var selectedCategory: String = "All"
    @State private var searchText = ""

    private let allItems: [NewsletterDirectoryItem] = NewsletterDirectoryItem.loadAll()

    private let categories: [String] = {
        var seen = Set<String>()
        var ordered: [String] = ["All"]
        for item in NewsletterDirectoryItem.loadAll() {
            if seen.insert(item.category).inserted {
                ordered.append(item.category)
            }
        }
        return ordered
    }()

    private var filtered: [NewsletterDirectoryItem] {
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
                                NewsletterDirectoryRow(item: item) {
                                    onSelect(item)
                                    dismiss()
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
            .navigationTitle("Browse Newsletters")
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
                        Text(shortCategoryName(category))
                            .font(AppTheme.sansSerif(13, weight: selectedCategory == category ? .semibold : .regular))
                            .foregroundStyle(selectedCategory == category ? appTheme.background : appTheme.textFaint)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(selectedCategory == category ? appTheme.accent : appTheme.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
        }
    }

    /// Shorten verbose category names so they fit comfortably in the pill picker.
    private func shortCategoryName(_ category: String) -> String {
        switch category {
        case "Artificial Intelligence / Machine Learning / Big Data": return "AI / ML"
        case "Technology in General":                                 return "Technology"
        case "Backend Development":                                   return "Backend"
        case "Career and growth":                                     return "Career"
        case "Awesome news":                                          return "News"
        case "Blockchain / Cryptocurrencies":                         return "Crypto"
        default:                                                       return category
        }
    }
}

// MARK: - Row

private struct NewsletterDirectoryRow: View {
    let item: NewsletterDirectoryItem
    let onSubscribe: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(AppTheme.sansSerif(15, weight: .medium))
                    .foregroundStyle(appTheme.heading)
                    .lineLimit(1)

                if !item.description.isEmpty {
                    Text(item.description)
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(appTheme.textFaint)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button {
                onSubscribe()
            } label: {
                Text("Subscribe")
                    .font(AppTheme.sansSerif(12, weight: .medium))
                    .foregroundStyle(appTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(appTheme.accentFaint)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.cardPadding)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}
