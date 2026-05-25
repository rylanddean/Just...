import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(ReaderTheme.defaultsKey) private var themeRaw: String = "ember"
    @AppStorage("streak.minReadsPerDay") private var minReadsPerDay: Int = 1
    @AppStorage(JustEllipsisApp.iCloudSyncKey) private var iCloudSyncEnabled: Bool = false

    @State private var versionTapCount = 0
    @State private var showClearStreakDialog = false
    @State private var showFullResetDialog = false

    private var selectedTheme: ReaderTheme {
        ReaderTheme(rawValue: themeRaw) ?? .ember
    }

    private var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        syncSection
                        streakSection
                        themeSection
                        dangerSection
                        versionFooter
                    }
                    .padding(AppTheme.pagePadding)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(AppTheme.sansSerif(15))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Clear streak?",
            isPresented: $showClearStreakDialog,
            titleVisibility: .visible
        ) {
            Button("Clear streak", role: .destructive) { clearStreak() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your reading streak and daily history will be deleted.")
        }
        .confirmationDialog(
            "Reset everything?",
            isPresented: $showFullResetDialog,
            titleVisibility: .visible
        ) {
            Button("Reset everything", role: .destructive) { resetEverything() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your queue, Brain, streak, and feeds will be deleted. This cannot be undone.")
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SYNC")
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(AppTheme.textFaint)
                .tracking(2)

            if iCloudAvailable {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sync with iCloud")
                                .font(AppTheme.sansSerif(15))
                                .foregroundStyle(AppTheme.heading)
                            Text("Your queue, Brain, and streak sync across devices on this Apple ID.")
                                .font(AppTheme.sansSerif(12))
                                .foregroundStyle(AppTheme.textFaint)
                        }

                        Spacer()

                        Toggle("", isOn: $iCloudSyncEnabled)
                            .labelsHidden()
                            .tint(AppTheme.readerAccent)
                    }

                    if iCloudSyncEnabled {
                        Text("Active the next time you open Just…")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(AppTheme.readerAccent.opacity(0.7))
                    }
                }
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("iCloud is off.")
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(AppTheme.heading)
                        Text("Enable iCloud Drive in Settings to sync.")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(AppTheme.textFaint)
                    }

                    Spacer()

                    Button("Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(AppTheme.readerAccent)
                }
            }
        }
    }

    // MARK: - Streak Section

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("STREAK")
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(AppTheme.textFaint)
                .tracking(2)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reads per day")
                        .font(AppTheme.sansSerif(15))
                        .foregroundStyle(AppTheme.heading)
                    Text("Minimum to count the day.")
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(AppTheme.textFaint)
                }

                Spacer()

                HStack(spacing: 0) {
                    Button {
                        if minReadsPerDay > 1 { minReadsPerDay -= 1 }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(minReadsPerDay > 1 ? AppTheme.accent : AppTheme.textFaint)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)

                    Text("\(minReadsPerDay)")
                        .font(AppTheme.sansSerif(17, weight: .semibold))
                        .foregroundStyle(AppTheme.heading)
                        .monospacedDigit()
                        .frame(minWidth: 28, alignment: .center)

                    Button {
                        if minReadsPerDay < 5 { minReadsPerDay += 1 }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(minReadsPerDay < 5 ? AppTheme.accent : AppTheme.textFaint)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("READER")
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(AppTheme.textFaint)
                .tracking(2)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(ReaderTheme.allCases) { theme in
                    ThemeTile(theme: theme, isSelected: theme == selectedTheme) {
                        handleSelection(theme)
                    }
                }
            }

        }
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DANGER")
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(AppTheme.textFaint)
                .tracking(2)

            Button {
                showFullResetDialog = true
            } label: {
                HStack {
                    Spacer()
                    Text("Reset everything.")
                        .font(AppTheme.sansSerif(15, weight: .medium))
                        .foregroundStyle(AppTheme.danger)
                    Spacer()
                }
                .frame(height: 48)
                .background(AppTheme.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                        .stroke(AppTheme.danger.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Version Footer

    private var versionFooter: some View {
        Button {
            versionTapCount += 1
            if versionTapCount >= 10 {
                showClearStreakDialog = true
                versionTapCount = 0
            }
        } label: {
            Text("Just… \(appVersion) (\(buildNumber))")
                .font(AppTheme.sansSerif(12))
                .foregroundStyle(AppTheme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func handleSelection(_ theme: ReaderTheme) {
        guard theme != selectedTheme else { return }
        themeRaw = theme.rawValue
    }

    private func clearStreak() {
        let days = (try? context.fetch(FetchDescriptor<ReadingDay>())) ?? []
        days.forEach { context.delete($0) }
        try? context.save()
    }

    private func resetEverything() {
        let links = (try? context.fetch(FetchDescriptor<QueuedLink>())) ?? []
        links.forEach { context.delete($0) }
        let entries = (try? context.fetch(FetchDescriptor<BrainEntry>())) ?? []
        entries.forEach { context.delete($0) }
        let days = (try? context.fetch(FetchDescriptor<ReadingDay>())) ?? []
        days.forEach { context.delete($0) }
        let feeds = (try? context.fetch(FetchDescriptor<RSSFeed>())) ?? []
        feeds.forEach { context.delete($0) }
        let articles = (try? context.fetch(FetchDescriptor<RSSArticle>())) ?? []
        articles.forEach { context.delete($0) }
        try? context.save()
    }
}

// MARK: - Theme Tile

private struct ThemeTile: View {
    let theme: ReaderTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                previewArea
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                            .stroke(
                                isSelected ? AppTheme.readerAccent : AppTheme.separator,
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                HStack {
                    Text(theme.displayName)
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(isSelected ? AppTheme.heading : AppTheme.textFaint)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppTheme.readerAccent)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)
            }
        }
        .buttonStyle(.plain)
    }

    private var previewArea: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .fill(theme.bg)
                .frame(height: 96)

            VStack(alignment: .leading, spacing: 6) {
                // Simulated heading
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: theme.headingHex))
                    .frame(width: 52, height: 5)

                // Body line 1
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.text.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)

                // Body line 2
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.text.opacity(0.55))
                    .frame(width: 44, height: 3)

                Spacer().frame(height: 4)

                // Accent line (simulates a link)
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.accent)
                    .frame(width: 36, height: 3)
            }
            .padding(12)
        }
    }
}
